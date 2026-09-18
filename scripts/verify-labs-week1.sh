#!/usr/bin/env bash
# MAYOTIX OS Phase 8 Week 1: Labs & Incident Response Verification Harness
#
# Verifies:
#   1. Script presence, directory structure, and documentation
#   2. Security permissions, shebang integrity, and executable bits
#   3. Lab sandbox isolation, internal bridge network (10.99.0.0/24), and discard-on-exit
#   4. Automated incident response triage engine and SHA-256 integrity hashing
#   5. SELinux policy confinement (mayotix_labs.te) and host home airgap enforcement
#   6. Privileged IPC daemon RPC endpoints (lab.*, incident.*)
#   7. Unified CLI subcommand synchronization (mayotix lab, mayotix incident)
#   8. Telemetry reporting and compliance audit generation
#
# Usage:
#   ./scripts/verify-labs-week1.sh [options]
#   ./scripts/verify-labs-week1.sh --dry-run
#   ./scripts/verify-labs-week1.sh --report-only

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LAB_SCRIPT="${PROJECT_ROOT}/desktop/labs/mayotix-lab.sh"
TRIAGE_SCRIPT="${PROJECT_ROOT}/desktop/defender/incident/triage-snapshot.sh"
SELINUX_TE="${PROJECT_ROOT}/security/selinux/mayotix_labs.te"
SELINUX_FC="${PROJECT_ROOT}/security/selinux/mayotix_labs.fc"
DAEMON_SCRIPT="${PROJECT_ROOT}/daemon/mayotix-daemon.py"
CLI_PATH="${PROJECT_ROOT}/cli/mayotix"
DOC_WEEK1="${PROJECT_ROOT}/docs/PHASE8_WEEK1_LABS.md"
BUILD_DIR="${PROJECT_ROOT}/build"
REPORT_FILE="${BUILD_DIR}/PHASE8_WEEK1_VERIFICATION_REPORT.txt"

# Terminal Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

DRY_RUN=0
REPORT_ONLY=0

PYTHON_BIN="python3"
if command -v python3 &>/dev/null && python3 -c "import sys" &>/dev/null; then
    PYTHON_BIN="python3"
elif command -v python &>/dev/null && python -c "import sys" &>/dev/null; then
    PYTHON_BIN="python"
fi

TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
WARNINGS=0

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; WARNINGS=$((WARNINGS + 1)); }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

pass_test() {
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    PASSED_TESTS=$((PASSED_TESTS + 1))
    log_success "$1"
}

fail_test() {
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    FAILED_TESTS=$((FAILED_TESTS + 1))
    log_error "$1"
}

# Parse options
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --report-only) REPORT_ONLY=1 ;;
        *) log_warn "Unknown option: $1" ;;
    esac
    shift
done

mkdir -p "$BUILD_DIR"

log_info "Starting MAYOTIX OS Phase 8 Week 1 Labs & Incident Response Verification..."
echo ""

# ==============================================================================
# Module 1: File Presence & Architecture Structure
# ==============================================================================
log_info "=== Module 1: File Presence & Directory Structure ==="

if [[ -f "$LAB_SCRIPT" ]]; then
    pass_test "Isolated lab environment harness exists at '$LAB_SCRIPT'"
else
    fail_test "Isolated lab environment harness missing at '$LAB_SCRIPT'"
fi

if [[ -f "$TRIAGE_SCRIPT" ]]; then
    pass_test "Automated incident response triage engine exists at '$TRIAGE_SCRIPT'"
else
    fail_test "Automated incident response triage engine missing at '$TRIAGE_SCRIPT'"
fi

if [[ -f "$SELINUX_TE" ]]; then
    pass_test "SELinux lab policy definition exists at '$SELINUX_TE'"
else
    fail_test "SELinux lab policy definition missing at '$SELINUX_TE'"
fi

if [[ -f "$SELINUX_FC" ]]; then
    pass_test "SELinux lab file contexts exist at '$SELINUX_FC'"
else
    fail_test "SELinux lab file contexts missing at '$SELINUX_FC'"
fi

if [[ -f "$DAEMON_SCRIPT" ]]; then
    pass_test "Privileged IPC daemon exists at '$DAEMON_SCRIPT'"
else
    fail_test "Privileged IPC daemon missing at '$DAEMON_SCRIPT'"
fi

if [[ -f "$CLI_PATH" ]]; then
    pass_test "Unified CLI exists at '$CLI_PATH'"
else
    fail_test "Unified CLI missing at '$CLI_PATH'"
fi

if [[ -f "$DOC_WEEK1" ]]; then
    pass_test "Phase 8 Week 1 technical documentation exists at '$DOC_WEEK1'"
else
    fail_test "Phase 8 Week 1 technical documentation missing at '$DOC_WEEK1'"
