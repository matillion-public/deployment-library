#!/usr/bin/env bash
# =============================================================================
# pre-deployment-check.sh — Matillion Agent In-Pod Validation
#
# Runs inside a Matillion agent pod to validate the runtime environment.
# Can be executed standalone via kubectl exec or orchestrated by run-check.sh.
#
# Exit code: 0 = all critical checks pass, 1 = any critical check failed.
# =============================================================================
set -uo pipefail

VERSION="1.0.0"

# ---------------------------------------------------------------------------
# Colors (auto-disable if not a terminal)
# ---------------------------------------------------------------------------
if [[ -t 1 ]] || [[ "${FORCE_COLOR:-}" == "1" ]]; then
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
# Counters & issue collector
# ---------------------------------------------------------------------------
PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0
INFO_COUNT=0

ISSUES=()  # collected as "LEVEL|message|remediation"

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
pass()   { ((PASS_COUNT++)); echo -e "  ${GREEN}[PASS]${NC} $*"; }
warn()   { ((WARN_COUNT++)); echo -e "  ${YELLOW}[WARN]${NC} $*"; }
fail()   { ((FAIL_COUNT++)); echo -e "  ${RED}[FAIL]${NC} $*"; }
info()   { ((INFO_COUNT++)); echo -e "  ${CYAN}[INFO]${NC} $*"; }
detail() { echo -e "         ${DIM}$*${NC}"; }

add_issue() {
    # $1=FAIL|WARN  $2=short description  $3=remediation
    ISSUES+=("$1|$2|$3")
}

