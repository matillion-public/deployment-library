#!/usr/bin/env bash
# =============================================================================
# test_crowdstrike_detection.sh — Test CrowdStrike detection and Python kill
#
# Creates mock kubectl and Python environments to verify:
# 1. CrowdStrike DaemonSet detection in cluster checks
# 2. Python file-based kill detection (exit 137) in in-pod checks
#
# Usage:  ./test_crowdstrike_detection.sh
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
        echo "    Output (last 15 lines):"
        echo "$output" | tail -15 | sed 's/^/      /'
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
        ((FAIL++))
        return 1
    else
        echo "PASS"
        ((PASS++))
        return 0
    fi
}

# ---------------------------------------------------------------------------
# Test 1: CrowdStrike DaemonSet detection (cluster-level)
# ---------------------------------------------------------------------------
create_mock_kubectl_with_crowdstrike() {
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
    # Return CrowdStrike falcon-sensor DaemonSet
    printf 'falcon-system\tfalcon-sensor\tcrowdstrike/falcon-sensor:7.10.0\n'
    printf 'falcon-system\tfalcon-node-sensor\tcrowdstrike/falcon-node-sensor:7.10.0\n'
    exit 0
fi
if [[ "$1" == "get" && "$2" == "pods" ]]; then
    # Check if querying for security pods on node or agent pods
    if echo "$*" | grep -q "field-selector"; then
        # Security pods on node query
        printf 'falcon-sensor-abc123\tRunning\n'
        exit 0
    fi
    # Agent pod query
    printf 'test-ns\ttest-agent-app-abc123\tRunning\tnode-1\t0\n'
    exit 0
fi
if [[ "$1" == "get" && "$2" == "pod" ]]; then
    if echo "$*" | grep -q 'serviceAccountName'; then
        echo "test-sa"
        exit 0
    fi
    if echo "$*" | grep -q 'containers\[0\].image'; then
        echo "public.ecr.aws/matillion/etl-agent:current"
        exit 0
    fi
    if echo "$*" | grep -q 'imageID'; then
        echo ""
        exit 0
    fi
    echo '{"spec":{"containers":[{"envFrom":[]}]}}'
    exit 0
fi
if [[ "$1" == "get" && "$2" == "namespace" ]]; then
    echo '{}'
    exit 0
fi
if [[ "$1" == "get" && "$2" == "serviceaccount" ]]; then
    echo '{"metadata":{"annotations":{}}}'
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
echo ""
MOCK_EOF
    chmod +x "${MOCK_DIR}/kubectl"
}

create_mock_kubectl_no_security() {
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
    # Return non-security DaemonSets only
    printf 'kube-system\tkube-proxy\tregistry.k8s.io/kube-proxy:v1.31.2\n'
    printf 'kube-system\tcoredns\tregistry.k8s.io/coredns:v1.11.3\n'
    exit 0
fi
if [[ "$1" == "get" && "$2" == "pods" ]]; then
    printf 'test-ns\ttest-agent-app-abc123\tRunning\tnode-1\t0\n'
    exit 0
fi
if [[ "$1" == "get" && "$2" == "pod" ]]; then
    if echo "$*" | grep -q 'serviceAccountName'; then echo "test-sa"; exit 0; fi
    if echo "$*" | grep -q 'containers\[0\].image'; then echo "public.ecr.aws/matillion/etl-agent:current"; exit 0; fi
    if echo "$*" | grep -q 'imageID'; then echo ""; exit 0; fi
    echo '{"spec":{"containers":[{"envFrom":[]}]}}'
    exit 0
fi
if [[ "$1" == "get" && "$2" == "namespace" ]]; then echo '{}'; exit 0; fi
if [[ "$1" == "get" && "$2" == "serviceaccount" ]]; then echo '{"metadata":{"annotations":{}}}'; exit 0; fi
if [[ "$1" == "get" && "$2" == "networkpolicies" ]]; then echo ""; exit 0; fi
if [[ "$1" == "cp" ]]; then exit 0; fi
if [[ "$1" == "exec" ]]; then echo "  [PASS] All checks"; exit 0; fi
echo ""
MOCK_EOF
    chmod +x "${MOCK_DIR}/kubectl"
}

echo ""
echo "=== CrowdStrike Detection & Python Kill Tests ==="
echo ""

# --- Cluster-level CrowdStrike detection ---
echo "  --- Cluster-Level CrowdStrike Detection ---"

setup_mock_dir
create_mock_kubectl_with_crowdstrike
CS_OUTPUT=$(bash "$RUN_CHECK" --namespace test-ns 2>&1) || true
teardown_mock_dir

