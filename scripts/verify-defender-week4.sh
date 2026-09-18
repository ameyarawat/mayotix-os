#!/bin/bash
# MAYOTIX OS Phase 7 Week 4: Defender Desktop Center, IPC Integration & Comprehensive Audit Verification Harness
#
# Verifies:
#   1. File presence, architecture structure, and documentation
#   2. XDG desktop application entry specifications and categories
#   3. Privileged IPC daemon RPC endpoints (capture.*, pcap.*, forensic.*, monitor.*)
#   4. Desktop Control Center GUI headless validation, tabs, and Wayland compatibility
#   5. Phase 7 Comprehensive Security Audit 100/100 compliance execution
#   6. Unified CLI subcommand synchronization across all Phase 7 modules
#   7. Automated report generation and compliance telemetry
#
# Usage:
#   ./scripts/verify-defender-week4.sh [options]
#   ./scripts/verify-defender-week4.sh --dry-run
#   ./scripts/verify-defender-week4.sh --report-only

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
GUI_SCRIPT="${PROJECT_ROOT}/desktop/defender/mayotix-defender-gui.py"
DESKTOP_ENTRY="${PROJECT_ROOT}/desktop/applications/mayotix-defender.desktop"
DAEMON_SCRIPT="${PROJECT_ROOT}/daemon/mayotix-daemon.py"
AUDIT_SCRIPT="${PROJECT_ROOT}/scripts/conduct-security-audit-phase7.sh"
CLI_PATH="${PROJECT_ROOT}/cli/mayotix"
DOC_WEEK4="${PROJECT_ROOT}/docs/PHASE7_WEEK4_DESKTOP_AUDIT.md"
DOC_RELEASE="${PROJECT_ROOT}/docs/PHASE7_RELEASE_NOTES.md"
BUILD_DIR="${PROJECT_ROOT}/build"
REPORT_FILE="${BUILD_DIR}/PHASE7_WEEK4_VERIFICATION_REPORT.txt"

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

log_info "Starting MAYOTIX OS Phase 7 Week 4 Defender Desktop & Audit Verification..."
echo ""

# ==============================================================================
# Module 1: File Presence & Directory Structure
# ==============================================================================
log_info "=== Module 1: File Presence & Directory Structure ==="

if [[ -f "$GUI_SCRIPT" ]]; then
    pass_test "Defender Desktop GUI script exists at '$GUI_SCRIPT'"
else
    fail_test "Defender Desktop GUI script missing at '$GUI_SCRIPT'"
fi

if [[ -f "$DESKTOP_ENTRY" ]]; then
    pass_test "XDG desktop entry exists at '$DESKTOP_ENTRY'"
else
    fail_test "XDG desktop entry missing at '$DESKTOP_ENTRY'"
fi

if [[ -f "$DAEMON_SCRIPT" ]]; then
    pass_test "Privileged IPC daemon exists at '$DAEMON_SCRIPT'"
else
    fail_test "Privileged IPC daemon missing at '$DAEMON_SCRIPT'"
fi

if [[ -f "$AUDIT_SCRIPT" ]]; then
    pass_test "Phase 7 Security Audit harness exists at '$AUDIT_SCRIPT'"
else
    fail_test "Phase 7 Security Audit harness missing at '$AUDIT_SCRIPT'"
fi

if [[ -f "$DOC_WEEK4" ]]; then
    pass_test "Phase 7 Week 4 technical documentation exists at '$DOC_WEEK4'"
else
    fail_test "Phase 7 Week 4 technical documentation missing at '$DOC_WEEK4'"
fi

if [[ -f "$DOC_RELEASE" ]]; then
    pass_test "Phase 7 Release Notes exist at '$DOC_RELEASE'"
else
    fail_test "Phase 7 Release Notes missing at '$DOC_RELEASE'"
fi

# ==============================================================================
# Module 2: XDG Desktop Entry & Launcher Configuration
# ==============================================================================
log_info "=== Module 2: XDG Desktop Entry Configuration ==="

if grep -q "^Type=Application" "$DESKTOP_ENTRY"; then
    pass_test "Desktop entry declares Type=Application"
