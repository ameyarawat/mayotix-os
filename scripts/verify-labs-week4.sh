#!/usr/bin/env bash
# ==============================================================================
# MAYOTIX OS Phase 8 Week 4: Labs Desktop Studio & Audit Verification Harness
# File: scripts/verify-labs-week4.sh
# Mode: 0755
#
# Comprehensive verification suite validating:
#   1. File presence, architecture structure, and documentation
#   2. XDG desktop application entry specifications and categories
#   3. Privileged IPC daemon RPC endpoints across all Phase 8 subsystems
#   4. Desktop Control Studio GUI headless validation, tabs, and Wayland compatibility
#   5. Phase 8 Comprehensive Security Audit 100/100 compliance execution
#   6. Unified CLI subcommand synchronization across all Phase 8 modules
#   7. Automated summary and compliance telemetry
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
GUI_SCRIPT="${PROJECT_ROOT}/desktop/labs/mayotix-labs-gui.py"
DESKTOP_ENTRY="${PROJECT_ROOT}/desktop/applications/mayotix-labs.desktop"
DAEMON_SCRIPT="${PROJECT_ROOT}/daemon/mayotix-daemon.py"
AUDIT_SCRIPT="${PROJECT_ROOT}/scripts/conduct-security-audit-phase8.sh"
CLI_PATH="${PROJECT_ROOT}/cli/mayotix"
DOC_WEEK4="${PROJECT_ROOT}/docs/PHASE8_WEEK4_DESKTOP_AUDIT.md"
DOC_RELEASE="${PROJECT_ROOT}/docs/PHASE8_RELEASE_NOTES.md"
BUILD_DIR="${PROJECT_ROOT}/build"
REPORT_FILE="${BUILD_DIR}/PHASE8_WEEK4_VERIFICATION_REPORT.txt"

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

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --report-only) REPORT_ONLY=1 ;;
        *) ;;
    esac
    shift
done

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

log_info "Starting MAYOTIX OS Phase 8 Week 4 Labs Desktop & Audit Verification..."
echo ""

# ==============================================================================
# Module 1: File Presence & Directory Structure
# ==============================================================================
log_info "=== Module 1: File Presence & Directory Structure ==="

check_file() {
    local file="$1"
    local desc="$2"
    if [[ -f "$file" ]]; then
        pass_test "$desc exists at '$file'"
    else
        fail_test "$desc missing at '$file'"
    fi
}

check_file "$GUI_SCRIPT" "Labs Desktop GUI script"
check_file "$DESKTOP_ENTRY" "XDG desktop entry"
check_file "$DAEMON_SCRIPT" "Privileged IPC daemon"
check_file "$AUDIT_SCRIPT" "Phase 8 Security Audit harness"
check_file "$DOC_WEEK4" "Phase 8 Week 4 technical documentation"
check_file "$DOC_RELEASE" "Phase 8 Release Notes"

# ==============================================================================
# Module 2: XDG Desktop Entry Configuration
# ==============================================================================
log_info "=== Module 2: XDG Desktop Entry Configuration ==="

if grep -q "Type=Application" "$DESKTOP_ENTRY"; then
    pass_test "Desktop entry declares Type=Application"
else
    fail_test "Desktop entry missing Type=Application"
fi

if grep -q "Categories=.*System.*Security" "$DESKTOP_ENTRY"; then
    pass_test "Desktop entry includes System and Security categories"
else
    fail_test "Desktop entry missing required categories"
fi

if grep -q "Exec=.*mayotix-labs-gui.py" "$DESKTOP_ENTRY"; then
    pass_test "Desktop entry points to mayotix-labs-gui.py"
else
    fail_test "Desktop entry Exec line invalid"
fi

# ==============================================================================
# Module 3: Privileged IPC Daemon Endpoints
# ==============================================================================
log_info "=== Module 3: Privileged IPC Daemon Endpoints ==="

declare -a ALL_PHASE8_RPC_METHODS=(
    "lab.launch"
    "lab.list"
    "lab.destroy"
    "lab.status"
    "lab.network_start"
    "lab.network_stop"
    "lab.network_status"
    "lab.sinkhole_start"
    "lab.sinkhole_stop"
    "lab.sinkhole_status"
    "lab.sinkhole_logs"
    "lab.detonate"
    "lab.detonation_list"
    "lab.detonation_report"
    "incident.triage"
    "incident.report"
)

for method in "${ALL_PHASE8_RPC_METHODS[@]}"; do
    if grep -q "\"$method\"" "$DAEMON_SCRIPT"; then
        pass_test "IPC daemon registers endpoint '$method'"
    else
        fail_test "IPC daemon missing endpoint '$method'"
    fi
done

# ==============================================================================
# Module 4: Desktop Control Studio GUI Headless Validation
# ==============================================================================
log_info "=== Module 4: Desktop Control Studio GUI Headless Validation ==="

# Test syntax compilation
if "$PYTHON_BIN" -m py_compile "$GUI_SCRIPT" >/dev/null 2>&1; then
    pass_test "Labs GUI script passes Python syntax compilation"
