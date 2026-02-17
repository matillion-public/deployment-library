#!/usr/bin/env bash
# =============================================================================
# run-check.sh — Matillion Agent Pre-Deployment Check Orchestrator
#
# Auto-discovers the Matillion agent pod using Helm chart labels, performs
# cluster-level checks (security DaemonSets, K8s version, PSS), then copies
# and executes the in-pod validation script.
#
# Usage:
#   ./run-check.sh                                    # auto-discover everything
#   ./run-check.sh --namespace matillion               # target namespace
#   ./run-check.sh --release my-release               # target Helm release
#   ./run-check.sh --pod <pod-name> -n <namespace>    # skip discovery
#   ./run-check.sh --kubeconfig /path/to/kubeconfig   # custom kubeconfig
#
# Exit code: 0 = all critical pass, 1 = any critical fail.
# =============================================================================
set -uo pipefail

VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IN_POD_SCRIPT="${SCRIPT_DIR}/pre-deployment-check.sh"

# ---------------------------------------------------------------------------
# Colors (auto-disable if not a terminal)
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    DIM='\033[2m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' CYAN='' BOLD='' DIM='' NC=''
fi

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
NAMESPACE=""
RELEASE=""
POD_NAME=""
KUBECONFIG_ARG=""
LABEL_NAME="app.kubernetes.io/name=matillion-agent"

# ---------------------------------------------------------------------------
# Counters & issue collector (cluster-level)
# ---------------------------------------------------------------------------
CLUSTER_PASS=0
CLUSTER_WARN=0
CLUSTER_FAIL=0
CLUSTER_INFO=0

ISSUES=()  # "LEVEL|message|remediation"

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
c_pass()   { ((CLUSTER_PASS++)); echo -e "  ${GREEN}[PASS]${NC} $*"; }
c_warn()   { ((CLUSTER_WARN++)); echo -e "  ${YELLOW}[WARN]${NC} $*"; }
c_fail()   { ((CLUSTER_FAIL++)); echo -e "  ${RED}[FAIL]${NC} $*"; }
c_info()   { ((CLUSTER_INFO++)); echo -e "  ${CYAN}[INFO]${NC} $*"; }
detail()   { echo -e "         ${DIM}$*${NC}"; }

add_issue() {
    ISSUES+=("$1|$2|$3")
}

# ---------------------------------------------------------------------------
# Box helper — pads plain text to fixed width inside ║ ... ║
# ---------------------------------------------------------------------------
BOX_W=60
box_top()    { echo -e "${BOLD}╔$(printf '═%.0s' $(seq 1 $BOX_W))╗${NC}"; }
box_bottom() { echo -e "${BOLD}╚$(printf '═%.0s' $(seq 1 $BOX_W))╝${NC}"; }
box_blank()  { echo -e "${BOLD}║$(printf ' %.0s' $(seq 1 $BOX_W))║${NC}"; }
box_line() {
    local plain="$1" formatted="${2:-$1}"
    local pad=$((BOX_W - 2 - ${#plain}))
    [[ $pad -lt 0 ]] && pad=0
    echo -e "${BOLD}║${NC}  ${formatted}$(printf ' %.0s' $(seq 1 $pad))${BOLD}║${NC}"
}

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  -n, --namespace <ns>       Target namespace (default: auto-discover)
  -r, --release <release>    Helm release name (narrows pod search)
  -p, --pod <pod>            Skip discovery, use this pod directly
  -k, --kubeconfig <path>    Path to kubeconfig file
  -h, --help                 Show this help

Examples:
  $(basename "$0")                            # auto-discover
  $(basename "$0") -n matillion               # target namespace
  $(basename "$0") -n matillion -r my-agent   # specific release
  $(basename "$0") -p my-pod -n matillion     # specific pod
EOF
    exit 0
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--namespace) NAMESPACE="$2"; shift 2 ;;
        -r|--release)   RELEASE="$2";   shift 2 ;;
        -p|--pod)       POD_NAME="$2";  shift 2 ;;
        -k|--kubeconfig) KUBECONFIG_ARG="$2"; shift 2 ;;
        -h|--help)      usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

# ---------------------------------------------------------------------------
# kubectl wrapper (injects --kubeconfig if set)
# ---------------------------------------------------------------------------
kc() {
    if [[ -n "$KUBECONFIG_ARG" ]]; then
        kubectl --kubeconfig "$KUBECONFIG_ARG" "$@"
    else
        kubectl "$@"
    fi
}

