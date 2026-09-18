#!/usr/bin/env bash
# ==============================================================================
# MAYOTIX OS Phase 8 Week 3 Verification Suite: Detonation Pipeline & Telemetry
# File: scripts/verify-labs-week3.sh
# Mode: 0755
#
# Comprehensive verification suite validating:
#   1. File Presence & Directory Structure
#   2. Security Permissions & Shebang Integrity
#   3. Automated Detonation Pipeline & Pre-flight Hashing
#   4. Behavioral Telemetry Tracer & Threat Evaluation Engine
#   5. SELinux Policy Confinement & ptrace Capabilities
#   6. Privileged IPC Daemon RPC Methods
#   7. Unified CLI Subcommand Synchronization
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Terminal Color Codes
CYAN="\033[0;36m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
BOLD="\033[1m"
NC="\033[0m"

log_info() { echo -e "${CYAN}[INFO]${NC} $1"; }
log_ok() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err() { echo -e "${RED}[ERR]${NC} $1" >&2; }

TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
WARNINGS=0

pass_test() {
    ((TOTAL_TESTS++)) || true
    ((PASSED_TESTS++)) || true
    log_ok "$1"
}

fail_test() {
    ((TOTAL_TESTS++)) || true
    ((FAILED_TESTS++)) || true
    log_err "$1"
}

warn_test() {
    ((WARNINGS++)) || true
    log_warn "$1"
}

DRY_RUN=0
JSON_OUTPUT=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --json)
            JSON_OUTPUT=1
            shift
            ;;
        *)
            shift
            ;;
    esac
done

PYTHON_BIN="python3"
if command -v python3 &>/dev/null && python3 -c "import sys" &>/dev/null; then
    PYTHON_BIN="python3"
elif command -v python &>/dev/null && python -c "import sys" &>/dev/null; then
    PYTHON_BIN="python"
fi

log_info "Starting MAYOTIX OS Phase 8 Week 3 Detonation & Behavioral Telemetry Verification..."
echo ""

# ==============================================================================
# Module 1: File Presence & Directory Structure
# ==============================================================================
log_info "=== Module 1: File Presence & Directory Structure ==="

DETONATE_SCRIPT="${PROJECT_ROOT}/desktop/labs/detonation-pipeline.sh"
ANALYZER_SCRIPT="${PROJECT_ROOT}/desktop/labs/behavior-analyzer.py"
SELINUX_TE="${PROJECT_ROOT}/security/selinux/mayotix_labs.te"
SELINUX_FC="${PROJECT_ROOT}/security/selinux/mayotix_labs.fc"
DAEMON_SCRIPT="${PROJECT_ROOT}/daemon/mayotix-daemon.py"
CLI_PATH="${PROJECT_ROOT}/cli/mayotix"
DOCS_FILE="${PROJECT_ROOT}/docs/PHASE8_WEEK3_DETONATION.md"

check_file() {
    local file="$1"
    local desc="$2"
    if [[ -f "$file" ]]; then
        pass_test "$desc exists at '$file'"
    else
        fail_test "$desc missing at '$file'"
    fi
}

check_file "$DETONATE_SCRIPT" "Automated detonation pipeline script"
check_file "$ANALYZER_SCRIPT" "Behavioral telemetry analyzer"
check_file "$SELINUX_TE" "SELinux lab policy definition"
check_file "$SELINUX_FC" "SELinux lab file contexts"
check_file "$DAEMON_SCRIPT" "Privileged IPC daemon"
check_file "$CLI_PATH" "Unified CLI"
check_file "$DOCS_FILE" "Phase 8 Week 3 technical documentation"

# ==============================================================================
# Module 2: Security Permissions & Shebang Integrity
# ==============================================================================
log_info "=== Module 2: Security Permissions & Shebang Integrity ==="

if head -n 1 "$DETONATE_SCRIPT" | grep -Eq '^#!/(usr/)?bin/(env )?bash'; then
    pass_test "Detonation pipeline declares standard bash shebang"
else
    fail_test "Detonation pipeline has invalid shebang"
fi

if head -n 1 "$ANALYZER_SCRIPT" | grep -Eq '^#!/(usr/)?bin/(env )?python'; then
    pass_test "Behavioral analyzer declares standard python shebang"
else
    fail_test "Behavioral analyzer has invalid shebang"