# ---------------------------------------------------------------------------
# Box helper — pads plain text to fixed width inside ║ ... ║
# ---------------------------------------------------------------------------
BOX_W=60  # inner width (between the ║ chars)
box_top()    { echo -e "${BOLD}╔$(printf '═%.0s' $(seq 1 $BOX_W))╗${NC}"; }
box_bottom() { echo -e "${BOLD}╚$(printf '═%.0s' $(seq 1 $BOX_W))╝${NC}"; }
box_blank()  { echo -e "${BOLD}║$(printf ' %.0s' $(seq 1 $BOX_W))║${NC}"; }
box_line() {
    # $1 = plain text (for width calc), $2 = formatted text (with ANSI)
    local plain="$1" formatted="${2:-$1}"
    local pad=$((BOX_W - 2 - ${#plain}))
    [[ $pad -lt 0 ]] && pad=0
    echo -e "${BOLD}║${NC}  ${formatted}$(printf ' %.0s' $(seq 1 $pad))${BOLD}║${NC}"
}

# ---------------------------------------------------------------------------
# Header
# ---------------------------------------------------------------------------
HEADER_DATE=$(date -u '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null || date '+%Y-%m-%d %H:%M:%S')
HEADER_HOST=$(hostname 2>/dev/null || echo 'unknown')
echo ""
box_top
box_line "Matillion Agent In-Pod Check v${VERSION}"
box_line "${HEADER_DATE}"
box_line "Host: ${HEADER_HOST}"
box_bottom
echo ""

# ============================= CRITICAL CHECKS ==============================
echo -e "${BOLD}── Critical Checks ─────────────────────────────────────────${NC}"
echo ""

# --- P1: python3 on PATH ---
PYTHON3_PATH=""
if PYTHON3_PATH=$(command -v python3 2>/dev/null); then
    PYTHON3_VER=$(python3 --version 2>&1 | head -1)
    pass "Python3 available: ${PYTHON3_PATH} (${PYTHON3_VER})"
else
    fail "python3 not found on PATH"
    add_issue "FAIL" "python3 not found on PATH" \
        "Install Python 3 in the container image or verify the PATH includes the Python binary location."
fi

# --- P2: python3 inline execution ---
INLINE_OK=false
if [[ -n "$PYTHON3_PATH" ]]; then
    INLINE_RESULT=$(python3 -c "print('matillion_check_ok')" 2>&1)
    INLINE_EXIT=$?
    if [[ $INLINE_EXIT -eq 0 && "$INLINE_RESULT" == "matillion_check_ok" ]]; then
        pass "Python3 inline execution works"
        INLINE_OK=true
    else
        fail "Python3 inline execution failed (exit ${INLINE_EXIT})"
        detail "Output: ${INLINE_RESULT}"
        add_issue "FAIL" "Python3 inline execution failed (exit ${INLINE_EXIT})" \
            "Verify the Python installation is not corrupted. Try: python3 -c \"print('hello')\" manually."
    fi
fi

# --- P3: python3 file-based execution ---
FILE_OK=false
if [[ -n "$PYTHON3_PATH" ]]; then
    CHECK_SCRIPT="/tmp/_matillion_check.py"
    cat > "$CHECK_SCRIPT" 2>/dev/null <<'PYEOF'
print('matillion_check_ok')
PYEOF

    if [[ -f "$CHECK_SCRIPT" ]]; then
        FILE_RESULT=$(python3 "$CHECK_SCRIPT" 2>&1)
        FILE_EXIT=$?
        if [[ $FILE_EXIT -eq 0 && "$FILE_RESULT" == "matillion_check_ok" ]]; then
            pass "Python3 file-based execution works"
            FILE_OK=true
        elif [[ $FILE_EXIT -eq 137 ]]; then
            fail "Python3 file-based execution killed (exit 137 — SIGKILL)"
            detail "Runtime security tool likely blocking file-based Python execution"
            detail "This matches CrowdStrike Falcon container drift detection behavior"
            add_issue "FAIL" "Python3 file-based execution killed (exit 137)" \
                "A runtime security tool (likely CrowdStrike Falcon) is killing Python when invoked with a file argument. Create a container exclusion policy in your security tool for the Matillion agent container/image."
        else
            fail "Python3 file-based execution failed (exit ${FILE_EXIT})"
            detail "Output: ${FILE_RESULT}"
            add_issue "FAIL" "Python3 file-based execution failed (exit ${FILE_EXIT})" \
                "Check filesystem permissions on /tmp and verify no security policies are blocking script execution."
        fi
        rm -f "$CHECK_SCRIPT" 2>/dev/null
    else
        fail "Could not write test script to /tmp/_matillion_check.py"
        add_issue "FAIL" "Cannot write to /tmp/_matillion_check.py" \
            "Ensure /tmp is writable. Check mount options and filesystem permissions."
    fi
fi

# --- P4: inline vs file-based mismatch ---
if [[ "$INLINE_OK" == true && "$FILE_OK" == false && -n "$PYTHON3_PATH" ]]; then
    fail "Python3 inline works but file-based execution fails"
    detail "This strongly indicates a runtime security tool is blocking file-based execution"
    detail "Check cluster-level security DaemonSet results above"
    add_issue "FAIL" "Inline Python works but file-based execution is blocked" \
        "A runtime security tool is intercepting file-based Python execution. Check cluster checks for detected security DaemonSets (CrowdStrike, Falco, etc.) and create an exclusion."
elif [[ "$INLINE_OK" == true && "$FILE_OK" == true ]]; then
    pass "Inline and file-based Python execution results match"
fi

# --- P5: /tmp writable ---
if touch /tmp/_matillion_write_test 2>/dev/null; then
    rm -f /tmp/_matillion_write_test 2>/dev/null
    pass "/tmp is writable"
else
    fail "/tmp is not writable"
    add_issue "FAIL" "/tmp is not writable" \
        "The agent writes temporary scripts to /tmp. Ensure /tmp is mounted as writable (check volumeMounts in the Deployment spec)."
fi

# --- P6: working directory ---
WORK_DIR="${MTLN_EMERALD_WORKING_DIR:-/home}"
CURRENT_USER=$(whoami 2>/dev/null || echo "unknown")
# The agent writes to subdirectories (e.g. /home/agentuser), not /home itself
WORK_DIR_USER="${WORK_DIR}/${CURRENT_USER}"
if [[ -d "$WORK_DIR_USER" ]]; then
    if touch "${WORK_DIR_USER}/_matillion_write_test" 2>/dev/null; then
        rm -f "${WORK_DIR_USER}/_matillion_write_test" 2>/dev/null
        pass "Working directory ${WORK_DIR_USER} exists and is writable"
    else
        fail "Working directory ${WORK_DIR_USER} exists but is not writable"
        add_issue "FAIL" "Working directory ${WORK_DIR_USER} is not writable" \
            "Ensure the container user (${CURRENT_USER}) has write permissions to ${WORK_DIR_USER}. Check the Dockerfile USER directive and directory ownership."
    fi
elif [[ -d "$WORK_DIR" ]]; then
    if touch "${WORK_DIR}/_matillion_write_test" 2>/dev/null; then
        rm -f "${WORK_DIR}/_matillion_write_test" 2>/dev/null
        pass "Working directory ${WORK_DIR} exists and is writable"
    else
        fail "Working directory ${WORK_DIR} exists but is not writable"
        add_issue "FAIL" "Working directory ${WORK_DIR} is not writable" \
            "Ensure the container user has write permissions. Set MTLN_EMERALD_WORKING_DIR to a writable path or fix directory ownership."
    fi
else
    fail "Working directory ${WORK_DIR} does not exist"
    add_issue "FAIL" "Working directory ${WORK_DIR} does not exist" \
        "Create the directory in the container image or set MTLN_EMERALD_WORKING_DIR to an existing writable path."
fi

# --- P7: java available ---
if command -v java >/dev/null 2>&1; then
    JAVA_VER=$(java -version 2>&1 | head -1)
    pass "Java available: ${JAVA_VER}"
else
    fail "java not found on PATH"
    add_issue "FAIL" "Java not found on PATH" \
        "The Matillion agent is a Spring Boot Java application. Ensure a JDK/JRE is installed in the container image."
fi

echo ""

# ============================== WARNING CHECKS ==============================
echo -e "${BOLD}── Warning Checks ──────────────────────────────────────────${NC}"
echo ""

# --- P8: /dev/shm size ---
if [[ -d /dev/shm ]]; then
    SHM_KB=$(df -k /dev/shm 2>/dev/null | awk 'NR==2{print $2}')
    if [[ -n "$SHM_KB" && "$SHM_KB" =~ ^[0-9]+$ ]]; then
        SHM_MB=$((SHM_KB / 1024))
        if [[ $SHM_MB -ge 40 ]]; then
            pass "/dev/shm is ${SHM_MB}MB (>= 40MB required)"
        else
            warn "/dev/shm is ${SHM_MB}MB (expected >= 40MB)"
            add_issue "WARN" "/dev/shm is only ${SHM_MB}MB (expected >= 40MB)" \
                "Add a sizeLimit to the emptyDir volume for /dev/shm in the Deployment spec, e.g.: emptyDir: { medium: Memory, sizeLimit: 64Mi }"
        fi
    else
        warn "Could not determine /dev/shm size"
    fi
else
    warn "/dev/shm does not exist"
    add_issue "WARN" "/dev/shm does not exist" \
        "Mount /dev/shm as an emptyDir with medium: Memory in the Deployment spec."
fi

# --- P9: /tmp free space ---
TMP_FREE_KB=$(df -k /tmp 2>/dev/null | awk 'NR==2{print $4}')
if [[ -n "$TMP_FREE_KB" && "$TMP_FREE_KB" =~ ^[0-9]+$ ]]; then
    TMP_FREE_MB=$((TMP_FREE_KB / 1024))
    if [[ $TMP_FREE_MB -ge 256 ]]; then
        pass "/tmp has ${TMP_FREE_MB}MB free (>= 256MB required)"
    else
        warn "/tmp has only ${TMP_FREE_MB}MB free (expected >= 256MB)"
        add_issue "WARN" "/tmp has only ${TMP_FREE_MB}MB free (expected >= 256MB)" \
            "Increase the sizeLimit on the /tmp emptyDir volume or free disk space on the node."
    fi
else
    warn "Could not determine /tmp free space"
fi

# --- P10: restricteduser user ---
if id restricteduser >/dev/null 2>&1; then
    info "restricteduser user exists — RESTRICTED mode available"
else
    info "restricteduser user does not exist — scripts will run in PRIVILEGED mode (expected)"
fi

# --- P11: restricteduser group ---
if getent group restricteduser >/dev/null 2>&1; then
    info "restricteduser group exists"
else
    info "restricteduser group does not exist — PRIVILEGED mode will be used (expected)"
fi

# --- P12: sudo available ---
if [[ -x /usr/bin/sudo ]]; then
    pass "sudo available at /usr/bin/sudo"
else
    warn "sudo not available at /usr/bin/sudo"
    add_issue "WARN" "sudo not available at /usr/bin/sudo" \
        "Required for RESTRICTED mode execution. Install sudo in the container image if RESTRICTED mode is needed."
fi

# --- P13: noexec on /tmp ---
TMP_MOUNT_FLAGS=$(mount 2>/dev/null | grep ' /tmp ' | head -1)
if [[ -n "$TMP_MOUNT_FLAGS" ]]; then
    if echo "$TMP_MOUNT_FLAGS" | grep -q 'noexec'; then
        warn "/tmp is mounted with noexec — may block script execution"
        detail "Mount: ${TMP_MOUNT_FLAGS}"
        add_issue "WARN" "/tmp is mounted with noexec" \
            "Remove the noexec mount option from /tmp, or mount a separate writable+executable tmpfs for the agent's script directory."
    else
        pass "/tmp does not have noexec mount flag"
    fi
else
    pass "/tmp mount flags OK (no separate mount or no noexec)"
fi

# --- P14: OOM kill counter ---
OOM_EVENTS="/sys/fs/cgroup/memory.events"
if [[ -f "$OOM_EVENTS" ]]; then
    OOM_KILL=$(grep -w oom_kill "$OOM_EVENTS" 2>/dev/null | awk '{print $2}')
    if [[ -n "$OOM_KILL" && "$OOM_KILL" != "0" ]]; then
        warn "OOM kill counter is ${OOM_KILL} (expected 0)"
        add_issue "WARN" "OOM kill counter is ${OOM_KILL}" \
            "Previous OOM kills indicate memory pressure. Increase the container memory limit in the Deployment spec (resources.limits.memory)."
    else
        pass "No OOM kills detected (oom_kill: ${OOM_KILL:-0})"
    fi
else
    # Try cgroup v1
    OOM_V1="/sys/fs/cgroup/memory/memory.oom_control"
    if [[ -f "$OOM_V1" ]]; then
        OOM_KILL=$(grep oom_kill_disable "$OOM_V1" 2>/dev/null | awk '{print $2}')
        info "cgroup v1 OOM control: oom_kill_disable=${OOM_KILL:-unknown}"
    else
        info "OOM kill counter not available (cgroup file not found)"
    fi
fi

# --- P15: Memory usage ---
MEM_CURRENT="/sys/fs/cgroup/memory.current"
MEM_MAX="/sys/fs/cgroup/memory.max"
if [[ -f "$MEM_CURRENT" && -f "$MEM_MAX" ]]; then
    MEM_CUR_BYTES=$(cat "$MEM_CURRENT" 2>/dev/null)
    MEM_MAX_BYTES=$(cat "$MEM_MAX" 2>/dev/null)
    if [[ "$MEM_MAX_BYTES" != "max" && -n "$MEM_CUR_BYTES" && -n "$MEM_MAX_BYTES" ]]; then
        MEM_CUR_MB=$((MEM_CUR_BYTES / 1048576))
        MEM_MAX_MB=$((MEM_MAX_BYTES / 1048576))
        if [[ $MEM_MAX_MB -gt 0 ]]; then
            MEM_PCT=$((MEM_CUR_MB * 100 / MEM_MAX_MB))
            if [[ $MEM_PCT -ge 80 ]]; then
                warn "Memory usage: ${MEM_CUR_MB}MB / ${MEM_MAX_MB}MB (${MEM_PCT}%) — above 80% threshold"
                add_issue "WARN" "Memory at ${MEM_PCT}% of limit (${MEM_CUR_MB}MB / ${MEM_MAX_MB}MB)" \
                    "Memory usage is high. Consider increasing resources.limits.memory in the Deployment spec to avoid OOM kills."
            else
                pass "Memory usage: ${MEM_CUR_MB}MB / ${MEM_MAX_MB}MB (${MEM_PCT}%)"
            fi
        fi
    elif [[ "$MEM_MAX_BYTES" == "max" ]]; then
        MEM_CUR_MB=$((MEM_CUR_BYTES / 1048576))
        pass "Memory usage: ${MEM_CUR_MB}MB / unlimited"
    fi
else
    # Try cgroup v1
    MEM_V1_USAGE="/sys/fs/cgroup/memory/memory.usage_in_bytes"
    MEM_V1_LIMIT="/sys/fs/cgroup/memory/memory.limit_in_bytes"
    if [[ -f "$MEM_V1_USAGE" && -f "$MEM_V1_LIMIT" ]]; then
        MEM_CUR_BYTES=$(cat "$MEM_V1_USAGE" 2>/dev/null)
        MEM_MAX_BYTES=$(cat "$MEM_V1_LIMIT" 2>/dev/null)
        MEM_CUR_MB=$((MEM_CUR_BYTES / 1048576))
        MEM_MAX_MB=$((MEM_MAX_BYTES / 1048576))
        # cgroup v1 uses a very large number for "no limit"
        if [[ $MEM_MAX_MB -lt 1000000 && $MEM_MAX_MB -gt 0 ]]; then
            MEM_PCT=$((MEM_CUR_MB * 100 / MEM_MAX_MB))
            if [[ $MEM_PCT -ge 80 ]]; then
                warn "Memory usage: ${MEM_CUR_MB}MB / ${MEM_MAX_MB}MB (${MEM_PCT}%) — above 80% threshold"
                add_issue "WARN" "Memory at ${MEM_PCT}% of limit" \
                    "Consider increasing resources.limits.memory in the Deployment spec."
            else
                pass "Memory usage: ${MEM_CUR_MB}MB / ${MEM_MAX_MB}MB (${MEM_PCT}%)"
            fi
        else
            pass "Memory usage: ${MEM_CUR_MB}MB / unlimited"
        fi
    else
        info "Memory cgroup data not available"
    fi
fi

# --- P16: PID usage ---
PID_CURRENT="/sys/fs/cgroup/pids.current"
PID_MAX="/sys/fs/cgroup/pids.max"
if [[ -f "$PID_CURRENT" && -f "$PID_MAX" ]]; then
    PID_CUR=$(cat "$PID_CURRENT" 2>/dev/null)
    PID_LIM=$(cat "$PID_MAX" 2>/dev/null)
    if [[ "$PID_LIM" != "max" && -n "$PID_CUR" && -n "$PID_LIM" && "$PID_LIM" -gt 0 ]]; then
        PID_PCT=$((PID_CUR * 100 / PID_LIM))
        if [[ $PID_PCT -ge 80 ]]; then
            warn "PID usage: ${PID_CUR} / ${PID_LIM} (${PID_PCT}%) — above 80% threshold"
            add_issue "WARN" "PID usage at ${PID_PCT}% of limit" \
                "The container is approaching its PID limit. Check for process leaks or increase the PID limit."
        else
            pass "PID usage: ${PID_CUR} / ${PID_LIM} (${PID_PCT}%)"
        fi
    else
        pass "PID usage: ${PID_CUR} / unlimited"
    fi
else
    info "PID cgroup data not available"
fi

echo ""

# ============================= ENVIRONMENT INFO =============================
echo -e "${BOLD}── Environment Info ────────────────────────────────────────${NC}"
echo ""

# --- P17: Seccomp status ---
SECCOMP=$(grep -w Seccomp /proc/self/status 2>/dev/null | awk '{print $2}')
case "$SECCOMP" in
    0) info "Seccomp: disabled (0)" ;;
    1) info "Seccomp: strict (1)" ;;
    2) info "Seccomp: filter (2)" ;;
    *) info "Seccomp: unknown (${SECCOMP:-N/A})" ;;