# ---------------------------------------------------------------------------
# kc_safe — run kubectl and detect auth/permission/connection errors
#
# Usage:  kc_safe "description" <kubectl args...>
# Result: Sets KC_OUT (stdout), KC_ERR (stderr), KC_RC (0=ok, 1=error).
#         On auth/permission/connection errors, reports via c_fail/c_warn
#         and adds to ISSUES. Runs in the current shell (not a subshell)
#         so counters and ISSUES are correctly updated.
# ---------------------------------------------------------------------------
KC_OUT=""
KC_ERR=""
KC_RC=0
kc_safe() {
    local description="$1"; shift
    local err_file
    err_file=$(mktemp 2>/dev/null || echo "/tmp/_kc_err_$$")
    KC_OUT=""
    KC_ERR=""
    KC_RC=0

    KC_OUT=$(kc "$@" 2>"$err_file") || true
    KC_ERR=$(cat "$err_file" 2>/dev/null)
    rm -f "$err_file" 2>/dev/null

    if [[ -n "$KC_ERR" ]]; then
        if echo "$KC_ERR" | grep -qi 'unauthorized\|authentication\|token.*expired\|login\|certificate.*expired'; then
            c_fail "Authentication error during: ${description}"
            detail "kubectl returned: $(echo "$KC_ERR" | head -1)"
            add_issue "FAIL" "Authentication failed: ${description}" \
                "Check your kubeconfig, token expiry, and cluster credentials. Try: kubectl cluster-info"
            KC_RC=1
            return 1
        elif echo "$KC_ERR" | grep -qi 'forbidden\|cannot list\|cannot get\|access denied'; then
            c_warn "Permission denied during: ${description}"
            detail "kubectl returned: $(echo "$KC_ERR" | head -1)"
            add_issue "WARN" "Insufficient RBAC permissions: ${description}" \
                "The current user/ServiceAccount lacks permissions. Grant the necessary RBAC roles or run with a more privileged kubeconfig."
            KC_RC=1
            return 1
        elif echo "$KC_ERR" | grep -qi 'connection refused\|was refused\|no such host\|timeout\|unable to connect\|dial tcp'; then
            c_fail "Connection error during: ${description}"
            detail "kubectl returned: $(echo "$KC_ERR" | head -1)"
            add_issue "FAIL" "Cannot connect to cluster: ${description}" \
                "Check cluster endpoint, network connectivity, and firewall rules. Verify your IP is in the API server authorized ranges."
            KC_RC=1
            return 1
        elif echo "$KC_ERR" | grep -qi 'not found\|NotFound'; then
            # Not an auth error — pass through for caller to handle
            KC_RC=2
            return 2
        fi
    fi

    KC_RC=0
    return 0
}

# ---------------------------------------------------------------------------
# Pre-flight: check dependencies
# ---------------------------------------------------------------------------
if ! command -v kubectl >/dev/null 2>&1; then
    echo -e "${RED}ERROR:${NC} kubectl not found on PATH. Install kubectl and try again."
    exit 1
fi

if [[ ! -f "$IN_POD_SCRIPT" ]]; then
    echo -e "${RED}ERROR:${NC} Cannot find in-pod script at ${IN_POD_SCRIPT}"
    echo "       Ensure pre-deployment-check.sh is in the same directory as this script."
    exit 1
fi

# ---------------------------------------------------------------------------
# Header
# ---------------------------------------------------------------------------
HEADER_DATE=$(date -u '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null || date '+%Y-%m-%d %H:%M:%S')
echo ""
box_top
box_line "Matillion Agent Pre-Deployment Check v${VERSION}"
box_line "${HEADER_DATE}"
box_bottom
echo ""

# ---------------------------------------------------------------------------
# Pre-flight: cluster connectivity & authentication
# ---------------------------------------------------------------------------
echo -e "${BOLD}── Cluster Connectivity ────────────────────────────────────${NC}"
echo ""

kc_safe "cluster authentication" cluster-info
if [[ $KC_RC -ne 0 ]]; then
    echo ""
    box_top
    box_line "RESULT: FAIL — cannot connect to cluster" "${RED}RESULT: FAIL${NC} — cannot connect to cluster"
    box_bottom
    exit 1
fi
c_pass "Cluster connection and authentication OK"

# Quick RBAC check — can we list pods?
RBAC_TEST=$(kc auth can-i list pods 2>/dev/null || echo "no")
if [[ "$RBAC_TEST" != "yes" ]]; then
    c_warn "Current user may have limited permissions (cannot list pods cluster-wide)"
    detail "Some checks may be skipped. Results with [SKIP] indicate permission issues."
fi
echo ""

# ========================= CLUSTER-LEVEL CHECKS ============================
echo -e "${BOLD}── Cluster Checks ──────────────────────────────────────────${NC}"
echo ""

# --- C3: Kubernetes version ---
kc_safe "get Kubernetes version" version -o yaml
K8S_VERSION=$(echo "$KC_OUT" | grep -m1 gitVersion | awk '{print $2}' 2>/dev/null || true)
if [[ -n "$K8S_VERSION" ]]; then
    K8S_MINOR=$(echo "$K8S_VERSION" | sed -E 's/v?([0-9]+)\.([0-9]+).*/\2/')
    if [[ -n "$K8S_MINOR" && "$K8S_MINOR" =~ ^[0-9]+$ ]]; then
        if [[ "$K8S_MINOR" -lt 29 ]]; then
            c_warn "Kubernetes version: ${K8S_VERSION} (may be end-of-life — check support matrix)"
            add_issue "WARN" "Kubernetes ${K8S_VERSION} may be end-of-life" \
                "Upgrade the cluster to a supported Kubernetes version (>= 1.29). See: https://kubernetes.io/releases/"
        else
            c_pass "Kubernetes version: ${K8S_VERSION} (supported)"
        fi
    else
        c_info "Kubernetes version: ${K8S_VERSION}"
    fi
else
    c_warn "Could not determine Kubernetes version"
fi

# --- C1: Scan for security DaemonSets ---
# Ordered list: most-specific patterns first to avoid "falco" matching "falcon-sensor"
SECURITY_PATTERNS=(
    "falcon-container-sensor:CrowdStrike Falcon"
    "falcon-node-sensor:CrowdStrike Falcon"
    "falcon-sensor:CrowdStrike Falcon"
    "microsoft-defender:Microsoft Defender"
    "twistlock-defender-ds:Twistlock/Prisma Cloud"
    "neuvector-enforcer-pod:NeuVector"
    "sysdig-agent:Sysdig"
    "aqua-enforcer:Aqua Security"
    "falco:Falco"
)

SECURITY_FOUND=()

kc_safe "list DaemonSets (cluster-wide)" get daemonsets --all-namespaces \
    -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.spec.template.spec.containers[0].image}{"\n"}{end}'