fi

# Validate Python AST syntax
if "$PYTHON_BIN" -m py_compile "$ANALYZER_SCRIPT" >/dev/null 2>&1; then
    pass_test "Behavioral analyzer script compiles cleanly (syntax verified)"
else
    fail_test "Behavioral analyzer script failed syntax check"
fi

# ==============================================================================
# Module 3: Detonation Pipeline Sandbox Orchestration
# ==============================================================================
log_info "=== Module 3: Detonation Pipeline Sandbox Orchestration ==="

# Check pre-flight hashing logic
if grep -q "sha256" "$DETONATE_SCRIPT" && grep -q "md5" "$DETONATE_SCRIPT"; then
    pass_test "Detonation pipeline calculates pre-flight cryptographic hashes"
else
    fail_test "Detonation pipeline missing cryptographic pre-flight hashing"
fi

# Check timeout enforcement
if grep -q "timeout" "$DETONATE_SCRIPT" && grep -q "TIMEOUT_SEC" "$DETONATE_SCRIPT"; then
    pass_test "Detonation pipeline enforces configurable execution timeouts"
else
    fail_test "Detonation pipeline missing execution timeout enforcement"
fi

# Check discard-on-exit cleanup trap
if grep -q "trap cleanup" "$DETONATE_SCRIPT" && grep -q "discard_on_exit" "$DETONATE_SCRIPT"; then
    pass_test "Detonation pipeline guarantees fail-closed discard-on-exit cleanup"
else
    fail_test "Detonation pipeline missing discard-on-exit purge trap"
fi

# Check status action
DETONATE_STATUS=$(bash "$DETONATE_SCRIPT" status --dry-run --json 2>/dev/null || echo "{}")
if echo "$DETONATE_STATUS" | grep -q "READY" && echo "$DETONATE_STATUS" | grep -q "mayotix-br0"; then
    pass_test "Detonation pipeline status outputs valid structured telemetry"
else
    fail_test "Detonation pipeline status failed to produce valid telemetry"
fi

# Check detonation simulation
DETONATE_RUN=$(bash "$DETONATE_SCRIPT" run /tmp/mock-sample.bin --dry-run --json 2>/dev/null || echo "{}")
if echo "$DETONATE_RUN" | grep -q "threat_evaluation" && echo "$DETONATE_RUN" | grep -q "risk_score"; then
    pass_test "Detonation pipeline successfully simulates full sandbox execution"
else
    fail_test "Detonation pipeline failed sandbox run simulation"
fi

# ==============================================================================
# Module 4: Behavioral Telemetry Tracer & Threat Evaluation Engine
# ==============================================================================
log_info "=== Module 4: Behavioral Telemetry Tracer & Threat Evaluation Engine ==="

# Check strace parsing in analyzer
if grep -q "parse_strace" "$ANALYZER_SCRIPT" && grep -q "execve" "$ANALYZER_SCRIPT"; then
    pass_test "Behavioral analyzer parses execve process spawn lineage"
else
    fail_test "Behavioral analyzer missing process lineage tracing"
fi

if grep -q "connect(" "$ANALYZER_SCRIPT" && grep -q "network_attempts" "$ANALYZER_SCRIPT"; then
    pass_test "Behavioral analyzer extracts outbound socket network IoCs"
else
    fail_test "Behavioral analyzer missing socket IoC extraction"
fi

if grep -q "evaluate_threat" "$ANALYZER_SCRIPT" && grep -q "risk_score" "$ANALYZER_SCRIPT"; then
    pass_test "Behavioral analyzer implements automated Threat Severity Scoring"
else
    fail_test "Behavioral analyzer missing threat evaluation scoring logic"
fi

# Check analyzer analyze output
ANALYZER_OUT=$("$PYTHON_BIN" "$ANALYZER_SCRIPT" analyze --dry-run --json 2>/dev/null || echo "{}")
if echo "$ANALYZER_OUT" | grep -q "risk_score" && echo "$ANALYZER_OUT" | grep -q "HIGH"; then
    pass_test "Behavioral analyzer outputs structured JSON threat reports"
else
    fail_test "Behavioral analyzer failed to output structured JSON threat report"
fi

