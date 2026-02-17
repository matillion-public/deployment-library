#!/usr/bin/env bash
# =============================================================================
# test_cloud_credentials.sh — Test cloud credential validation
#
# Creates mock kubectl and environments to verify:
# 1. Cluster-level (C7) cloud credential checks in run-check.sh
# 2. In-pod (P20b) cloud credential checks in pre-deployment-check.sh
#
# Usage:  ./test_cloud_credentials.sh
# Exit:   0 = all tests pass, 1 = any test failed
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
RUN_CHECK="${CHECKS_DIR}/run-check.sh"
IN_POD_CHECK="${CHECKS_DIR}/pre-deployment-check.sh"

PASS=0
FAIL=0
MOCK_DIR=""

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
setup_mock_dir() {
    MOCK_DIR=$(mktemp -d)
    export PATH="${MOCK_DIR}:${PATH}"
}

teardown_mock_dir() {
    [[ -n "$MOCK_DIR" && -d "$MOCK_DIR" ]] && rm -rf "$MOCK_DIR"
}

assert_output_contains() {
    local output="$1"
    local pattern="$2"
    local description="$3"

    echo -n "  TEST: ${description}... "
    if echo "$output" | grep -qi "$pattern"; then
        echo "PASS"
        ((PASS++))
        return 0
    else
        echo "FAIL"
        echo "    Expected pattern: ${pattern}"
        echo "    Output (last 20 lines):"
        echo "$output" | tail -20 | sed 's/^/      /'
        ((FAIL++))
        return 1
    fi
}

assert_output_not_contains() {
    local output="$1"
    local pattern="$2"
    local description="$3"

    echo -n "  TEST: ${description}... "
    if echo "$output" | grep -qi "$pattern"; then
        echo "FAIL"
        echo "    Unexpected pattern found: ${pattern}"
        echo "    Matching lines:"
        echo "$output" | grep -i "$pattern" | head -5 | sed 's/^/      /'
        ((FAIL++))
        return 1
    else
        echo "PASS"
        ((PASS++))
        return 0
    fi
}

# ---------------------------------------------------------------------------
# Base mock kubectl — handles all the standard queries that run-check.sh makes
# before reaching C7. Individual tests override the SA/cloud-specific responses.
# ---------------------------------------------------------------------------
write_mock_kubectl_base() {
    cat > "${MOCK_DIR}/kubectl" <<'MOCK_EOF'
#!/usr/bin/env bash
if [[ "$1" == "cluster-info" ]]; then
    echo "Kubernetes control plane is running at https://test-cluster:6443"
    exit 0
fi
if [[ "$1" == "auth" && "$2" == "can-i" ]]; then
    echo "yes"
    exit 0
fi
if [[ "$1" == "version" ]]; then
    echo "serverVersion:"
    echo "  gitVersion: v1.31.2"
    exit 0
fi
if [[ "$1" == "get" && "$2" == "daemonsets" ]]; then
    echo ""
    exit 0
fi
if [[ "$1" == "get" && "$2" == "pods" ]]; then
    printf 'test-ns\ttest-agent-app-abc123\tRunning\tnode-1\t0\n'
    exit 0
fi
if [[ "$1" == "get" && "$2" == "namespace" ]]; then
    echo '{}'
    exit 0
fi
if [[ "$1" == "get" && "$2" == "networkpolicies" ]]; then
    echo ""
    exit 0
fi
if [[ "$1" == "cp" ]]; then
    exit 0
fi
if [[ "$1" == "exec" ]]; then
    echo "  [PASS] All checks"
    exit 0
fi
MOCK_EOF
}

# Appends pod-level and SA-level mock responses to the kubectl mock.
# $1 = cloud_provider value (AWS, AZURE, or empty)
# $2 = SA JSON (full JSON for serviceaccount response)
# $3 = secret_key_refs output (for jsonpath secretKeyRef query)
append_mock_pod_and_sa() {
    local cloud_provider="$1"
    local sa_json="$2"
    local secret_key_refs="${3:-}"

    cat >> "${MOCK_DIR}/kubectl" <<MOCK_EOF
if [[ "\$1" == "get" && "\$2" == "pod" ]]; then
    if echo "\$*" | grep -q 'serviceAccountName'; then
        echo "test-sa"
        exit 0
    fi
    if echo "\$*" | grep -q 'containers\[0\].image'; then
        echo "public.ecr.aws/matillion/etl-agent:current"
        exit 0
    fi
    if echo "\$*" | grep -q 'imageID'; then
        echo ""
        exit 0
    fi
    if echo "\$*" | grep -q 'CLOUD_PROVIDER'; then
        echo "${cloud_provider}"
        exit 0
    fi
    if echo "\$*" | grep -q 'secretKeyRef'; then
        printf '${secret_key_refs}'
        exit 0
    fi
    echo '{"spec":{"containers":[{"envFrom":[]}]}}'
    exit 0
fi
if [[ "\$1" == "get" && "\$2" == "serviceaccount" ]]; then
    echo '${sa_json}'
    exit 0
fi
echo ""
MOCK_EOF
    chmod +x "${MOCK_DIR}/kubectl"
}