ALL_DS="$KC_OUT"

if [[ -n "$ALL_DS" ]]; then
    while IFS=$'\t' read -r ds_ns ds_name ds_image; do
        [[ -z "$ds_name" ]] && continue
        for entry in "${SECURITY_PATTERNS[@]}"; do
            pattern="${entry%%:*}"
            PRODUCT="${entry#*:}"
            if [[ "$ds_name" == *"$pattern"* ]]; then
                c_warn "${PRODUCT} detected: ${ds_name} DaemonSet in ${ds_ns} namespace"
                detail "Image: ${ds_image:-unknown}"

                if [[ "$PRODUCT" == "CrowdStrike Falcon" ]]; then
                    detail "** CrowdStrike container drift detection may block Python file-based execution **"
                    add_issue "WARN" "CrowdStrike Falcon detected (${ds_name} in ${ds_ns})" \
                        "CrowdStrike's container drift detection can kill Python processes invoked with file arguments (exit 137). If in-pod Python file checks fail, create an exclusion for the Matillion agent container image in the CrowdStrike console."
                fi

                SECURITY_FOUND+=("${ds_ns}/${ds_name}|${PRODUCT}")
                break
            fi
        done
    done <<< "$ALL_DS"
fi

if [[ ${#SECURITY_FOUND[@]} -eq 0 && $KC_RC -eq 0 ]]; then
    c_pass "No known security DaemonSets detected"
fi

# --- Auto-discover Matillion agent pod ---
echo ""
echo -e "  ${BOLD}--- Pod Discovery ---${NC}"

if [[ -z "$POD_NAME" ]]; then
    SELECTOR="$LABEL_NAME"
    if [[ -n "$RELEASE" ]]; then
        SELECTOR="${SELECTOR},app.kubernetes.io/instance=${RELEASE}"
    fi

    NS_FLAG=()
    if [[ -n "$NAMESPACE" ]]; then
        NS_FLAG=("-n" "$NAMESPACE")
    else
        NS_FLAG=("--all-namespaces")
    fi

    kc_safe "list pods with selector ${SELECTOR}" get pods "${NS_FLAG[@]}" -l "$SELECTOR" \
        -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.status.phase}{"\t"}{.spec.nodeName}{"\t"}{.status.containerStatuses[0].restartCount}{"\n"}{end}'
    POD_DATA="$KC_OUT"

    if [[ $KC_RC -ne 0 ]]; then
        # kc_safe already reported auth/permission/connection error
        echo ""
        box_top
        box_line "RESULT: FAIL — could not list pods" "${RED}RESULT: FAIL${NC} — could not list pods"
        box_bottom
        exit 1
    fi

    if [[ -z "$POD_DATA" ]]; then
        echo ""
        c_fail "No Matillion agent pods found with selector: ${SELECTOR}"
        detail "Hint: check namespace (--namespace) or release name (--release)"
        detail "Run: kubectl get pods --all-namespaces -l ${LABEL_NAME}"
        add_issue "FAIL" "No agent pods found with selector: ${SELECTOR}" \
            "Ensure the Matillion agent Helm chart is deployed. Verify with: kubectl get pods --all-namespaces -l ${LABEL_NAME}"
        echo ""
        box_top
        box_line "RESULT: FAIL — could not discover agent pod" "${RED}RESULT: FAIL${NC} — could not discover agent pod"
        box_bottom
        exit 1
    fi

    FOUND_NS=""
    FOUND_POD=""
    FOUND_NODE=""
    FOUND_RESTARTS=""
    FOUND_PHASE=""

    while IFS=$'\t' read -r p_ns p_name p_phase p_node p_restarts; do
        [[ -z "$p_name" ]] && continue
        if [[ "$p_phase" == "Running" && -z "$FOUND_POD" ]]; then
            FOUND_NS="$p_ns"
            FOUND_POD="$p_name"
            FOUND_NODE="$p_node"
            FOUND_RESTARTS="$p_restarts"
            FOUND_PHASE="$p_phase"
        fi
        c_info "Found pod: ${p_ns}/${p_name} (${p_phase}, node: ${p_node}, restarts: ${p_restarts:-0})"
    done <<< "$POD_DATA"

    if [[ -z "$FOUND_POD" ]]; then
        c_fail "Found agent pods but none are in Running state"
        add_issue "FAIL" "No agent pods in Running state" \
            "Check pod events with: kubectl describe pod <pod-name> -n <namespace>. Look for CrashLoopBackOff, ImagePullBackOff, or resource constraints."
        echo ""
        box_top
        box_line "RESULT: FAIL — no running agent pod" "${RED}RESULT: FAIL${NC} — no running agent pod"
        box_bottom
        exit 1
    fi

    POD_NAME="$FOUND_POD"
    NAMESPACE="$FOUND_NS"
    AGENT_NODE="$FOUND_NODE"

    echo ""
else
    if [[ -z "$NAMESPACE" ]]; then
        echo -e "${RED}ERROR:${NC} --namespace is required when using --pod"
        exit 1
    fi
    kc_safe "get pod details for ${POD_NAME}" get pod "$POD_NAME" -n "$NAMESPACE" \
        -o jsonpath='{.spec.nodeName}{"\t"}{.status.containerStatuses[0].restartCount}{"\t"}{.status.phase}'
    if [[ $KC_RC -ne 0 ]]; then
        if [[ $KC_RC -eq 2 ]]; then
            c_fail "Pod ${POD_NAME} not found in namespace ${NAMESPACE}"
            add_issue "FAIL" "Pod ${POD_NAME} not found" \
                "Check the pod name and namespace. Run: kubectl get pods -n ${NAMESPACE}"
        fi
        echo ""
        box_top
        box_line "RESULT: FAIL — cannot access specified pod" "${RED}RESULT: FAIL${NC} — cannot access specified pod"
        box_bottom
        exit 1
    fi
    IFS=$'\t' read -r AGENT_NODE FOUND_RESTARTS FOUND_PHASE <<< "$KC_OUT"
    FOUND_RESTARTS="${FOUND_RESTARTS:-0}"
    FOUND_PHASE="${FOUND_PHASE:-unknown}"
fi

# --- C5: Pod status and restart count ---
c_info "Agent pod: ${POD_NAME} (${FOUND_PHASE:-unknown}, ${FOUND_RESTARTS:-0} restarts)"
if [[ -n "$FOUND_RESTARTS" && "$FOUND_RESTARTS" =~ ^[0-9]+$ && "$FOUND_RESTARTS" -gt 5 ]]; then
    c_warn "Agent pod has ${FOUND_RESTARTS} restarts — investigate restart reasons"
    add_issue "WARN" "Agent pod has ${FOUND_RESTARTS} restarts" \
        "High restart count indicates recurring failures. Check logs: kubectl logs ${POD_NAME} -n ${NAMESPACE} --previous"
fi

# --- C2: Security DaemonSet pods on agent's node ---
if [[ -n "$AGENT_NODE" && ${#SECURITY_FOUND[@]} -gt 0 ]]; then
    echo ""
    echo -e "  ${BOLD}--- Security Agents on Node: ${AGENT_NODE} ---${NC}"
    for entry in "${SECURITY_FOUND[@]}"; do
        ds_ref="${entry%%|*}"
        ds_product="${entry##*|}"
        ds_ns="${ds_ref%%/*}"
        ds_ds_name="${ds_ref##*/}"

        kc_safe "list ${ds_product} pods on node ${AGENT_NODE}" get pods -n "$ds_ns" \
            --field-selector "spec.nodeName=${AGENT_NODE}" \
            -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.phase}{"\n"}{end}'
        [[ $KC_RC -ne 0 ]] && continue

        if [[ -n "$KC_OUT" ]]; then
            while IFS=$'\t' read -r np_name np_phase; do
                [[ -z "$np_name" ]] && continue
                if [[ "$np_name" == *"$ds_ds_name"* || "$np_name" == *"falcon"* || "$np_name" == *"defender"* || "$np_name" == *"falco"* || "$np_name" == *"sysdig"* || "$np_name" == *"twistlock"* || "$np_name" == *"aqua"* || "$np_name" == *"neuvector"* ]]; then
                    c_warn "${ds_product} pod running on agent node: ${np_name} (${np_phase})"
                fi
            done <<< "$KC_OUT"
        fi
    done
fi

# --- C4: Pod security standards on namespace ---
if [[ -n "$NAMESPACE" ]]; then
    kc_safe "get namespace labels for ${NAMESPACE}" get namespace "$NAMESPACE" -o jsonpath='{.metadata.labels}'
    PSS_ENFORCE=""
    if [[ $KC_RC -eq 0 ]] && echo "$KC_OUT" | grep -q 'pod-security.kubernetes.io/enforce'; then
        PSS_ENFORCE=$(echo "$KC_OUT" | grep -o '"pod-security.kubernetes.io/enforce":"[^"]*"' | cut -d'"' -f4 || true)
    fi

    if [[ -n "$PSS_ENFORCE" ]]; then
        if [[ "$PSS_ENFORCE" == "restricted" ]]; then
            c_warn "Namespace ${NAMESPACE} has PSS enforce=${PSS_ENFORCE} — may restrict agent execution"
            add_issue "WARN" "Namespace PSS enforce=restricted" \
                "The 'restricted' Pod Security Standard may prevent the agent from running. Consider using 'baseline' or adding an exemption for the agent namespace."
        else
            c_info "Namespace ${NAMESPACE} PSS enforce=${PSS_ENFORCE}"
        fi
    elif [[ $KC_RC -eq 0 ]]; then
        c_pass "No pod security standard restrictions on namespace ${NAMESPACE}"
    fi
fi

# --- C6: Container image and track validation ---
echo ""
echo -e "  ${BOLD}--- Image & Track ---${NC}"

kc_safe "get container image for pod ${POD_NAME}" get pod "$POD_NAME" -n "$NAMESPACE" \
    -o jsonpath='{.spec.containers[0].image}'
CONTAINER_IMAGE="$KC_OUT"

kc_safe "get running image ID for pod ${POD_NAME}" get pod "$POD_NAME" -n "$NAMESPACE" \
    -o jsonpath='{.status.containerStatuses[0].imageID}'
RUNNING_IMAGE_ID="$KC_OUT"

if [[ -n "$CONTAINER_IMAGE" ]]; then
    c_info "Container image: ${CONTAINER_IMAGE}"

    # Detect track from image tag
    IMAGE_TAG="${CONTAINER_IMAGE##*:}"
    IMAGE_REPO="${CONTAINER_IMAGE%%:*}"
    # Handle digest-based references (repo@sha256:...)
    if [[ "$CONTAINER_IMAGE" == *"@sha256:"* ]]; then
        IMAGE_TAG="(pinned by digest)"
        IMAGE_REPO="${CONTAINER_IMAGE%%@*}"
    fi

    case "$IMAGE_TAG" in
        current)
            c_info "Release track: Current"
            detail "Updated ~twice/week (Tue/Thu). Latest features, bug fixes, security patches."
            detail "Support: latest release + one prior. Full SaaS agents always run Current."
            detail "Recommended for: dev/test environments wanting early access to features."
            ;;
        stable)
            c_info "Release track: Stable"
            detail "Released monthly (1st of month). Vetted cut of Current after ~1 month soak."
            detail "Support: latest release + one prior."
            detail "Recommended for: production environments wanting predictable upgrades."
            ;;
        *)
            c_warn "Release track: Custom tag '${IMAGE_TAG}' (not a standard track)"
            detail "Standard tracks: 'current' (twice/week) or 'stable' (monthly, production)."
            detail "Custom tags are not covered by standard support windows."
            detail "Docs: https://docs.matillion.com/data-productivity-cloud/agent/docs/agent-updates/"
            add_issue "WARN" "Non-standard image tag '${IMAGE_TAG}'" \
                "Use ':current' for dev/test or ':stable' for production. Custom tags are outside the standard support window. See: https://docs.matillion.com/data-productivity-cloud/agent/docs/agent-updates/"
            ;;
    esac

    # Detect cloud provider from image repo
    if [[ "$IMAGE_REPO" == *"ecr.aws"* ]]; then
        c_info "Image registry: AWS ECR (public.ecr.aws/matillion/etl-agent)"
    elif [[ "$IMAGE_REPO" == *"azurecr.io"* ]]; then
        c_info "Image registry: Azure ACR (matillion.azurecr.io/cloud-agent)"
    else
        c_info "Image registry: ${IMAGE_REPO}"
    fi

    # Check for image drift: compare spec image vs running image
    if [[ -n "$RUNNING_IMAGE_ID" ]]; then
        SPEC_DIGEST=""
        RUNNING_DIGEST=""
        if [[ "$CONTAINER_IMAGE" == *"@sha256:"* ]]; then
            SPEC_DIGEST="${CONTAINER_IMAGE##*@}"
        fi
        if [[ "$RUNNING_IMAGE_ID" == *"sha256:"* ]]; then
            RUNNING_DIGEST="${RUNNING_IMAGE_ID##*@}"
            # If spec uses a tag (not digest), we can't compare directly but can show info
            if [[ -z "$SPEC_DIGEST" ]]; then
                c_info "Running image digest: ${RUNNING_DIGEST:0:20}..."
            elif [[ "$SPEC_DIGEST" != "$RUNNING_DIGEST" ]]; then
                c_warn "Image drift detected: spec digest differs from running digest"
                detail "Spec:    ${SPEC_DIGEST:0:30}..."
                detail "Running: ${RUNNING_DIGEST:0:30}..."
                add_issue "WARN" "Container image drift detected" \
                    "The running image digest does not match the spec. The pod may be running a stale image. Delete the pod to pull the latest: kubectl delete pod ${POD_NAME} -n ${NAMESPACE}"
            else
                c_pass "Image digest matches spec (no drift)"
            fi
        fi
    fi
else
    c_warn "Could not determine container image"
fi

# --- C7: ServiceAccount and cloud identity validation ---
echo ""
echo -e "  ${BOLD}--- ServiceAccount & Identity ---${NC}"

kc_safe "get ServiceAccount for pod ${POD_NAME}" get pod "$POD_NAME" -n "$NAMESPACE" \
    -o jsonpath='{.spec.serviceAccountName}'
SA_NAME="$KC_OUT"

# Fetch CLOUD_PROVIDER from pod env vars
kc_safe "get CLOUD_PROVIDER env var" get pod "$POD_NAME" -n "$NAMESPACE" \
    -o jsonpath='{.spec.containers[0].env[?(@.name=="CLOUD_PROVIDER")].value}'
POD_CLOUD_PROVIDER="$KC_OUT"

# Fetch secretKeyRef env var names to detect local credential modes
kc_safe "get secretKeyRef env sources" get pod "$POD_NAME" -n "$NAMESPACE" \
    -o jsonpath='{range .spec.containers[0].env[*]}{.name}{"="}{.valueFrom.secretKeyRef.key}{"\n"}{end}'
SECRET_KEY_REFS="$KC_OUT"

if [[ -n "$SA_NAME" ]]; then
    c_info "ServiceAccount: ${SA_NAME}"

    # Get SA annotations and labels
    kc_safe "get ServiceAccount ${SA_NAME} details" get serviceaccount "$SA_NAME" -n "$NAMESPACE" -o json
    SA_JSON="$KC_OUT"

    if [[ $KC_RC -eq 0 && -n "$SA_JSON" ]]; then
        # AWS — EKS IRSA role ARN
        ROLE_ARN=$(echo "$SA_JSON" | grep -o '"eks.amazonaws.com/role-arn":"[^"]*"' | cut -d'"' -f4 || true)
        # Azure — Workload Identity client ID
        WI_CLIENT=$(echo "$SA_JSON" | grep -o '"azure.workload.identity/client-id":"[^"]*"' | cut -d'"' -f4 || true)
        # Azure — Workload Identity use label
        WI_LABEL=$(echo "$SA_JSON" | grep -o '"azure.workload.identity/use":"[^"]*"' | cut -d'"' -f4 || true)

        case "${POD_CLOUD_PROVIDER}" in
            AWS)
                if [[ -n "$ROLE_ARN" ]]; then
                    # Check for placeholder ARN
                    if [[ "$ROLE_ARN" == *"<ServiceAccountRoleArn>"* || "$ROLE_ARN" == *"<"*">"* ]]; then
                        c_fail "AWS IRSA role ARN is a placeholder: ${ROLE_ARN}"
                        detail "Replace the placeholder with a real IAM role ARN in your Helm values"
                        add_issue "FAIL" "AWS IRSA role ARN is a placeholder" \
                            "Set a valid IAM role ARN in the ServiceAccount annotation eks.amazonaws.com/role-arn"
                    elif echo "$ROLE_ARN" | grep -qE '^arn:aws[-a-z]*:iam::[0-9]+:role/'; then
                        c_pass "AWS IRSA configured with valid ARN: ${ROLE_ARN}"
                    else
                        c_warn "AWS IRSA role ARN may be malformed: ${ROLE_ARN}"
                        detail "Expected format: arn:aws:iam::<account-id>:role/<role-name>"
                        add_issue "WARN" "AWS IRSA role ARN may be malformed" \
                            "Verify the ARN format: arn:aws:iam::<account-id>:role/<role-name>"
                    fi
                elif echo "$SECRET_KEY_REFS" | grep -q "AWS_ACCESS_KEY_ID"; then
                    c_info "AWS using local credentials (secretKeyRef for AWS_ACCESS_KEY_ID found)"
                    detail "IRSA is recommended over static credentials for production use"
                else
                    c_warn "AWS: no IRSA annotation and no local credentials detected"
                    detail "Expected eks.amazonaws.com/role-arn annotation on ServiceAccount ${SA_NAME}"
                    detail "Or AWS_ACCESS_KEY_ID injected via secretKeyRef"
                    add_issue "WARN" "No AWS credentials configuration detected" \
                        "Configure IRSA (recommended) or provide AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY via a Secret"
                fi
                ;;
            AZURE)
                if [[ -n "$WI_CLIENT" ]]; then
                    c_pass "Azure Workload Identity configured: ${WI_CLIENT:0:8}..."
                    # Check for the required label
                    if [[ "$WI_LABEL" == "true" ]]; then
                        c_pass "Azure Workload Identity label present (azure.workload.identity/use=true)"
                    else
                        c_warn "Azure Workload Identity label missing or not 'true' on ServiceAccount"
                        detail "Add label azure.workload.identity/use: \"true\" to ServiceAccount ${SA_NAME}"
                        add_issue "WARN" "Azure WI label missing on ServiceAccount" \
                            "Add the label azure.workload.identity/use: \"true\" to the ServiceAccount to enable token injection"
                    fi
                elif echo "$SECRET_KEY_REFS" | grep -q "AZURE_CLIENT_SECRET"; then
                    c_info "Azure using Service Principal credentials (secretKeyRef for AZURE_CLIENT_SECRET found)"
                    detail "Workload Identity is recommended over SP secrets for production use"
                else
                    c_warn "Azure: no Workload Identity annotation and no SP credentials detected"
                    detail "Expected azure.workload.identity/client-id annotation on ServiceAccount ${SA_NAME}"
                    detail "Or AZURE_CLIENT_SECRET injected via secretKeyRef"
                    add_issue "WARN" "No Azure credentials configuration detected" \
                        "Configure Workload Identity (recommended) or provide AZURE_CLIENT_SECRET via a Secret"
                fi
                ;;
            "")
                c_warn "CLOUD_PROVIDER env var not found on pod — cannot validate cloud credentials"
                detail "Set CLOUD_PROVIDER to AWS or AZURE in your deployment configuration"
                add_issue "WARN" "CLOUD_PROVIDER not set" \
                    "Set the CLOUD_PROVIDER environment variable on the agent pod"
                # Still report any annotations found
                if [[ -n "$ROLE_ARN" ]]; then
                    c_info "Found AWS IRSA annotation: ${ROLE_ARN}"
                fi
                if [[ -n "$WI_CLIENT" ]]; then
                    c_info "Found Azure WI annotation: ${WI_CLIENT:0:8}..."
                fi
                ;;
            *)
                c_info "CLOUD_PROVIDER=${POD_CLOUD_PROVIDER} — GCP or other provider"
                # GCP — check for iam.gke.io/gcp-service-account annotation
                GCP_SA=$(echo "$SA_JSON" | grep -o '"iam.gke.io/gcp-service-account":"[^"]*"' | cut -d'"' -f4 || true)
                if [[ -n "$GCP_SA" ]]; then
                    c_info "GCP Workload Identity configured: ${GCP_SA}"
                fi
                ;;
        esac
    fi