esac

# --- P18: Memory configuration ---
if [[ -f /proc/sys/vm/overcommit_memory ]]; then
    OVERCOMMIT=$(cat /proc/sys/vm/overcommit_memory 2>/dev/null)
    info "vm.overcommit_memory: ${OVERCOMMIT}"
fi

# JVM process memory
JAVA_PID=$(pgrep -f 'java.*spring\|java.*emerald\|java.*agent' 2>/dev/null | head -1)
if [[ -n "$JAVA_PID" ]]; then
    JVM_RSS=$(awk '/VmRSS/{print $2, $3}' /proc/"$JAVA_PID"/status 2>/dev/null)
    JVM_VSZ=$(awk '/VmSize/{print $2, $3}' /proc/"$JAVA_PID"/status 2>/dev/null)
    if [[ -n "$JVM_RSS" ]]; then
        info "JVM process (PID ${JAVA_PID}): RSS=${JVM_RSS}, VSZ=${JVM_VSZ}"
    fi
fi

# --- P19: ulimits ---
info "ulimits:"
ulimit -a 2>/dev/null | while IFS= read -r line; do
    detail "  $line"
done

# --- P20: Environment variables ---
info "Environment variables (existence check):"
for VAR in MATILLION_REGION ACCOUNT_ID AGENT_ID OAUTH_CLIENT_ID CLOUD_PROVIDER MTLN_EMERALD_WORKING_DIR; do
    if [[ -n "${!VAR:-}" ]]; then
        # Mask the value — only show first 4 chars for IDs, presence for secrets
        VAL="${!VAR}"
        if [[ "$VAR" == *SECRET* || "$VAR" == *CLIENT_ID* ]]; then
            detail "  ${VAR}: [SET]"
        elif [[ ${#VAL} -gt 8 ]]; then
            detail "  ${VAR}: ${VAL:0:4}...${VAL: -4}"
        else
            detail "  ${VAR}: ${VAL}"
        fi
    else
        detail "  ${VAR}: [NOT SET]"
    fi
done

# --- P20b: Cloud Credential Validation ---
echo ""
echo -e "${BOLD}── Cloud Credential Validation ─────────────────────────────${NC}"
echo ""

CP="${CLOUD_PROVIDER:-}"
case "$CP" in
    AWS)
        ROLE_ARN_ENV="${AWS_ROLE_ARN:-}"
        TOKEN_FILE="${AWS_WEB_IDENTITY_TOKEN_FILE:-}"
        ACCESS_KEY="${AWS_ACCESS_KEY_ID:-}"
        SECRET_KEY="${AWS_SECRET_ACCESS_KEY:-}"

        if [[ -n "$ROLE_ARN_ENV" || -n "$TOKEN_FILE" ]]; then
            # IRSA mode
            if [[ -n "$TOKEN_FILE" && ! -f "$TOKEN_FILE" ]]; then
                fail "AWS IRSA token file not found: ${TOKEN_FILE}"
                detail "The webhook may not have injected the projected token"
                detail "Check that the EKS IRSA OIDC provider is configured and the SA annotation is correct"
                add_issue "FAIL" "AWS IRSA token file missing (${TOKEN_FILE})" \
                    "Verify the EKS IRSA OIDC provider is configured, the ServiceAccount has the correct annotation, and the mutating webhook is running"
            elif [[ -n "$TOKEN_FILE" && -f "$TOKEN_FILE" ]]; then
                pass "AWS IRSA credentials present (token file exists)"
                detail "AWS_ROLE_ARN: ${ROLE_ARN_ENV:-[not set]}"
                detail "AWS_WEB_IDENTITY_TOKEN_FILE: ${TOKEN_FILE}"
            else
                warn "AWS_ROLE_ARN set but AWS_WEB_IDENTITY_TOKEN_FILE not set"
                detail "IRSA may be partially configured"
                add_issue "WARN" "AWS IRSA partial: ROLE_ARN set but no token file" \
                    "Check that the EKS pod identity webhook is injecting the projected service account token"
            fi
        elif [[ -n "$ACCESS_KEY" && -n "$SECRET_KEY" ]]; then
            pass "AWS local credentials present (ACCESS_KEY_ID + SECRET_ACCESS_KEY)"
            detail "IRSA is recommended over static credentials for production use"
        else
            warn "AWS: no IRSA token and no local credentials detected"
            detail "Expected AWS_ROLE_ARN + AWS_WEB_IDENTITY_TOKEN_FILE (IRSA)"
            detail "Or AWS_ACCESS_KEY_ID + AWS_SECRET_ACCESS_KEY (static creds)"
            add_issue "WARN" "No AWS credentials found in pod environment" \
                "Configure IRSA (recommended) or inject AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY via a Secret"
        fi
        ;;
    AZURE)
        FED_TOKEN="${AZURE_FEDERATED_TOKEN_FILE:-}"
        AZ_CLIENT="${AZURE_CLIENT_ID:-}"
        AZ_TENANT="${AZURE_TENANT_ID:-}"
        AZ_SECRET="${AZURE_CLIENT_SECRET:-}"

        if [[ -n "$FED_TOKEN" ]]; then
            # Workload Identity mode
            if [[ ! -f "$FED_TOKEN" ]]; then
                fail "Azure WI federated token file not found: ${FED_TOKEN}"
                detail "The Azure Workload Identity webhook may not have injected the token"
                detail "Ensure the azure-wi-webhook-controller-manager is running and the SA is labelled"
                add_issue "FAIL" "Azure WI token file missing (${FED_TOKEN})" \
                    "Verify azure-workload-identity webhook is running, the ServiceAccount has label azure.workload.identity/use: \"true\" and the correct client-id annotation"
            elif [[ -n "$AZ_CLIENT" && -n "$AZ_TENANT" ]]; then
                pass "Azure Workload Identity credentials present"
                detail "AZURE_CLIENT_ID: ${AZ_CLIENT:0:4}...${AZ_CLIENT: -4}"
                detail "AZURE_TENANT_ID: ${AZ_TENANT:0:4}...${AZ_TENANT: -4}"
                detail "AZURE_FEDERATED_TOKEN_FILE: ${FED_TOKEN}"
            else
                warn "Azure WI token file exists but configuration is incomplete"
                [[ -z "$AZ_CLIENT" ]] && detail "AZURE_CLIENT_ID: [NOT SET]"
                [[ -z "$AZ_TENANT" ]] && detail "AZURE_TENANT_ID: [NOT SET]"
                add_issue "WARN" "Azure WI partial: token file present but missing env vars" \
                    "Ensure AZURE_CLIENT_ID and AZURE_TENANT_ID are injected by the webhook"
            fi
        elif [[ -n "$AZ_CLIENT" && -n "$AZ_SECRET" && -n "$AZ_TENANT" ]]; then
            pass "Azure Service Principal credentials present"
            detail "Workload Identity is recommended over SP secrets for production use"
        else
            warn "Azure: no Workload Identity token and no SP credentials detected"
            detail "Expected AZURE_FEDERATED_TOKEN_FILE (Workload Identity)"
            detail "Or AZURE_CLIENT_ID + AZURE_CLIENT_SECRET + AZURE_TENANT_ID (Service Principal)"
            add_issue "WARN" "No Azure credentials found in pod environment" \
                "Configure Workload Identity (recommended) or inject SP credentials via a Secret"
        fi
        ;;
    "")
        warn "CLOUD_PROVIDER not set — cannot validate cloud credentials"
        detail "Set CLOUD_PROVIDER to AWS or AZURE in your deployment configuration"
        add_issue "WARN" "CLOUD_PROVIDER not set" \
            "Set the CLOUD_PROVIDER environment variable on the agent pod"
        ;;
    *)
        info "CLOUD_PROVIDER=${CP} — skipping credential validation (only AWS/AZURE supported)"
        ;;