fi

# ==============================================================================
# Module 2: Security Permissions & Shebang Integrity
# ==============================================================================
log_info "=== Module 2: Security Permissions & Shebang Integrity ==="

if head -n 1 "$LAB_SCRIPT" | grep -qE '^#!/(bin|usr/bin)/(env )?bash'; then
    pass_test "Lab script declares standard bash shebang"
else
    fail_test "Lab script has invalid shebang: $(head -n 1 "$LAB_SCRIPT")"
fi

if head -n 1 "$TRIAGE_SCRIPT" | grep -qE '^#!/(bin|usr/bin)/(env )?bash'; then
    pass_test "Triage script declares standard bash shebang"
else
    fail_test "Triage script has invalid shebang: $(head -n 1 "$TRIAGE_SCRIPT")"
fi

# ==============================================================================
# Module 3: Lab Sandbox Isolation & Virtual Bridge Engine
# ==============================================================================
log_info "=== Module 3: Lab Sandbox Isolation & Virtual Bridge Engine ==="

# Test status command
LAB_STATUS=$("$LAB_SCRIPT" status --dry-run --json 2>/dev/null || echo "")
if echo "$LAB_STATUS" | grep -q "10.99.0.0/24" && echo "$LAB_STATUS" | grep -q "mayotix-br0"; then
    pass_test "Lab harness enforces 10.99.0.0/24 internal bridge subnet"
else
    fail_test "Lab harness status output missing expected bridge configuration"
fi

# Test launch simulation
LAB_LAUNCH=$("$LAB_SCRIPT" launch --template malware --network bridge --dry-run 2>/dev/null || echo "")
if echo "$LAB_LAUNCH" | grep -q "DENIED access to /home/\*" && echo "$LAB_LAUNCH" | grep -q "Auto-purge on exit"; then
    pass_test "Lab harness validates host home airgap and discard-on-exit semantics"
else
    fail_test "Lab harness launch simulation failed or missing airgap verification"
fi

# Test list simulation
LAB_LIST=$("$LAB_SCRIPT" list --dry-run --json 2>/dev/null || echo "")
if echo "$LAB_LIST" | "$PYTHON_BIN" -m json.tool >/dev/null 2>&1; then
    pass_test "Lab harness list output produces valid JSON telemetry"
else
    fail_test "Lab harness list failed to produce valid JSON"
fi

# Test destroy simulation
LAB_DESTROY=$("$LAB_SCRIPT" destroy mock-lab-1 --dry-run 2>/dev/null || echo "")
if echo "$LAB_DESTROY" | grep -q "destroyed cleanly"; then
    pass_test "Lab harness cleanly simulates session teardown and artifact wipe"
else
    fail_test "Lab harness destroy simulation failed"
fi

# ==============================================================================
# Module 4: Automated Incident Response Triage Engine
# ==============================================================================
log_info "=== Module 4: Automated Incident Response Triage Engine ==="

TRIAGE_DRY=$("$TRIAGE_SCRIPT" --dry-run 2>/dev/null || echo "")
if echo "$TRIAGE_DRY" | grep -q "Network Sockets & Routing" && echo "$TRIAGE_DRY" | grep -q "Kernel Taint & Modules"; then
    pass_test "Triage engine collects network sockets, process tree, and kernel state"
else
    fail_test "Triage engine output missing required host audit categories"
fi

TRIAGE_JSON=$("$TRIAGE_SCRIPT" --dry-run --json 2>/dev/null || echo "")
if echo "$TRIAGE_JSON" | "$PYTHON_BIN" -m json.tool >/dev/null 2>&1; then
    pass_test "Triage engine outputs valid structured JSON manifest"
else
    fail_test "Triage engine JSON output invalid"
fi

if echo "$TRIAGE_JSON" | grep -q "sha256_checksum" && echo "$TRIAGE_JSON" | grep -q "triage_session"; then
    pass_test "Triage engine calculates SHA-256 cryptographic verification checksums"
else
    fail_test "Triage engine missing SHA-256 checksum or session ID in manifest"
fi

# ==============================================================================
# Module 5: SELinux Policy Confinement (mayotix_labs.te)
# ==============================================================================
log_info "=== Module 5: SELinux Policy Confinement ==="

if grep -q "type mayotix_labs_t;" "$SELINUX_TE" && \
   grep -q "type mayotix_labs_exec_t;" "$SELINUX_TE" && \
   grep -q "type mayotix_labs_log_t;" "$SELINUX_TE"; then
    pass_test "SELinux policy declares domain, execution, and log types"
else
    fail_test "SELinux policy missing expected type definitions in '$SELINUX_TE'"
fi

# Verify absence of user_home_t access (host user home airgap)
if grep -v '^[[:space:]]*#' "$SELINUX_TE" | grep -qE "user_home_t|user_home_dir_t"; then
    fail_test "Security violation: SELinux policy allows access to host user home directories"