elif [[ $KC_RC -eq 0 ]]; then
    c_warn "Could not determine ServiceAccount for pod"
fi

# --- C8: Secret availability ---
echo ""
echo -e "  ${BOLD}--- Secrets ---${NC}"

# Find secrets referenced by the pod (secretRef and secretKeyRef)
kc_safe "get pod spec for secret references" get pod "$POD_NAME" -n "$NAMESPACE" -o json
POD_JSON="$KC_OUT"
POD_JSON_RC=$KC_RC

if [[ $POD_JSON_RC -eq 0 && -n "$POD_JSON" ]]; then
    # Extract secret names from envFrom.secretRef and env.valueFrom.secretKeyRef
    SECRET_NAMES=$(echo "$POD_JSON" | grep -oE '"secretName":"[^"]*"|"name":"[^"]*-config"' | cut -d'"' -f4 | sort -u || true)

    # Also check secretRef in envFrom
    ENVFROM_SECRETS=$(echo "$POD_JSON" | grep -B1 '"secretRef"' | grep -o '"name":"[^"]*"' | cut -d'"' -f4 || true)
    ALL_SECRETS=$(echo -e "${SECRET_NAMES}\n${ENVFROM_SECRETS}" | sort -u | grep -v '^$' || true)

    if [[ -n "$ALL_SECRETS" ]]; then
        while IFS= read -r secret_name; do
            [[ -z "$secret_name" ]] && continue
            kc_safe "get secret '${secret_name}'" get secret "$secret_name" -n "$NAMESPACE" -o jsonpath='{.data}'
            if [[ $KC_RC -eq 2 ]]; then
                # "not found" — kc_safe returned 2
                c_fail "Secret '${secret_name}' not found"
                add_issue "FAIL" "Secret '${secret_name}' not found in namespace ${NAMESPACE}" \
                    "Create the missing secret before deployment. Check the Helm values for oauthClientId/oauthClientSecret or run: kubectl get secrets -n ${NAMESPACE}"
            elif [[ $KC_RC -ne 0 ]]; then
                # Auth/permission error — kc_safe already reported it
                :
            elif [[ -n "$KC_OUT" && "$KC_OUT" != "{}" ]]; then
                KEY_COUNT=$(echo "$KC_OUT" | grep -o '"[^"]*":' | wc -l | tr -d ' ')
                c_pass "Secret '${secret_name}' exists (${KEY_COUNT} keys)"
            else
                c_warn "Secret '${secret_name}' exists but has no data keys"
                add_issue "WARN" "Secret '${secret_name}' has no data" \
                    "The secret exists but contains no keys. Verify the secret was created correctly: kubectl get secret ${secret_name} -n ${NAMESPACE} -o yaml"
            fi
        done <<< "$ALL_SECRETS"
    else
        c_info "No secret references detected in pod spec"
    fi