# ---------------------------------------------------------------------------
# In-pod mock helpers — builds a mock environment for pre-deployment-check.sh
# ---------------------------------------------------------------------------
setup_inpod_mock_env() {
    local mock_env
    mock_env=$(mktemp -d)
    local mock_bin="${mock_env}/bin"
    mkdir -p "$mock_bin"

    # Normal python3 — both inline and file-based work
    cat > "${mock_bin}/python3" <<'PYEOF'
#!/usr/bin/env bash
if [[ "$1" == "-c" ]]; then
    if echo "$2" | grep -q "^print("; then
        echo "$2" | sed "s/^print(['\"]//;s/['\"])$//"
    fi
    exit 0
fi
if [[ "$1" == "--version" ]]; then
    echo "Python 3.10.12"
    exit 0
fi
if [[ -f "$1" ]]; then
    while IFS= read -r line; do
        if echo "$line" | grep -q "^print("; then
            echo "$line" | sed "s/^print(['\"]//;s/['\"])$//"
        fi
    done < "$1"
    exit 0
fi
exit 0
PYEOF
    chmod +x "${mock_bin}/python3"

    # Mock java
    cat > "${mock_bin}/java" <<'JEOF'
#!/usr/bin/env bash
if [[ "$1" == "-version" || "$1" == "--version" ]]; then
    echo 'openjdk version "21.0.9" 2025-10-21' >&2
    exit 0
fi
JEOF
    chmod +x "${mock_bin}/java"

    # Mock sudo
    cat > "${mock_bin}/sudo" <<'SEOF'
#!/usr/bin/env bash
echo "mock sudo"
SEOF
    chmod +x "${mock_bin}/sudo"

    # Filesystem structure
    mkdir -p "${mock_env}/tmp" "${mock_env}/home/agentuser" "${mock_env}/dev/shm"
    mkdir -p "${mock_env}/proc/self" "${mock_env}/sys/fs/cgroup"

    cat > "${mock_env}/proc/self/status" <<'EOF'
Seccomp:        0
EOF
    echo "104857600" > "${mock_env}/sys/fs/cgroup/memory.current"
    echo "4294967296" > "${mock_env}/sys/fs/cgroup/memory.max"
    echo "oom_kill 0" > "${mock_env}/sys/fs/cgroup/memory.events"
    echo "50" > "${mock_env}/sys/fs/cgroup/pids.current"
    echo "32768" > "${mock_env}/sys/fs/cgroup/pids.max"

    echo "$mock_env"
}

run_inpod_check() {
    local mock_env="$1"
    shift
    # Remaining args are env var overrides as KEY=VALUE pairs
    local env_args=()
    for arg in "$@"; do
        env_args+=("$arg")
    done

    local mock_bin="${mock_env}/bin"
    local cmd_env=(
        PATH="${mock_bin}:/usr/bin:/bin"
        TMPDIR="${mock_env}/tmp"
        HOME="${mock_env}/home/agentuser"
        MTLN_EMERALD_WORKING_DIR="${mock_env}/home/agentuser"
        MATILLION_REGION="eu1"
        ACCOUNT_ID="test-account-123"
        AGENT_ID="test-agent-456"
        FORCE_COLOR=0
    )

    env -i "${cmd_args[@]}" "${env_args[@]}" bash "$IN_POD_CHECK" 2>&1 || true
}

# ===========================================================================
# CLUSTER-LEVEL TESTS (C7 — mock kubectl)
# ===========================================================================
echo ""
echo "=== Cloud Credential Validation Tests ==="
echo ""
echo "  --- Cluster-Level: AWS Tests ---"

# --- Test: AWS IRSA valid ARN → PASS ---
setup_mock_dir
write_mock_kubectl_base
append_mock_pod_and_sa \
    "AWS" \
    '{"metadata":{"annotations":{"eks.amazonaws.com/role-arn":"arn:aws:iam::123456789012:role/matillion-agent-role"},"labels":{}}}' \
    ""