esac

# --- P21: Java/Python versions ---
if command -v java >/dev/null 2>&1; then
    info "Java version: $(java -version 2>&1 | head -1)"
fi
if command -v python3 >/dev/null 2>&1; then
    info "Python version: $(python3 --version 2>&1)"
fi

# --- P22: DNS resolution & HTTPS connectivity ---
# Matillion platform endpoints the agent must reach
REGION="${MATILLION_REGION:-}"
OTEL_HOST=""
case "$REGION" in
    eu|eu1) OTEL_HOST="opentelemetry.eu1.core.matillion.com" ;;
    us|us1) OTEL_HOST="opentelemetry.us1.core.matillion.com" ;;
    ap|ap1) OTEL_HOST="opentelemetry.us1.core.matillion.com" ;;  # AP falls back to US
    *)      OTEL_HOST="opentelemetry.us1.core.matillion.com" ;;
esac
DNS_TARGETS=(
    "keycloak.core.matillion.com"
    "$OTEL_HOST"
)

# Pick the best available lookup tool
DNS_TOOL=""
if command -v nslookup >/dev/null 2>&1; then
    DNS_TOOL="nslookup"
elif command -v getent >/dev/null 2>&1; then
    DNS_TOOL="getent"
fi

if [[ -n "$DNS_TOOL" ]]; then
    for DNS_TARGET in "${DNS_TARGETS[@]}"; do
        case "$DNS_TOOL" in
            nslookup) RESULT=$( nslookup "$DNS_TARGET" 2>&1 ) ;;
            getent)   RESULT=$( getent hosts "$DNS_TARGET" 2>&1 ) ;;
        esac
        if [[ $? -eq 0 ]]; then
            info "DNS resolution: ${DNS_TARGET} — OK"
        else
            warn "DNS resolution: ${DNS_TARGET} — FAILED"
            add_issue "WARN" "Cannot resolve ${DNS_TARGET}" \
                "Ensure DNS is configured correctly and network policies allow DNS egress (port 53). Check the NetworkPolicy and CoreDNS configuration."
        fi
    done