elif [[ $POD_JSON_RC -ne 0 ]]; then
    # kc_safe already reported the error
    :
else
    c_warn "Could not read pod spec for secret references"
fi

# --- C9: NetworkPolicy egress check ---
echo ""
echo -e "  ${BOLD}--- Network Policies ---${NC}"

kc_safe "list NetworkPolicies in ${NAMESPACE}" get networkpolicies -n "$NAMESPACE" \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'
NP_LIST="$KC_OUT"
NP_RC=$KC_RC

if [[ $NP_RC -eq 0 && -n "$NP_LIST" ]]; then
    NP_COUNT=$(echo "$NP_LIST" | wc -l | tr -d ' ')
    c_info "${NP_COUNT} NetworkPolicy(s) in namespace ${NAMESPACE}"

    while IFS= read -r np_name; do
        [[ -z "$np_name" ]] && continue
        # Check for egress rules
        kc_safe "get NetworkPolicy ${np_name} egress" get networkpolicy "$np_name" -n "$NAMESPACE" \
            -o jsonpath='{.spec.egress}{"\t"}{.spec.policyTypes[*]}'
        [[ $KC_RC -ne 0 ]] && continue
        NP_EGRESS="${KC_OUT%%$'\t'*}"
        NP_POLICY_TYPES="${KC_OUT#*$'\t'}"

        if echo "$NP_POLICY_TYPES" | grep -q 'Egress'; then
            if [[ -z "$NP_EGRESS" || "$NP_EGRESS" == "[]" ]]; then
                c_warn "NetworkPolicy '${np_name}' has Egress policy type but no egress rules — all egress blocked"
                add_issue "WARN" "NetworkPolicy '${np_name}' blocks all egress" \
                    "The agent needs egress to port 443 (HTTPS) and port 53 (DNS). Add egress rules or remove the Egress policy type."
            else
                # Check for DNS (port 53) and HTTPS (port 443) in egress rules
                HAS_DNS=false
                HAS_HTTPS=false
                if echo "$NP_EGRESS" | grep -q '"port":53\|"port":"53"'; then
                    HAS_DNS=true
                fi
                if echo "$NP_EGRESS" | grep -q '"port":443\|"port":"443"'; then
                    HAS_HTTPS=true
                fi

                if [[ "$HAS_DNS" == true && "$HAS_HTTPS" == true ]]; then
                    c_pass "NetworkPolicy '${np_name}' allows DNS (53) and HTTPS (443) egress"
                else
                    MISSING=""
                    [[ "$HAS_DNS" == false ]] && MISSING="DNS (port 53)"
                    [[ "$HAS_HTTPS" == false ]] && MISSING="${MISSING:+$MISSING, }HTTPS (port 443)"
                    c_warn "NetworkPolicy '${np_name}' may be missing egress for: ${MISSING}"
                    add_issue "WARN" "NetworkPolicy '${np_name}' may block ${MISSING}" \
                        "The agent requires egress to port 443 (Matillion API, keycloak, OTEL) and port 53 (DNS). Add the missing egress rules."
                fi
            fi
        else
            c_info "NetworkPolicy '${np_name}' does not restrict egress"
        fi
    done <<< "$NP_LIST"