else
    fail_test "Labs GUI script syntax error"
fi

# Test headless simulation
GUI_OUT=$("$PYTHON_BIN" "$GUI_SCRIPT" --dry-run --json 2>/dev/null || echo "{}")

if echo "$GUI_OUT" | grep -q "MAYOTIX Labs Control Studio"; then
    pass_test "Labs GUI headless execution returns valid application metadata"
else
    fail_test "Labs GUI headless execution failed"
fi

if echo "$GUI_OUT" | grep -q '"tabs_count": 4'; then
    pass_test "Labs GUI declares all 4 primary studio tabs"
else
    fail_test "Labs GUI missing required tabs"
fi

if echo "$GUI_OUT" | grep -q '"wayland_compatible": true'; then
    pass_test "Labs GUI declares native Wayland display compatibility"
else
    fail_test "Labs GUI missing Wayland compatibility declaration"
fi

# ==============================================================================
# Module 5: Comprehensive Security Audit (100/100 points)
# ==============================================================================
log_info "=== Module 5: Comprehensive Security Audit (100/100 points) ==="

AUDIT_RES=$(bash "$AUDIT_SCRIPT" --dry-run --json 2>/dev/null || echo "{}")
AUDIT_SCORE=$(echo "$AUDIT_RES" | grep '"score":' | head -n 1 | awk -F':' '{print $2}' | tr -d ' ,')

if [[ "$AUDIT_SCORE" -eq 100 ]]; then
    pass_test "Phase 8 Comprehensive Security Audit achieved 100/100 points (PASS)"
else
    fail_test "Phase 8 Comprehensive Security Audit failed ($AUDIT_SCORE / 100 points)"
fi

# ==============================================================================
# Module 6: Unified CLI Subcommand Synchronization
# ==============================================================================
log_info "=== Module 6: Unified CLI Subcommand Synchronization ==="

# Verify lab commands
if "$PYTHON_BIN" "$CLI_PATH" lab status --dry-run >/dev/null 2>&1; then
    pass_test "Unified CLI executes 'mayotix lab status --dry-run'"
else
    fail_test "CLI failed 'mayotix lab status --dry-run'"
fi

if "$PYTHON_BIN" "$CLI_PATH" lab network status --dry-run >/dev/null 2>&1; then
    pass_test "Unified CLI executes 'mayotix lab network status --dry-run'"
else
    fail_test "CLI failed 'mayotix lab network status --dry-run'"
fi

if "$PYTHON_BIN" "$CLI_PATH" lab sinkhole status --dry-run >/dev/null 2>&1; then
    pass_test "Unified CLI executes 'mayotix lab sinkhole status --dry-run'"
else
    fail_test "CLI failed 'mayotix lab sinkhole status --dry-run'"
fi

if "$PYTHON_BIN" "$CLI_PATH" lab detonate --dry-run >/dev/null 2>&1; then
    pass_test "Unified CLI executes 'mayotix lab detonate --dry-run'"
else
    fail_test "CLI failed 'mayotix lab detonate --dry-run'"
fi

if "$PYTHON_BIN" "$CLI_PATH" lab reports --dry-run >/dev/null 2>&1; then
    pass_test "Unified CLI executes 'mayotix lab reports --dry-run'"
else
    fail_test "CLI failed 'mayotix lab reports --dry-run'"
fi

if "$PYTHON_BIN" "$CLI_PATH" incident triage --dry-run >/dev/null 2>&1; then
    pass_test "Unified CLI executes 'mayotix incident triage --dry-run'"
else
    fail_test "CLI failed 'mayotix incident triage --dry-run'"
fi

# ==============================================================================
# Module 7: Summary & Audit Report Generation
# ==============================================================================
echo ""
echo -e "${BOLD}${CYAN}==============================================================================${NC}"
echo -e "${BOLD}${CYAN}MAYOTIX OS Phase 8 Week 4 Audit Summary${NC}"
echo -e "${BOLD}${CYAN}Total Checks: $TOTAL_TESTS | Passed: $PASSED_TESTS | Failed: $FAILED_TESTS | Warnings: $WARNINGS${NC}"
echo -e "${BOLD}${CYAN}==============================================================================${NC}"

mkdir -p "$BUILD_DIR"
{
    echo "=============================================================================="
    echo "MAYOTIX OS Phase 8 Week 4: Desktop Control Studio & Audit Report"
    echo "Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo "Total Checks: $TOTAL_TESTS"
    echo "Passed Checks: $PASSED_TESTS"
    echo "Failed Checks: $FAILED_TESTS"
    echo "Status: $([[ $FAILED_TESTS -eq 0 ]] && echo 'PASSED (100% COMPLIANT)' || echo 'FAILED')"
    echo "=============================================================================="
} > "$REPORT_FILE"

if [[ $FAILED_TESTS -eq 0 ]]; then
    log_success "PHASE 8 WEEK 4 LABS DESKTOP & AUDIT: ALL CHECKS PASSED (100%)"
    exit 0
else
    log_error "PHASE 8 WEEK 4 AUDIT FAILED with $FAILED_TESTS errors."
    exit 1
fi