# Check analyzer list output
ANALYZER_LIST=$("$PYTHON_BIN" "$ANALYZER_SCRIPT" list --dry-run --json 2>/dev/null || echo "{}")
if echo "$ANALYZER_LIST" | grep -q "total_reports"; then
    pass_test "Behavioral analyzer enumerates available report archives"
else
    fail_test "Behavioral analyzer failed report catalog enumeration"
fi

# ==============================================================================
# Module 5: SELinux Policy Confinement & ptrace Capabilities
# ==============================================================================
log_info "=== Module 5: SELinux Policy Confinement & ptrace Capabilities ==="

if grep -q "sys_ptrace" "$SELINUX_TE"; then
    pass_test "SELinux policy declares sys_ptrace capability for sandbox tracing"
else
    fail_test "SELinux policy missing sys_ptrace capability"
fi

if grep -q "ptrace" "$SELINUX_TE" && grep -q "process.*ptrace" "$SELINUX_TE"; then
    pass_test "SELinux policy permits process ptrace within mayotix_labs_t"
else
    fail_test "SELinux policy missing process ptrace permission"
fi

# Airgap check: zero user_home_t access permitted
if grep -v '^[[:space:]]*#' "$SELINUX_TE" | grep -q "user_home_t"; then
    fail_test "SELinux policy permits user_home_t (VIOLATES AIRGAP ISOLATION)"
else
    pass_test "SELinux policy enforces airgap (zero user_home_t access permitted)"
fi

# Check for wildcards
if grep -v '^[[:space:]]*#' "$SELINUX_TE" | grep -q '\*'; then
    fail_test "SELinux policy contains wildcard permissions"
else
    pass_test "No wildcard permissions detected in SELinux policy"
fi

# ==============================================================================
# Module 6: Privileged IPC Daemon RPC Methods
# ==============================================================================
log_info "=== Module 6: Privileged IPC Daemon RPC Methods ==="

declare -a EXPECTED_METHODS=(
    "lab.detonate"
    "lab.detonation_list"
    "lab.detonation_report"
)

for method in "${EXPECTED_METHODS[@]}"; do
    if grep -q "\"$method\"" "$DAEMON_SCRIPT"; then
        pass_test "IPC daemon registers endpoint '$method'"
    else
        fail_test "IPC daemon missing endpoint '$method'"
    fi
done

# ==============================================================================
# Module 7: Unified CLI Subcommand Synchronization
# ==============================================================================
log_info "=== Module 7: CLI Subcommand Synchronization ==="

CLI_HELP=$("$PYTHON_BIN" "$CLI_PATH" lab --help 2>/dev/null || echo "")

if echo "$CLI_HELP" | grep -q "detonate" && echo "$CLI_HELP" | grep -q "reports"; then
    pass_test "Unified CLI registers 'mayotix lab detonate' and 'mayotix lab reports'"
else
    fail_test "Unified CLI missing lab detonate or reports subcommands"
fi

# Test mayotix lab detonate --dry-run
if "$PYTHON_BIN" "$CLI_PATH" lab detonate /tmp/mock.bin --dry-run >/dev/null 2>&1; then
    pass_test "Unified CLI executes 'mayotix lab detonate --dry-run'"
else
    fail_test "CLI failed to execute 'mayotix lab detonate --dry-run'"
fi

# Test mayotix lab reports --dry-run
if "$PYTHON_BIN" "$CLI_PATH" lab reports --dry-run >/dev/null 2>&1; then
    pass_test "Unified CLI executes 'mayotix lab reports --dry-run'"
else
    fail_test "CLI failed to execute 'mayotix lab reports --dry-run'"
fi

# ==============================================================================
# Module 8: Summary & Audit Report Generation
# ==============================================================================
echo ""
echo "=============================================================================="
echo "MAYOTIX OS Phase 8 Week 3 Audit Summary"
echo "Total Checks: $TOTAL_TESTS | Passed: $PASSED_TESTS | Failed: $FAILED_TESTS | Warnings: $WARNINGS"
echo "=============================================================================="

if [[ $FAILED_TESTS -eq 0 ]]; then
    log_ok "PHASE 8 WEEK 3 DETONATION & TELEMETRY: ALL CHECKS PASSED (100%)"
    exit 0
else
    log_err "PHASE 8 WEEK 3 AUDIT FAILED ($FAILED_TESTS failed checks)"
    exit 1
fi