elif [[ $NP_RC -eq 0 ]]; then
    c_info "No NetworkPolicies in namespace ${NAMESPACE}"
fi

echo ""

# ===================== COPY AND EXECUTE IN-POD SCRIPT =======================
echo -e "  ${BOLD}--- Running In-Pod Checks ---${NC}"
echo -e "  Copying validation script to pod ${CYAN}${NAMESPACE}/${POD_NAME}${NC}..."
echo ""

REMOTE_SCRIPT="/tmp/_matillion_pre_check.sh"

# Copy script into pod
CP_ERR=$(mktemp 2>/dev/null || echo "/tmp/_cp_err_$$")
if ! kc cp "$IN_POD_SCRIPT" "${NAMESPACE}/${POD_NAME}:${REMOTE_SCRIPT}" 2>"$CP_ERR"; then
    CP_STDERR=$(cat "$CP_ERR" 2>/dev/null)
    rm -f "$CP_ERR" 2>/dev/null
    if echo "$CP_STDERR" | grep -qi 'unauthorized\|authentication\|token.*expired'; then
        c_fail "Authentication error copying script to pod"
        detail "kubectl returned: $(echo "$CP_STDERR" | head -1)"
        add_issue "FAIL" "Authentication failed during kubectl cp" \
            "Check your kubeconfig, token expiry, and cluster credentials."
    elif echo "$CP_STDERR" | grep -qi 'forbidden\|access denied'; then
        c_fail "Permission denied copying script to pod"
        detail "kubectl returned: $(echo "$CP_STDERR" | head -1)"
        add_issue "FAIL" "Insufficient permissions for kubectl cp" \
            "The current user needs exec/cp permissions on the pod. Check RBAC roles."
    else
        c_fail "Failed to copy validation script into pod"
        [[ -n "$CP_STDERR" ]] && detail "Error: $(echo "$CP_STDERR" | head -1)"
        detail "Ensure kubectl cp works: kubectl cp <file> ${NAMESPACE}/${POD_NAME}:/tmp/"
        add_issue "FAIL" "Cannot copy validation script into pod" \
            "Check that tar is available in the container and /tmp is writable. Try: kubectl exec -n ${NAMESPACE} ${POD_NAME} -- ls /tmp"
    fi
    echo ""
    box_top
    box_line "RESULT: FAIL — could not copy script to pod" "${RED}RESULT: FAIL${NC} — could not copy script to pod"
    box_bottom
    exit 1