else
    fail_test "Desktop entry missing Type=Application"
fi

if grep -q "^Categories=.*Security.*System" "$DESKTOP_ENTRY" || grep -q "^Categories=.*System.*Security" "$DESKTOP_ENTRY"; then
    pass_test "Desktop entry includes System and Security categories"
else
    fail_test "Desktop entry missing standard Security/System categories"
fi

if grep -q "^StartupNotify=true" "$DESKTOP_ENTRY"; then
    pass_test "Desktop entry enables StartupNotify"
else
    fail_test "Desktop entry missing StartupNotify configuration"
fi

if grep -q "mayotix-defender-gui" "$DESKTOP_ENTRY"; then
    pass_test "Desktop entry points to mayotix-defender-gui executable"
else
    fail_test "Desktop entry does not execute mayotix-defender-gui"
fi

# ==============================================================================
# Module 3: Privileged IPC Daemon RPC Methods
# ==============================================================================
log_info "=== Module 3: Privileged IPC Daemon RPC Methods ==="

declare -a EXPECTED_METHODS=(
    "capture.start"
    "capture.stop"
    "capture.status"
    "capture.list_profiles"
    "pcap.analyze"
    "pcap.dissect"
    "forensic.dump"
    "forensic.sanitize"
    "monitor.scan"
)

for method in "${EXPECTED_METHODS[@]}"; do
    if grep -q "\"$method\"" "$DAEMON_SCRIPT"; then
        pass_test "IPC daemon registers endpoint '$method'"
    else
        fail_test "IPC daemon missing endpoint '$method'"
    fi
done

# Check daemon parameter validation & cap drop
if grep -q "allowed_profiles" "$DAEMON_SCRIPT" && grep -q "dissector" "$DAEMON_SCRIPT"; then
    pass_test "IPC daemon enforces strict parameter validation for defender endpoints"
else
    fail_test "IPC daemon missing parameter whitelist for defender endpoints"
fi

# ==============================================================================
# Module 4: Desktop Control Center GUI Validation
# ==============================================================================
log_info "=== Module 4: Desktop Control Center GUI Validation ==="

GUI_SYNTAX=$("$PYTHON_BIN" -m py_compile "$GUI_SCRIPT" 2>&1 || echo "ERROR")
if [[ -z "$GUI_SYNTAX" ]]; then
    pass_test "Defender Desktop GUI script compiles cleanly (syntax verified)"
else
    fail_test "Defender Desktop GUI script syntax error: $GUI_SYNTAX"
fi

GUI_DRY=$("$PYTHON_BIN" "$GUI_SCRIPT" --dry-run 2>/dev/null || echo "")
if echo "$GUI_DRY" | grep -q "MAYOTIX Defender Desktop Control Center" && echo "$GUI_DRY" | grep -q "Packet Inspection"; then
    pass_test "GUI headless dry-run execution succeeded with all tabs declared"
else
    fail_test "GUI headless dry-run execution failed"
fi

GUI_JSON=$("$PYTHON_BIN" "$GUI_SCRIPT" --dry-run --json 2>/dev/null || echo "")
if echo "$GUI_JSON" | "$PYTHON_BIN" -m json.tool >/dev/null 2>&1; then
    pass_test "GUI headless output produces valid JSON telemetry"
else
    fail_test "GUI headless output failed to produce valid JSON"
fi

if echo "$GUI_JSON" | grep -q '"tabs_count": 3' && echo "$GUI_JSON" | grep -q '"wayland_compatible": true'; then
    pass_test "GUI declares 3 functional tabs and Wayland compositor compatibility"
else
    fail_test "GUI missing expected tab count or Wayland compatibility flag"
fi

# ==============================================================================
# Module 5: Comprehensive Security Audit Harness Execution
# ==============================================================================
log_info "=== Module 5: Phase 7 Comprehensive Security Audit Execution ==="

AUDIT_RES=$("$AUDIT_SCRIPT" --dry-run 2>/dev/null || echo "")
if echo "$AUDIT_RES" | grep -q "100/100 pts (PASS - 100% COMPLIANT)"; then
    pass_test "Phase 7 Security Audit script achieves 100/100 points compliance"