else
    info "DNS resolution: no lookup tool available (nslookup/getent)"
fi

# --- P22b: HTTPS connectivity ---
if command -v curl >/dev/null 2>&1; then
    for ENDPOINT in "${DNS_TARGETS[@]}"; do
        HTTP_CODE=$(curl -so /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 10 "https://${ENDPOINT}/" 2>/dev/null || echo "000")
        if [[ "$HTTP_CODE" == "000" ]]; then
            warn "HTTPS connectivity: ${ENDPOINT} — connection failed"
            add_issue "WARN" "Cannot reach https://${ENDPOINT} (connection failed)" \
                "Verify network egress is allowed to port 443. Check NetworkPolicies, firewall rules, and proxy settings (PROXY_HTTPS)."
        elif [[ "$HTTP_CODE" =~ ^[2345] ]]; then
            info "HTTPS connectivity: ${ENDPOINT} — OK (HTTP ${HTTP_CODE})"
        else
            warn "HTTPS connectivity: ${ENDPOINT} — unexpected HTTP ${HTTP_CODE}"
        fi
    done
elif command -v wget >/dev/null 2>&1; then
    for ENDPOINT in "${DNS_TARGETS[@]}"; do
        if wget -q --spider --timeout=5 "https://${ENDPOINT}/" 2>/dev/null; then
            info "HTTPS connectivity: ${ENDPOINT} — OK"
        else
            warn "HTTPS connectivity: ${ENDPOINT} — connection failed"
            add_issue "WARN" "Cannot reach https://${ENDPOINT}" \
                "Verify network egress is allowed to port 443. Check NetworkPolicies, firewall rules, and proxy settings."
        fi
    done