fi
rm -f "$CP_ERR" 2>/dev/null

# Make executable and run — force color output through the pipe
POD_EXIT=0
EXEC_ERR=$(mktemp 2>/dev/null || echo "/tmp/_exec_err_$$")
kc exec -n "$NAMESPACE" "$POD_NAME" -- chmod +x "$REMOTE_SCRIPT" 2>/dev/null || true
kc exec -n "$NAMESPACE" "$POD_NAME" -- bash -c "FORCE_COLOR=1 bash $REMOTE_SCRIPT" 2>"$EXEC_ERR" || POD_EXIT=$?

# Check if exec failed due to auth/permission (not just script exit code)
EXEC_STDERR=$(cat "$EXEC_ERR" 2>/dev/null)
rm -f "$EXEC_ERR" 2>/dev/null
if [[ $POD_EXIT -ne 0 && -n "$EXEC_STDERR" ]]; then
    if echo "$EXEC_STDERR" | grep -qi 'unauthorized\|authentication\|forbidden\|access denied'; then
        c_fail "kubectl exec failed: $(echo "$EXEC_STDERR" | head -1)"
        add_issue "FAIL" "Cannot execute script in pod" \
            "Check RBAC permissions for exec on pods in namespace ${NAMESPACE}."
    fi
fi