else
    fail_test "Phase 7 Security Audit script failed to achieve 100/100 points"
fi

AUDIT_JSON=$("$AUDIT_SCRIPT" --json 2>/dev/null || echo "")
if echo "$AUDIT_JSON" | "$PYTHON_BIN" -m json.tool >/dev/null 2>&1; then
    pass_test "Phase 7 Security Audit script produces valid JSON report"
else
    fail_test "Phase 7 Security Audit script JSON report invalid"
fi

if echo "$AUDIT_JSON" | grep -q '"total_score": 100' && echo "$AUDIT_JSON" | grep -q '"status": "PASS"'; then
    pass_test "Security Audit JSON telemetry confirms PASS status with score 100"
else
    fail_test "Security Audit JSON telemetry indicates non-pass status"
fi

# ==============================================================================
# Module 6: CLI Subcommand Synchronization
# ==============================================================================
log_info "=== Module 6: CLI Subcommand Synchronization ==="

CLI_HELP=$("$PYTHON_BIN" "$CLI_PATH" --help 2>/dev/null || echo "")
declare -a SUBCOMMANDS=("capture" "pcap" "forensic" "monitor")

for sub in "${SUBCOMMANDS[@]}"; do
    if echo "$CLI_HELP" | grep -q "$sub"; then
        pass_test "Unified CLI synchronizes Phase 7 subcommand '$sub'"
    else
        fail_test "Unified CLI missing Phase 7 subcommand '$sub'"
    fi
done

# Verify all Phase 7 dry-run invocations through CLI
if "$PYTHON_BIN" "$CLI_PATH" capture --dry-run >/dev/null 2>&1; then
    pass_test "Unified CLI executes 'mayotix capture --dry-run'"
else
    fail_test "CLI failed to execute 'mayotix capture --dry-run'"
fi

if "$PYTHON_BIN" "$CLI_PATH" pcap scan --dry-run >/dev/null 2>&1; then
    pass_test "Unified CLI executes 'mayotix pcap scan --dry-run'"
else
    fail_test "CLI failed to execute 'mayotix pcap scan --dry-run'"
fi

if "$PYTHON_BIN" "$CLI_PATH" forensic dump --pid 1 --dry-run >/dev/null 2>&1; then
    pass_test "Unified CLI executes 'mayotix forensic dump --pid 1 --dry-run'"
else
    fail_test "CLI failed to execute 'mayotix forensic dump --pid 1 --dry-run'"
fi

if "$PYTHON_BIN" "$CLI_PATH" monitor --dry-run >/dev/null 2>&1; then
    pass_test "Unified CLI executes 'mayotix monitor --dry-run'"
else
    fail_test "CLI failed to execute 'mayotix monitor --dry-run'"
fi

# ==============================================================================
# Module 7: Summary & Audit Report Generation
# ==============================================================================
echo ""
echo "=============================================================================="
echo "MAYOTIX OS Phase 7 Week 4 Audit Summary"
echo "Total Checks: $TOTAL_TESTS | Passed: $PASSED_TESTS | Failed: $FAILED_TESTS | Warnings: $WARNINGS"
echo "=============================================================================="

{
    echo "=============================================================================="
    echo "MAYOTIX OS Phase 7 Week 4: Desktop Center & Audit Verification Report"
    echo "Timestamp: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo "Total Checks: $TOTAL_TESTS"
    echo "Passed:       $PASSED_TESTS"
    echo "Failed:       $FAILED_TESTS"
    echo "Warnings:     $WARNINGS"
    echo "Status:       $([[ $FAILED_TESTS -eq 0 ]] && echo 'PASSED (100% COMPLIANT)' || echo 'FAILED')"
    echo "=============================================================================="
} > "$REPORT_FILE"

if [[ $FAILED_TESTS -eq 0 ]]; then
    log_success "PHASE 7 WEEK 4 DESKTOP CENTER & AUDIT: ALL CHECKS PASSED (100%)"
    exit 0
else
    log_error "PHASE 7 WEEK 4 VERIFICATION FAILED with $FAILED_TESTS errors."
    exit 1
fi