else
    info "HTTPS connectivity: no curl or wget available — skipped"
fi

# --- P25: JVM heap and GC settings ---
if [[ -z "$JAVA_PID" ]]; then
    JAVA_PID=$(pgrep -f 'java' 2>/dev/null | head -1)
fi
if [[ -n "$JAVA_PID" && -f "/proc/${JAVA_PID}/cmdline" ]]; then
    JVM_CMDLINE=$(tr '\0' ' ' < "/proc/${JAVA_PID}/cmdline" 2>/dev/null)
    # Extract heap settings
    XMX=$(echo "$JVM_CMDLINE" | grep -oE '\-Xmx[0-9]+[kmgKMG]?' || true)
    XMS=$(echo "$JVM_CMDLINE" | grep -oE '\-Xms[0-9]+[kmgKMG]?' || true)
    GC_ALG=$(echo "$JVM_CMDLINE" | grep -oE '\-XX:\+Use[A-Za-z]+GC' || true)
    MAX_RAM_PCT=$(echo "$JVM_CMDLINE" | grep -oE '\-XX:MaxRAMPercentage=[0-9.]+' || true)
    MIN_RAM_PCT=$(echo "$JVM_CMDLINE" | grep -oE '\-XX:MinRAMPercentage=[0-9.]+' || true)
    INIT_RAM_PCT=$(echo "$JVM_CMDLINE" | grep -oE '\-XX:InitialRAMPercentage=[0-9.]+' || true)

    # Build heap description: prefer explicit -Xmx, fall back to MaxRAMPercentage
    HEAP_DESC=""
    if [[ -n "$XMX" ]]; then
        HEAP_DESC="${XMX}"
        [[ -n "$XMS" ]] && HEAP_DESC="${HEAP_DESC}, ${XMS}"
    elif [[ -n "$MAX_RAM_PCT" ]]; then
        HEAP_DESC="${MAX_RAM_PCT}"
        [[ -n "$INIT_RAM_PCT" ]] && HEAP_DESC="${HEAP_DESC}, ${INIT_RAM_PCT}"
    else
        HEAP_DESC="heap=JVM defaults"
    fi

    info "JVM settings: ${HEAP_DESC} | ${GC_ALG:-GC=default}"
    # Show full JVM args for diagnostics
    JVM_OPTS=$(echo "$JVM_CMDLINE" | grep -oE '\-X[^ ]+|\-D[^ ]+|\-XX:[^ ]+' | tr '\n' ' ' || true)
    if [[ -n "$JVM_OPTS" ]]; then
        detail "  All JVM flags: ${JVM_OPTS}"
    fi