# Cleanup
kc exec -n "$NAMESPACE" "$POD_NAME" -- rm -f "$REMOTE_SCRIPT" 2>/dev/null || true

echo ""

# =========================== COMBINED SUMMARY ===============================
CLUSTER_COUNTS="Cluster: ${CLUSTER_PASS} passed  ${CLUSTER_WARN} warnings  ${CLUSTER_FAIL} failed"
CLUSTER_COUNTS_FMT="Cluster: ${GREEN}${CLUSTER_PASS} passed${NC}  ${YELLOW}${CLUSTER_WARN} warnings${NC}  ${RED}${CLUSTER_FAIL} failed${NC}"

if [[ $POD_EXIT -ne 0 || $CLUSTER_FAIL -gt 0 ]]; then
    OVERALL_PLAIN="OVERALL: FAIL"
    OVERALL_FMT="${RED}OVERALL: FAIL${NC}"
else
    OVERALL_PLAIN="OVERALL: PASS"
    OVERALL_FMT="${GREEN}OVERALL: PASS${NC}"
fi

if [[ $POD_EXIT -eq 0 ]]; then
    POD_PLAIN="In-Pod:  All critical checks passed"
    POD_FMT="In-Pod:  ${GREEN}All critical checks passed${NC}"
else
    POD_PLAIN="In-Pod:  Critical checks failed (see above)"
    POD_FMT="In-Pod:  ${RED}Critical checks failed (see above)${NC}"
fi

box_top
box_line "$OVERALL_PLAIN" "$OVERALL_FMT"
box_blank
box_line "$CLUSTER_COUNTS" "$CLUSTER_COUNTS_FMT"
box_line "$POD_PLAIN" "$POD_FMT"
box_bottom

# ===================== CLUSTER-LEVEL REMEDIATION ============================
if [[ ${#ISSUES[@]} -gt 0 ]]; then
    echo ""
    echo -e "${BOLD}── Cluster-Level Remediation ───────────────────────────────${NC}"
    echo ""

    IDX=1
    for issue_entry in "${ISSUES[@]}"; do
        IFS='|' read -r level msg fix <<< "$issue_entry"
        if [[ "$level" == "FAIL" ]]; then
            echo -e "  ${RED}${IDX}. [FAIL] ${msg}${NC}"
        else
            echo -e "  ${YELLOW}${IDX}. [WARN] ${msg}${NC}"
        fi
        echo -e "     ${DIM}Fix: ${fix}${NC}"
        echo ""
        ((IDX++))
    done
fi

exit $POD_EXIT