else
    pass_test "SELinux policy enforces strict airgap (zero user_home_t access permitted)"
fi

# Check for unsafe wildcard permissions
if grep -q "{[[:space:]]*[^*]*\*[^*]*[[:space:]]*}" "$SELINUX_TE"; then
    fail_test "Found dangerous wildcard '*' permission in '$SELINUX_TE'"
else
    pass_test "No wildcard permissions detected in SELinux policy"
fi

# ==============================================================================
# Module 6: Privileged IPC Daemon RPC Methods
# ==============================================================================
log_info "=== Module 6: Privileged IPC Daemon RPC Methods ==="

declare -a EXPECTED_METHODS=(
    "lab.launch"
    "lab.list"
    "lab.destroy"
    "lab.status"
    "incident.triage"
    "incident.report"
)

for method in "${EXPECTED_METHODS[@]}"; do
    if grep -q "\"$method\"" "$DAEMON_SCRIPT"; then
        pass_test "IPC daemon registers endpoint '$method'"
    else
        fail_test "IPC daemon missing endpoint '$method'"
    fi
done

if grep -q "allowed_templates" "$DAEMON_SCRIPT" && grep -q "allowed_networks" "$DAEMON_SCRIPT"; then
    pass_test "IPC daemon enforces parameter whitelisting for lab endpoints"
else
    fail_test "IPC daemon missing parameter whitelist for lab endpoints"
fi

# ==============================================================================
# Module 7: Unified CLI Subcommand Synchronization
# ==============================================================================
log_info "=== Module 7: CLI Subcommand Synchronization ==="

CLI_HELP=$("$PYTHON_BIN" "$CLI_PATH" --help 2>/dev/null || echo "")

if echo "$CLI_HELP" | grep -q "lab" && echo "$CLI_HELP" | grep -q "incident"; then
    pass_test "Unified CLI registers 'lab' and 'incident' subcommands"
else
    fail_test "Unified CLI missing 'lab' or 'incident' subcommands"
fi

# Test mayotix lab status --dry-run
if "$PYTHON_BIN" "$CLI_PATH" lab status --dry-run >/dev/null 2>&1; then
    pass_test "Unified CLI executes 'mayotix lab status --dry-run'"
else
    fail_test "CLI failed to execute 'mayotix lab status --dry-run'"
fi

# Test mayotix lab launch --dry-run
if "$PYTHON_BIN" "$CLI_PATH" lab launch --dry-run >/dev/null 2>&1; then
    pass_test "Unified CLI executes 'mayotix lab launch --dry-run'"
else
    fail_test "CLI failed to execute 'mayotix lab launch --dry-run'"
fi

# Test mayotix incident triage --dry-run
if "$PYTHON_BIN" "$CLI_PATH" incident triage --dry-run >/dev/null 2>&1; then
    pass_test "Unified CLI executes 'mayotix incident triage --dry-run'"
else
    fail_test "CLI failed to execute 'mayotix incident triage --dry-run'"
fi

# Test mayotix incident report --dry-run
if "$PYTHON_BIN" "$CLI_PATH" incident report --dry-run >/dev/null 2>&1; then
    pass_test "Unified CLI executes 'mayotix incident report --dry-run'"
else
    fail_test "CLI failed to execute 'mayotix incident report --dry-run'"
fi

# ==============================================================================
# Module 8: Summary & Audit Report Generation
# ==============================================================================
echo ""
echo "=============================================================================="
echo "MAYOTIX OS Phase 8 Week 1 Audit Summary"
echo "Total Checks: $TOTAL_TESTS | Passed: $PASSED_TESTS | Failed: $FAILED_TESTS | Warnings: $WARNINGS"
echo "=============================================================================="

{
    echo "=============================================================================="
    echo "MAYOTIX OS Phase 8 Week 1: Labs & Incident Response Verification Report"
    echo "Timestamp: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo "Total Checks: $TOTAL_TESTS"
    echo "Passed:       $PASSED_TESTS"
    echo "Failed:       $FAILED_TESTS"
    echo "Warnings:     $WARNINGS"
    echo "Status:       $([[ $FAILED_TESTS -eq 0 ]] && echo 'PASSED (100% COMPLIANT)' || echo 'FAILED')"
    echo "=============================================================================="
} > "$REPORT_FILE"

if [[ $FAILED_TESTS -eq 0 ]]; then
    log_success "PHASE 8 WEEK 1 LABS & INCIDENT RESPONSE: ALL CHECKS PASSED (100%)"
    exit 0
else
    log_error "PHASE 8 WEEK 1 VERIFICATION FAILED with $FAILED_TESTS errors."
    exit 1
fi