assert_output_contains "$CS_OUTPUT" \
    "CrowdStrike Falcon detected" \
    "CrowdStrike DaemonSet detected in cluster scan"

assert_output_contains "$CS_OUTPUT" \
    "container drift detection may block Python" \
    "CrowdStrike drift warning shown"

assert_output_contains "$CS_OUTPUT" \
    "falcon-sensor" \
    "Falcon sensor DaemonSet name reported"

assert_output_contains "$CS_OUTPUT" \
    "falcon-system" \
    "Falcon namespace reported"

assert_output_contains "$CS_OUTPUT" \
    "pod running on agent node" \
    "CrowdStrike pod detected on agent's node"

# --- No CrowdStrike scenario ---
echo ""
echo "  --- Clean Cluster (No Security DaemonSets) ---"

setup_mock_dir
create_mock_kubectl_no_security
CLEAN_OUTPUT=$(bash "$RUN_CHECK" --namespace test-ns 2>&1) || true
teardown_mock_dir

assert_output_contains "$CLEAN_OUTPUT" \
    "No known security DaemonSets detected" \
    "Reports clean when no security DaemonSets found"

assert_output_not_contains "$CLEAN_OUTPUT" \
    "CrowdStrike" \
    "No CrowdStrike warnings on clean cluster"

# ---------------------------------------------------------------------------
# Test 2: Python file-based kill detection (in-pod)
# ---------------------------------------------------------------------------
echo ""
echo "  --- Python File-Based Kill Detection (in-pod) ---"

# Create a mock environment for the in-pod script
MOCK_ENV=$(mktemp -d)
MOCK_BIN="${MOCK_ENV}/bin"
mkdir -p "$MOCK_BIN"

# Mock python3 — inline works, file-based returns 137 (simulating CrowdStrike kill)
cat > "${MOCK_BIN}/python3" <<'PYEOF'
#!/usr/bin/env bash
if [[ "$1" == "-c" ]]; then
    # Simulate Python print() for inline execution
    if echo "$2" | grep -q "^print("; then
        echo "$2" | sed "s/^print(['\"]//;s/['\"])$//"
    fi
    exit 0
fi
if [[ "$1" == "--version" ]]; then
    echo "Python 3.10.12"
    exit 0
fi
# File-based execution — simulate SIGKILL (exit 137)
exit 137
PYEOF
chmod +x "${MOCK_BIN}/python3"

# Mock java
cat > "${MOCK_BIN}/java" <<'JEOF'
#!/usr/bin/env bash
if [[ "$1" == "-version" || "$1" == "--version" ]]; then
    echo 'openjdk version "21.0.9" 2025-10-21' >&2
    exit 0
fi
echo "java mock"
JEOF
chmod +x "${MOCK_BIN}/java"

# Mock sudo
cat > "${MOCK_BIN}/sudo" <<'SEOF'
#!/usr/bin/env bash
echo "mock sudo"
SEOF
chmod +x "${MOCK_BIN}/sudo"

# Create necessary filesystem structure
mkdir -p "${MOCK_ENV}/tmp" "${MOCK_ENV}/home/agentuser" "${MOCK_ENV}/dev/shm"
mkdir -p "${MOCK_ENV}/proc/self" "${MOCK_ENV}/sys/fs/cgroup"

# Create mock /proc/self/status
cat > "${MOCK_ENV}/proc/self/status" <<'EOF'
Name:   bash
Seccomp:        0
EOF

# Create mock cgroup files
echo "104857600" > "${MOCK_ENV}/sys/fs/cgroup/memory.current"
echo "4294967296" > "${MOCK_ENV}/sys/fs/cgroup/memory.max"
echo "oom_kill 0" > "${MOCK_ENV}/sys/fs/cgroup/memory.events"
echo "50" > "${MOCK_ENV}/sys/fs/cgroup/pids.current"
echo "32768" > "${MOCK_ENV}/sys/fs/cgroup/pids.max"

# Run the in-pod script with the mock environment
# We need to override PATH and make /tmp writable
export FORCE_COLOR=0
INPOD_OUTPUT=$(
    PATH="${MOCK_BIN}:/usr/bin:/bin" \
    TMPDIR="${MOCK_ENV}/tmp" \
    HOME="${MOCK_ENV}/home/agentuser" \
    MTLN_EMERALD_WORKING_DIR="${MOCK_ENV}/home/agentuser" \
    MATILLION_REGION="eu1" \
    ACCOUNT_ID="test-account-123" \
    AGENT_ID="test-agent-456" \
    CLOUD_PROVIDER="AZURE" \
    bash "$IN_POD_CHECK" 2>&1
) || true

