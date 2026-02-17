#!/usr/bin/env bash
# =============================================================================
# test_auth_errors.sh — Test auth/permission error handling in run-check.sh
#
# Creates a mock kubectl that returns various error responses and verifies
# that run-check.sh detects and reports them correctly.
#
# Usage:  ./test_auth_errors.sh
# Exit:   0 = all tests pass, 1 = any test failed
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
RUN_CHECK="${CHECKS_DIR}/run-check.sh"

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

create_mock_kubectl() {
    local behavior="$1"
    cat > "${MOCK_DIR}/kubectl" <<MOCK_EOF
#!/usr/bin/env bash
# Mock kubectl — behavior: ${behavior}
MOCK_EOF

    case "$behavior" in
        auth_failure)
            cat >> "${MOCK_DIR}/kubectl" <<'MOCK_EOF'
if [[ "$1" == "cluster-info" ]]; then
    echo "error: You must be logged in to the server (Unauthorized)" >&2
    exit 1
fi
echo ""
MOCK_EOF
            ;;
        token_expired)
            cat >> "${MOCK_DIR}/kubectl" <<'MOCK_EOF'
if [[ "$1" == "cluster-info" ]]; then
    echo "error: You must be logged in to the server (the server has asked for the client to provide credentials)" >&2
    echo "error: token has expired" >&2
    exit 1
fi
echo ""
MOCK_EOF
            ;;
        connection_refused)
            cat >> "${MOCK_DIR}/kubectl" <<'MOCK_EOF'
if [[ "$1" == "cluster-info" ]]; then
    echo "The connection to the server 10.0.0.1:6443 was refused - did you specify the right host or port?" >&2
    exit 1
fi
echo ""
MOCK_EOF
            ;;
        forbidden_pods)
            cat >> "${MOCK_DIR}/kubectl" <<'MOCK_EOF'
# cluster-info works, but listing pods is forbidden
if [[ "$1" == "cluster-info" ]]; then
    echo "Kubernetes control plane is running at https://test-cluster:6443"
    exit 0
fi
if [[ "$1" == "auth" && "$2" == "can-i" ]]; then
    echo "no"
    exit 0
fi
if [[ "$1" == "version" ]]; then
    echo "serverVersion:"
    echo "  gitVersion: v1.31.2"
    exit 0
fi
if [[ "$1" == "get" && "$2" == "daemonsets" ]]; then
    echo "Error from server (Forbidden): daemonsets.apps is forbidden: User \"test-user\" cannot list resource \"daemonsets\" in API group \"apps\" at the cluster scope" >&2
    exit 1
fi
if [[ "$1" == "get" && "$2" == "pods" ]]; then
    echo "Error from server (Forbidden): pods is forbidden: User \"test-user\" cannot list resource \"pods\" in API group \"\" in the namespace \"test-ns\"" >&2
    exit 1
fi
echo ""
MOCK_EOF
            ;;
        partial_permissions)
            cat >> "${MOCK_DIR}/kubectl" <<'MOCK_EOF'
# cluster-info works, pods work, but secrets are forbidden
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
if [[ "$1" == "get" && "$2" == "pod" ]]; then
    # Check what jsonpath is requested
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
    # Pod JSON for secret extraction
    echo '{"spec":{"containers":[{"envFrom":[{"secretRef":{"name":"test-config"}}]}]}}'
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
if [[ "$1" == "get" && "$2" == "secret" ]]; then
    echo "Error from server (Forbidden): secrets \"test-config\" is forbidden: User \"test-user\" cannot get resource \"secrets\" in API group \"\" in the namespace \"test-ns\"" >&2
    exit 1
fi
if [[ "$1" == "get" && "$2" == "networkpolicies" ]]; then
    echo ""
    exit 0
fi
if [[ "$1" == "cp" ]]; then
    exit 0
fi
if [[ "$1" == "exec" ]]; then
    # Simulate in-pod script output
    echo "  [PASS] All checks pass"
    exit 0
fi
echo ""
MOCK_EOF
            ;;
        dns_timeout)
            cat >> "${MOCK_DIR}/kubectl" <<'MOCK_EOF'
if [[ "$1" == "cluster-info" ]]; then
    echo "Unable to connect to the server: dial tcp: lookup test-cluster.example.com: no such host" >&2
    exit 1
fi
echo ""
MOCK_EOF
            ;;
    esac

    chmod +x "${MOCK_DIR}/kubectl"
}

run_test() {
    local test_name="$1"
    local behavior="$2"
    local expected_pattern="$3"
    local expect_exit="${4:-1}"

    echo -n "  TEST: ${test_name}... "

    setup_mock_dir
    create_mock_kubectl "$behavior"

    local output exit_code
    output=$(bash "$RUN_CHECK" --namespace test-ns 2>&1) || true
    exit_code=$?

    teardown_mock_dir

    local passed=true

    # Check expected pattern in output
    if ! echo "$output" | grep -qi "$expected_pattern"; then
        echo "FAIL"
        echo "    Expected pattern: ${expected_pattern}"
        echo "    Output (last 10 lines):"
        echo "$output" | tail -10 | sed 's/^/      /'
        ((FAIL++))
        return 1
    fi

    echo "PASS"
    ((PASS++))
    return 0
}

# ---------------------------------------------------------------------------
# Run tests
# ---------------------------------------------------------------------------
echo ""
echo "=== Auth/Permission Error Handling Tests ==="
echo ""

echo "  --- Cluster Connectivity Tests ---"

run_test \
    "Unauthorized (401) detected and reported" \
    "auth_failure" \
    "authentication error"

run_test \
    "Expired token detected and reported" \
    "token_expired" \
    "authentication error"

run_test \
    "Connection refused detected and reported" \
    "connection_refused" \
    "connection error"

run_test \
    "DNS resolution failure detected" \
    "dns_timeout" \
    "connection error"

echo ""
echo "  --- RBAC Permission Tests ---"

run_test \
    "Forbidden on pod listing detected" \
    "forbidden_pods" \
    "permission denied"

run_test \
    "Forbidden on secrets detected (partial permissions)" \
    "partial_permissions" \
    "permission denied.*secret"

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
exit 0