OUTPUT=$(bash "$RUN_CHECK" --namespace test-ns 2>&1) || true
teardown_mock_dir

assert_output_contains "$OUTPUT" \
    "IRSA configured with valid ARN" \
    "AWS IRSA valid ARN → PASS"

# --- Test: AWS IRSA placeholder ARN → FAIL ---
setup_mock_dir
write_mock_kubectl_base
append_mock_pod_and_sa \
    "AWS" \
    '{"metadata":{"annotations":{"eks.amazonaws.com/role-arn":"<ServiceAccountRoleArn>"},"labels":{}}}' \
    ""
OUTPUT=$(bash "$RUN_CHECK" --namespace test-ns 2>&1) || true
teardown_mock_dir

assert_output_contains "$OUTPUT" \
    "placeholder" \
    "AWS IRSA placeholder ARN → FAIL"

# --- Test: AWS IRSA malformed ARN → WARN ---
setup_mock_dir
write_mock_kubectl_base
append_mock_pod_and_sa \
    "AWS" \
    '{"metadata":{"annotations":{"eks.amazonaws.com/role-arn":"not-a-real-arn"},"labels":{}}}' \
    ""
OUTPUT=$(bash "$RUN_CHECK" --namespace test-ns 2>&1) || true
teardown_mock_dir

assert_output_contains "$OUTPUT" \
    "malformed" \
    "AWS IRSA malformed ARN → WARN"

# --- Test: AWS local creds (no IRSA) → INFO ---
setup_mock_dir
write_mock_kubectl_base
append_mock_pod_and_sa \
    "AWS" \
    '{"metadata":{"annotations":{},"labels":{}}}' \
    'AWS_ACCESS_KEY_ID=aws_access_key_id\nAWS_SECRET_ACCESS_KEY=aws_secret_access_key\n'
OUTPUT=$(bash "$RUN_CHECK" --namespace test-ns 2>&1) || true
teardown_mock_dir

assert_output_contains "$OUTPUT" \
    "local credentials.*AWS_ACCESS_KEY_ID\|AWS.*local credentials" \
    "AWS local creds (no IRSA) → INFO"

# --- Test: AWS no creds at all → WARN ---
setup_mock_dir
write_mock_kubectl_base
append_mock_pod_and_sa \
    "AWS" \
    '{"metadata":{"annotations":{},"labels":{}}}' \
    ""
OUTPUT=$(bash "$RUN_CHECK" --namespace test-ns 2>&1) || true
teardown_mock_dir

assert_output_contains "$OUTPUT" \
    "no IRSA annotation and no local credentials" \
    "AWS no creds → WARN"

echo ""
echo "  --- Cluster-Level: Azure Tests ---"

# --- Test: Azure WI correctly configured → PASS ---
setup_mock_dir
write_mock_kubectl_base
append_mock_pod_and_sa \
    "AZURE" \
    '{"metadata":{"annotations":{"azure.workload.identity/client-id":"abcd1234-5678-90ab-cdef-1234567890ab"},"labels":{"azure.workload.identity/use":"true"}}}' \
    ""
OUTPUT=$(bash "$RUN_CHECK" --namespace test-ns 2>&1) || true
teardown_mock_dir

assert_output_contains "$OUTPUT" \
    "Azure Workload Identity configured" \
    "Azure WI configured → PASS"

assert_output_contains "$OUTPUT" \
    "Workload Identity label present" \
    "Azure WI label present → PASS"

# --- Test: Azure WI missing label → WARN ---
setup_mock_dir
write_mock_kubectl_base
append_mock_pod_and_sa \
    "AZURE" \
    '{"metadata":{"annotations":{"azure.workload.identity/client-id":"abcd1234-5678-90ab-cdef-1234567890ab"},"labels":{}}}' \
    ""
OUTPUT=$(bash "$RUN_CHECK" --namespace test-ns 2>&1) || true
teardown_mock_dir

assert_output_contains "$OUTPUT" \
    "label missing" \
    "Azure WI missing label → WARN"

# --- Test: Azure SP mode → INFO ---
setup_mock_dir
write_mock_kubectl_base
append_mock_pod_and_sa \
    "AZURE" \
    '{"metadata":{"annotations":{},"labels":{}}}' \
    'AZURE_CLIENT_SECRET=azure_client_secret\n'
OUTPUT=$(bash "$RUN_CHECK" --namespace test-ns 2>&1) || true
teardown_mock_dir