assert_output_contains "$INPOD_OUTPUT" \
    "file-based execution.*\(exit 137\)\|killed.*137\|exit 137" \
    "Detects Python file-based execution killed with exit 137"

assert_output_contains "$INPOD_OUTPUT" \
    "runtime security\|security tool\|CrowdStrike\|drift" \
    "Suggests runtime security tool interference"

assert_output_contains "$INPOD_OUTPUT" \
    "FAIL" \
    "Reports overall FAIL when Python file execution is killed"

# --- Test that inline works but file fails (mismatch detection) ---
assert_output_contains "$INPOD_OUTPUT" \
    "inline.*works\|inline execution works" \
    "Inline Python execution reported as working"

rm -rf "$MOCK_ENV"

# ---------------------------------------------------------------------------
# Test 3: Python file-based works normally (no kill)
# ---------------------------------------------------------------------------
echo ""
echo "  --- Python File-Based Execution Normal (no kill) ---"

MOCK_ENV2=$(mktemp -d)
MOCK_BIN2="${MOCK_ENV2}/bin"
mkdir -p "$MOCK_BIN2"

# Normal python3 — both inline and file-based work
cat > "${MOCK_BIN2}/python3" <<'PYEOF'
#!/usr/bin/env bash
if [[ "$1" == "-c" ]]; then
    # Simulate Python print() for inline execution
    if echo "$2" | grep -q "^print("; then
        echo "$2" | sed "s/^print(['\"]//;s/['\"])$//"
    fi
    exit 0
fi
if [[ "$1" == "--version" ]]; then
    echo "Python 3.10.12"
    exit 0
fi
# File-based execution — simulate Python by extracting print() calls
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
chmod +x "${MOCK_BIN2}/python3"

# Mock java
cat > "${MOCK_BIN2}/java" <<'JEOF'
#!/usr/bin/env bash
if [[ "$1" == "-version" || "$1" == "--version" ]]; then
    echo 'openjdk version "21.0.9" 2025-10-21' >&2
    exit 0
fi
JEOF
chmod +x "${MOCK_BIN2}/java"

cat > "${MOCK_BIN2}/sudo" <<'SEOF'
#!/usr/bin/env bash
echo "mock sudo"
SEOF
chmod +x "${MOCK_BIN2}/sudo"

mkdir -p "${MOCK_ENV2}/tmp" "${MOCK_ENV2}/home/agentuser" "${MOCK_ENV2}/dev/shm"
mkdir -p "${MOCK_ENV2}/proc/self" "${MOCK_ENV2}/sys/fs/cgroup"

cat > "${MOCK_ENV2}/proc/self/status" <<'EOF'
Seccomp:        0
EOF
echo "104857600" > "${MOCK_ENV2}/sys/fs/cgroup/memory.current"
echo "4294967296" > "${MOCK_ENV2}/sys/fs/cgroup/memory.max"
echo "oom_kill 0" > "${MOCK_ENV2}/sys/fs/cgroup/memory.events"
echo "50" > "${MOCK_ENV2}/sys/fs/cgroup/pids.current"
echo "32768" > "${MOCK_ENV2}/sys/fs/cgroup/pids.max"

INPOD_OK_OUTPUT=$(
    PATH="${MOCK_BIN2}:/usr/bin:/bin" \
    TMPDIR="${MOCK_ENV2}/tmp" \
    HOME="${MOCK_ENV2}/home/agentuser" \
    MTLN_EMERALD_WORKING_DIR="${MOCK_ENV2}/home/agentuser" \
    MATILLION_REGION="us1" \
    ACCOUNT_ID="test-account-123" \
    AGENT_ID="test-agent-456" \
    CLOUD_PROVIDER="AWS" \
    FORCE_COLOR=0 \
    bash "$IN_POD_CHECK" 2>&1
) || true

assert_output_contains "$INPOD_OK_OUTPUT" \
    "file-based execution works" \
    "File-based Python execution reported as working when not killed"

assert_output_contains "$INPOD_OK_OUTPUT" \
    "inline.*file-based.*match\|results match" \
    "Inline and file-based results match"

assert_output_not_contains "$INPOD_OK_OUTPUT" \
    "runtime security\|security tool" \
    "No security tool warning when Python works normally"

rm -rf "$MOCK_ENV2"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
exit 0