else
    info "JVM settings: Java process not found or /proc not available"
fi

# --- P23: Disk space ---
info "Disk space:"
for MOUNT_PATH in /tmp /dev/shm "$WORK_DIR"; do
    if [[ -d "$MOUNT_PATH" ]]; then
        DF_LINE=$(df -h "$MOUNT_PATH" 2>/dev/null | awk 'NR==2{print $2, $3, $4, $5}')
        detail "  ${MOUNT_PATH}: ${DF_LINE:-unknown}"
    fi
done

# --- P24: Mount flags ---
info "Mount flags for key filesystems:"
for MP in /tmp /dev/shm "$WORK_DIR"; do
    MFLAGS=$(mount 2>/dev/null | grep " ${MP} " | head -1)
    if [[ -n "$MFLAGS" ]]; then
        detail "  ${MP}: ${MFLAGS}"
    else
        detail "  ${MP}: (no dedicated mount point)"
    fi
done

echo ""

# ================================= SUMMARY ==================================
SUMMARY_COUNTS="${PASS_COUNT} passed  ${WARN_COUNT} warnings  ${FAIL_COUNT} failed"
if [[ $FAIL_COUNT -gt 0 ]]; then
    RESULT_PLAIN="RESULT: FAIL"
    RESULT_FMT="${RED}RESULT: FAIL${NC}"
else
    RESULT_PLAIN="RESULT: PASS"
    RESULT_FMT="${GREEN}RESULT: PASS${NC}"
fi
box_top
box_line "$RESULT_PLAIN" "$RESULT_FMT"
box_line "$SUMMARY_COUNTS" "${GREEN}${PASS_COUNT} passed${NC}  ${YELLOW}${WARN_COUNT} warnings${NC}  ${RED}${FAIL_COUNT} failed${NC}"
box_bottom

# ============================= REMEDIATION ==================================
if [[ ${#ISSUES[@]} -gt 0 ]]; then
    echo ""
    echo -e "${BOLD}── Remediation Steps ───────────────────────────────────────${NC}"
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

if [[ $FAIL_COUNT -gt 0 ]]; then
    exit 1
fi
exit 0