assert_output_contains "$OUTPUT" \
    "Service Principal credentials\|SP credentials\|AZURE_CLIENT_SECRET" \
    "Azure SP mode → INFO"

# --- Test: Azure no creds → WARN ---
setup_mock_dir
write_mock_kubectl_base
append_mock_pod_and_sa \
    "AZURE" \
    '{"metadata":{"annotations":{},"labels":{}}}' \
    ""
OUTPUT=$(bash "$RUN_CHECK" --namespace test-ns 2>&1) || true
teardown_mock_dir

assert_output_contains "$OUTPUT" \
    "no Workload Identity annotation and no SP credentials" \
    "Azure no creds → WARN"

echo ""
echo "  --- Cluster-Level: Other ---"

# --- Test: CLOUD_PROVIDER not found → WARN ---
setup_mock_dir
write_mock_kubectl_base
append_mock_pod_and_sa \
    "" \
    '{"metadata":{"annotations":{},"labels":{}}}' \
    ""
OUTPUT=$(bash "$RUN_CHECK" --namespace test-ns 2>&1) || true
teardown_mock_dir

assert_output_contains "$OUTPUT" \
    "CLOUD_PROVIDER.*not found\|CLOUD_PROVIDER.*not set" \
    "CLOUD_PROVIDER not found → WARN"


# ===========================================================================
# IN-POD TESTS (P20b — mock env)
# ===========================================================================
echo ""
echo "  --- In-Pod: AWS Tests ---"

# --- Test: AWS IRSA happy path (token file exists) → PASS ---
MOCK_ENV=$(setup_inpod_mock_env)
# Create a fake token file
mkdir -p "${MOCK_ENV}/var/run/secrets/eks.amazonaws.com/serviceaccount"
echo "fake-token" > "${MOCK_ENV}/var/run/secrets/eks.amazonaws.com/serviceaccount/token"
TOKEN_PATH="${MOCK_ENV}/var/run/secrets/eks.amazonaws.com/serviceaccount/token"

OUTPUT=$(
    PATH="${MOCK_ENV}/bin:/usr/bin:/bin" \
    TMPDIR="${MOCK_ENV}/tmp" \
    HOME="${MOCK_ENV}/home/agentuser" \
    MTLN_EMERALD_WORKING_DIR="${MOCK_ENV}/home/agentuser" \
    MATILLION_REGION="eu1" \
    ACCOUNT_ID="test-account-123" \
    AGENT_ID="test-agent-456" \
    FORCE_COLOR=0 \
    CLOUD_PROVIDER="AWS" \
    AWS_ROLE_ARN="arn:aws:iam::123456789012:role/test-role" \
    AWS_WEB_IDENTITY_TOKEN_FILE="${TOKEN_PATH}" \
    bash "$IN_POD_CHECK" 2>&1
) || true
rm -rf "$MOCK_ENV"

assert_output_contains "$OUTPUT" \
    "IRSA credentials present\|IRSA.*token file exists" \
    "AWS IRSA happy path → PASS"

# --- Test: AWS IRSA token file missing → FAIL ---
MOCK_ENV=$(setup_inpod_mock_env)

OUTPUT=$(
    PATH="${MOCK_ENV}/bin:/usr/bin:/bin" \
    TMPDIR="${MOCK_ENV}/tmp" \
    HOME="${MOCK_ENV}/home/agentuser" \
    MTLN_EMERALD_WORKING_DIR="${MOCK_ENV}/home/agentuser" \
    MATILLION_REGION="eu1" \
    ACCOUNT_ID="test-account-123" \
    AGENT_ID="test-agent-456" \
    FORCE_COLOR=0 \
    CLOUD_PROVIDER="AWS" \
    AWS_ROLE_ARN="arn:aws:iam::123456789012:role/test-role" \
    AWS_WEB_IDENTITY_TOKEN_FILE="/nonexistent/path/token" \
    bash "$IN_POD_CHECK" 2>&1
) || true
rm -rf "$MOCK_ENV"

assert_output_contains "$OUTPUT" \
    "IRSA token file not found\|token file.*not found" \
    "AWS IRSA token missing → FAIL"

# --- Test: AWS local creds → PASS ---
MOCK_ENV=$(setup_inpod_mock_env)

OUTPUT=$(
    PATH="${MOCK_ENV}/bin:/usr/bin:/bin" \
    TMPDIR="${MOCK_ENV}/tmp" \
    HOME="${MOCK_ENV}/home/agentuser" \
    MTLN_EMERALD_WORKING_DIR="${MOCK_ENV}/home/agentuser" \
    MATILLION_REGION="eu1" \
    ACCOUNT_ID="test-account-123" \
    AGENT_ID="test-agent-456" \
    FORCE_COLOR=0 \
    CLOUD_PROVIDER="AWS" \
    AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE" \
    AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY" \
    bash "$IN_POD_CHECK" 2>&1
) || true
rm -rf "$MOCK_ENV"

assert_output_contains "$OUTPUT" \
    "local credentials present\|ACCESS_KEY_ID.*SECRET_ACCESS_KEY" \
    "AWS local creds → PASS"

# --- Test: AWS no creds → WARN ---
MOCK_ENV=$(setup_inpod_mock_env)

OUTPUT=$(
    PATH="${MOCK_ENV}/bin:/usr/bin:/bin" \
    TMPDIR="${MOCK_ENV}/tmp" \
    HOME="${MOCK_ENV}/home/agentuser" \
    MTLN_EMERALD_WORKING_DIR="${MOCK_ENV}/home/agentuser" \
    MATILLION_REGION="eu1" \
    ACCOUNT_ID="test-account-123" \
    AGENT_ID="test-agent-456" \
    FORCE_COLOR=0 \
    CLOUD_PROVIDER="AWS" \
    bash "$IN_POD_CHECK" 2>&1
) || true
rm -rf "$MOCK_ENV"

assert_output_contains "$OUTPUT" \
    "no IRSA token and no local credentials" \
    "AWS no creds → WARN"

echo ""
echo "  --- In-Pod: Azure Tests ---"

# --- Test: Azure WI happy path → PASS ---
MOCK_ENV=$(setup_inpod_mock_env)
mkdir -p "${MOCK_ENV}/var/run/secrets/azure/tokens"
echo "fake-azure-token" > "${MOCK_ENV}/var/run/secrets/azure/tokens/azure-identity-token"
AZ_TOKEN_PATH="${MOCK_ENV}/var/run/secrets/azure/tokens/azure-identity-token"

OUTPUT=$(
    PATH="${MOCK_ENV}/bin:/usr/bin:/bin" \
    TMPDIR="${MOCK_ENV}/tmp" \
    HOME="${MOCK_ENV}/home/agentuser" \
    MTLN_EMERALD_WORKING_DIR="${MOCK_ENV}/home/agentuser" \
    MATILLION_REGION="eu1" \
    ACCOUNT_ID="test-account-123" \
    AGENT_ID="test-agent-456" \
    FORCE_COLOR=0 \
    CLOUD_PROVIDER="AZURE" \
    AZURE_FEDERATED_TOKEN_FILE="${AZ_TOKEN_PATH}" \
    AZURE_CLIENT_ID="abcd1234-5678-90ab-cdef-1234567890ab" \
    AZURE_TENANT_ID="aaaa1111-2222-3333-4444-555566667777" \
    bash "$IN_POD_CHECK" 2>&1
) || true
rm -rf "$MOCK_ENV"

assert_output_contains "$OUTPUT" \
    "Workload Identity credentials present" \
    "Azure WI happy path → PASS"

# --- Test: Azure WI token missing → FAIL ---
MOCK_ENV=$(setup_inpod_mock_env)

OUTPUT=$(
    PATH="${MOCK_ENV}/bin:/usr/bin:/bin" \
    TMPDIR="${MOCK_ENV}/tmp" \
    HOME="${MOCK_ENV}/home/agentuser" \
    MTLN_EMERALD_WORKING_DIR="${MOCK_ENV}/home/agentuser" \
    MATILLION_REGION="eu1" \
    ACCOUNT_ID="test-account-123" \
    AGENT_ID="test-agent-456" \
    FORCE_COLOR=0 \
    CLOUD_PROVIDER="AZURE" \
    AZURE_FEDERATED_TOKEN_FILE="/nonexistent/azure/token" \
    AZURE_CLIENT_ID="abcd1234-5678-90ab-cdef-1234567890ab" \
    AZURE_TENANT_ID="aaaa1111-2222-3333-4444-555566667777" \
    bash "$IN_POD_CHECK" 2>&1
) || true
rm -rf "$MOCK_ENV"

assert_output_contains "$OUTPUT" \
    "federated token file not found\|WI.*token file not found\|token file.*not found" \
    "Azure WI token missing → FAIL"

# --- Test: Azure WI partial (missing TENANT_ID) → WARN ---
MOCK_ENV=$(setup_inpod_mock_env)
mkdir -p "${MOCK_ENV}/var/run/secrets/azure/tokens"
echo "fake-azure-token" > "${MOCK_ENV}/var/run/secrets/azure/tokens/azure-identity-token"
AZ_TOKEN_PATH="${MOCK_ENV}/var/run/secrets/azure/tokens/azure-identity-token"

OUTPUT=$(
    PATH="${MOCK_ENV}/bin:/usr/bin:/bin" \
    TMPDIR="${MOCK_ENV}/tmp" \
    HOME="${MOCK_ENV}/home/agentuser" \
    MTLN_EMERALD_WORKING_DIR="${MOCK_ENV}/home/agentuser" \
    MATILLION_REGION="eu1" \
    ACCOUNT_ID="test-account-123" \
    AGENT_ID="test-agent-456" \
    FORCE_COLOR=0 \
    CLOUD_PROVIDER="AZURE" \
    AZURE_FEDERATED_TOKEN_FILE="${AZ_TOKEN_PATH}" \
    AZURE_CLIENT_ID="abcd1234-5678-90ab-cdef-1234567890ab" \
    bash "$IN_POD_CHECK" 2>&1
) || true
rm -rf "$MOCK_ENV"

assert_output_contains "$OUTPUT" \
    "incomplete\|partial\|AZURE_TENANT_ID.*NOT SET\|missing.*env" \
    "Azure WI partial (missing TENANT_ID) → WARN"

# --- Test: Azure SP → PASS ---
MOCK_ENV=$(setup_inpod_mock_env)

OUTPUT=$(
    PATH="${MOCK_ENV}/bin:/usr/bin:/bin" \
    TMPDIR="${MOCK_ENV}/tmp" \
    HOME="${MOCK_ENV}/home/agentuser" \
    MTLN_EMERALD_WORKING_DIR="${MOCK_ENV}/home/agentuser" \
    MATILLION_REGION="eu1" \
    ACCOUNT_ID="test-account-123" \
    AGENT_ID="test-agent-456" \
    FORCE_COLOR=0 \
    CLOUD_PROVIDER="AZURE" \
    AZURE_CLIENT_ID="abcd1234-5678-90ab-cdef-1234567890ab" \
    AZURE_CLIENT_SECRET="super-secret-value" \
    AZURE_TENANT_ID="aaaa1111-2222-3333-4444-555566667777" \
    bash "$IN_POD_CHECK" 2>&1
) || true
rm -rf "$MOCK_ENV"

assert_output_contains "$OUTPUT" \
    "Service Principal credentials present" \
    "Azure SP → PASS"

# --- Test: Azure no creds → WARN ---
MOCK_ENV=$(setup_inpod_mock_env)

OUTPUT=$(
    PATH="${MOCK_ENV}/bin:/usr/bin:/bin" \
    TMPDIR="${MOCK_ENV}/tmp" \
    HOME="${MOCK_ENV}/home/agentuser" \
    MTLN_EMERALD_WORKING_DIR="${MOCK_ENV}/home/agentuser" \
    MATILLION_REGION="eu1" \
    ACCOUNT_ID="test-account-123" \
    AGENT_ID="test-agent-456" \
    FORCE_COLOR=0 \
    CLOUD_PROVIDER="AZURE" \
    bash "$IN_POD_CHECK" 2>&1
) || true
rm -rf "$MOCK_ENV"

assert_output_contains "$OUTPUT" \
    "no Workload Identity token and no SP credentials" \
    "Azure no creds → WARN"

echo ""
echo "  --- In-Pod: Other ---"

# --- Test: CLOUD_PROVIDER not set → WARN ---
MOCK_ENV=$(setup_inpod_mock_env)

OUTPUT=$(
    PATH="${MOCK_ENV}/bin:/usr/bin:/bin" \
    TMPDIR="${MOCK_ENV}/tmp" \
    HOME="${MOCK_ENV}/home/agentuser" \
    MTLN_EMERALD_WORKING_DIR="${MOCK_ENV}/home/agentuser" \
    MATILLION_REGION="eu1" \
    ACCOUNT_ID="test-account-123" \
    AGENT_ID="test-agent-456" \
    FORCE_COLOR=0 \
    bash "$IN_POD_CHECK" 2>&1
) || true
rm -rf "$MOCK_ENV"

assert_output_contains "$OUTPUT" \
    "CLOUD_PROVIDER not set" \
    "CLOUD_PROVIDER not set → WARN"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
exit 0
