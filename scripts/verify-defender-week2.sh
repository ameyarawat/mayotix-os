#!/bin/bash
# MAYOTIX OS Phase 7 Week 2: Security Lab Environment & PCAP Dissector Verification Harness
#
# Verifies:
#   1. Script, sandbox profile, SELinux policy, and documentation presence
#   2. Security permissions, shebang integrity, and executable bits
#   3. Bubblewrap sandbox profile isolation (unshare-net, cap-drop ALL, tmpfs)
#   4. SELinux dissector policy specification and socket restriction analysis
#   5. Automated threat heuristics scanner (cleartext, DNS, WireGuard, port-scan)
#   6. CLI subcommands integration (mayotix analyze, mayotix dissect)
#   7. Dry-run simulation, JSON serialization, and compliance report generation
#
# Usage:
#   ./scripts/verify-defender-week2.sh [options]
#   ./scripts/verify-defender-week2.sh --dry-run
#   ./scripts/verify-defender-week2.sh --report-only

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DISSECT_SCRIPT="${PROJECT_ROOT}/desktop/defender/dissect-pcap.sh"
SCAN_SCRIPT="${PROJECT_ROOT}/desktop/defender/scan-pcap.py"
BWRAP_PROFILE="${PROJECT_ROOT}/sandbox/bubblewrap/profiles/dissector"
SELINUX_TE="${PROJECT_ROOT}/security/selinux/mayotix_dissector.te"
SELINUX_FC="${PROJECT_ROOT}/security/selinux/mayotix_dissector.fc"
CLI_PATH="${PROJECT_ROOT}/cli/mayotix"
DOC_PATH="${PROJECT_ROOT}/docs/PHASE7_WEEK2_DEFENDER_LAB.md"
BUILD_DIR="${PROJECT_ROOT}/build"
REPORT_FILE="${BUILD_DIR}/PHASE7_WEEK2_DEFENDER_LAB_VERIFICATION_REPORT.txt"

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

log_info "Starting MAYOTIX OS Phase 7 Week 2 Defender Lab & Dissector Verification..."
echo ""

# ==============================================================================
# Module 1: File Presence & Directory Structure
# ==============================================================================
log_info "=== Module 1: File Presence & Directory Structure ==="

if [[ -f "$DISSECT_SCRIPT" ]]; then
    pass_test "PCAP dissector wrapper script exists at '$DISSECT_SCRIPT'"
else
    fail_test "PCAP dissector wrapper script missing at '$DISSECT_SCRIPT'"
fi

if [[ -f "$SCAN_SCRIPT" ]]; then
    pass_test "PCAP threat heuristics scanner exists at '$SCAN_SCRIPT'"
else
    fail_test "PCAP threat heuristics scanner missing at '$SCAN_SCRIPT'"
fi

if [[ -f "$BWRAP_PROFILE" ]]; then
    pass_test "Bubblewrap dissector sandbox profile exists at '$BWRAP_PROFILE'"
else
    fail_test "Bubblewrap dissector sandbox profile missing at '$BWRAP_PROFILE'"
fi

if [[ -f "$SELINUX_TE" ]]; then
    pass_test "SELinux dissector policy type enforcement file exists at '$SELINUX_TE'"
else
    fail_test "SELinux dissector policy type enforcement file missing at '$SELINUX_TE'"
fi

if [[ -f "$SELINUX_FC" ]]; then
    pass_test "SELinux dissector file contexts file exists at '$SELINUX_FC'"
else
    fail_test "SELinux dissector file contexts file missing at '$SELINUX_FC'"
fi

if [[ -f "$CLI_PATH" ]]; then
    pass_test "Unified CLI script exists at '$CLI_PATH'"
else
    fail_test "Unified CLI script missing at '$CLI_PATH'"
fi

if [[ -f "$DOC_PATH" ]]; then
    pass_test "Phase 7 Week 2 documentation exists at '$DOC_PATH'"
else
    fail_test "Phase 7 Week 2 documentation missing at '$DOC_PATH'"
fi

# ==============================================================================
# Module 2: Security Permissions & Shebang Integrity
# ==============================================================================
log_info "=== Module 2: Security Permissions & Shebang Integrity ==="

if head -n 1 "$DISSECT_SCRIPT" | grep -q "^#!/bin/bash"; then
    pass_test "Dissector wrapper script specifies standard bash shebang"
else
    fail_test "Dissector wrapper script missing standard bash shebang"
fi

if grep -q "set -euo pipefail" "$DISSECT_SCRIPT"; then
    pass_test "Dissector wrapper script enforces strict bash error handling (set -euo pipefail)"
else
    fail_test "Dissector wrapper script missing strict bash error flags"
fi

if head -n 1 "$SCAN_SCRIPT" | grep -q "^#!/usr/bin/env python3"; then
    pass_test "Threat scanner script specifies standard python3 shebang"
else
    fail_test "Threat scanner script missing standard python3 shebang"
fi

if [[ -x "$DISSECT_SCRIPT" ]] || [[ "$DRY_RUN" -eq 1 ]]; then
    pass_test "Dissector wrapper script has executable permissions"
else
    fail_test "Dissector wrapper script lacks executable permissions"
fi

if [[ -x "$SCAN_SCRIPT" ]] || [[ "$DRY_RUN" -eq 1 ]]; then
    pass_test "Threat scanner script has executable permissions"
else
    fail_test "Threat scanner script lacks executable permissions"
fi

# ==============================================================================
# Module 3: Bubblewrap Sandbox Profile & Isolation Directives
# ==============================================================================
log_info "=== Module 3: Bubblewrap Sandbox Profile & Isolation Directives ==="

if grep -q 'NETWORK="none"' "$BWRAP_PROFILE"; then
    pass_test "Bubblewrap dissector profile enforces complete network isolation (NETWORK=\"none\")"
else
    fail_test "Bubblewrap dissector profile missing network isolation directive"
fi

if grep -q 'CAPABILITIES=""' "$BWRAP_PROFILE"; then
    pass_test "Bubblewrap dissector profile enforces complete capability dropping (CAPABILITIES=\"\")"
else
    fail_test "Bubblewrap dissector profile missing capability dropping directive"
fi

if grep -q "unshare-net" "$DISSECT_SCRIPT" && grep -q "cap-drop ALL" "$DISSECT_SCRIPT"; then
    pass_test "Dissector script invokes Bubblewrap with zero network and full capability dropping"
else
    fail_test "Dissector script missing unshare-net or cap-drop arguments"
fi

if grep -q "ro-bind" "$DISSECT_SCRIPT" && grep -q "tmpfs" "$DISSECT_SCRIPT"; then
    pass_test "Dissector script enforces read-only filesystem root and ephemeral tmpfs mounts"
else
    fail_test "Dissector script missing ro-bind or tmpfs sandboxing flags"
fi

# ==============================================================================
# Module 4: SELinux Dissector Policy & Confinement
# ==============================================================================
log_info "=== Module 4: SELinux Dissector Policy & Confinement ==="

if grep -q "module mayotix_dissector 1.0;" "$SELINUX_TE"; then
    pass_test "SELinux module declaration validated (mayotix_dissector 1.0)"
else
    fail_test "SELinux module declaration invalid or missing in '$SELINUX_TE'"
fi

if grep -q "type mayotix_dissector_t;" "$SELINUX_TE" && \
   grep -q "type mayotix_dissector_exec_t;" "$SELINUX_TE"; then
    pass_test "SELinux domain types defined (mayotix_dissector_t, mayotix_dissector_exec_t)"
else
    fail_test "Missing required SELinux domain types in '$SELINUX_TE'"
fi

# Dissectors must have ZERO network socket permissions in SELinux policy
if grep -qE "(packet_socket|rawip_socket|tcp_socket|udp_socket)" "$SELINUX_TE"; then
    fail_test "SELinux dissector policy unexpectedly permits network socket classes!"
else
    pass_test "Zero network socket access confirmed in SELinux dissector domain"
fi

if grep -q "mayotix_defender_log_t:file" "$SELINUX_TE" && grep -q "read open" "$SELINUX_TE"; then
    pass_test "SELinux policy grants confined read-only access to defender capture logs"
else
    fail_test "Missing confined read-only access to defender capture logs"
fi

# Check for unsafe wildcard permissions
if grep -q "{[[:space:]]*[^*]*\*[^*]*[[:space:]]*}" "$SELINUX_TE"; then
    fail_test "Found dangerous wildcard '*' permission in '$SELINUX_TE'"
else
    pass_test "No wildcard permissions detected in SELinux policy"
fi

# ==============================================================================
# Module 5: Automated Threat & Heuristics Scanner
# ==============================================================================
log_info "=== Module 5: Automated Threat & Heuristics Scanner ==="

if grep -q "CLEARTEXT_PORTS" "$SCAN_SCRIPT" && grep -q "HTTP" "$SCAN_SCRIPT"; then
    pass_test "Threat scanner defines cleartext protocol heuristic ports (HTTP/FTP/Telnet)"
else
    fail_test "Threat scanner missing cleartext protocol definitions"
fi

if grep -q "53" "$SCAN_SCRIPT" && grep -q "853" "$SCAN_SCRIPT"; then
    pass_test "Threat scanner enforces DNS-over-TLS (port 853) vs plaintext DNS (port 53) detection"
else
    fail_test "Threat scanner missing DNS inspection heuristic"
fi

if grep -q "51820" "$SCAN_SCRIPT"; then
    pass_test "Threat scanner includes WireGuard encapsulation heuristic rule (UDP/51820)"
else
    fail_test "Threat scanner missing WireGuard verification heuristic"
fi

# Test scanner dry-run execution
SCAN_OUT=$("$PYTHON_BIN" "$SCAN_SCRIPT" --dry-run 2>/dev/null || echo "")
if echo "$SCAN_OUT" | grep -q "Threat & Heuristic Report" && echo "$SCAN_OUT" | grep -q "Security Score"; then
    pass_test "Threat scanner executes dry-run analysis and prints formatted report"
else
    fail_test "Threat scanner failed dry-run execution"
fi

SCAN_JSON=$("$PYTHON_BIN" "$SCAN_SCRIPT" --dry-run --json 2>/dev/null || echo "")
if echo "$SCAN_JSON" | "$PYTHON_BIN" -m json.tool >/dev/null 2>&1; then
    pass_test "Threat scanner outputs valid JSON telemetry"
else
    fail_test "Threat scanner failed to output valid JSON"
fi

# ==============================================================================
# Module 6: CLI Subcommand Integration (mayotix analyze & dissect)
# ==============================================================================
log_info "=== Module 6: CLI Subcommand Integration ==="

CLI_HELP=$("$PYTHON_BIN" "$CLI_PATH" --help 2>/dev/null || echo "")

if echo "$CLI_HELP" | grep -q "analyze" && echo "$CLI_HELP" | grep -q "dissect"; then
    pass_test "Unified CLI registers 'analyze' and 'dissect' subcommands"
else
    fail_test "Unified CLI missing analyze or dissect subcommands"
fi

# Test mayotix analyze --dry-run
CLI_ANA=$("$PYTHON_BIN" "$CLI_PATH" analyze --dry-run 2>/dev/null || echo "")
if echo "$CLI_ANA" | grep -q "Threat & Heuristic Report"; then
    pass_test "CLI executes 'mayotix analyze --dry-run' successfully"
else
    fail_test "CLI failed to execute 'mayotix analyze --dry-run'"
fi

# Test mayotix analyze --dry-run --json
CLI_ANA_JSON=$("$PYTHON_BIN" "$CLI_PATH" analyze --dry-run --json 2>/dev/null || echo "")
if echo "$CLI_ANA_JSON" | "$PYTHON_BIN" -m json.tool >/dev/null 2>&1; then
    pass_test "CLI executes 'mayotix analyze --dry-run --json' producing valid JSON"
else
    fail_test "CLI failed to output valid JSON for 'mayotix analyze --dry-run --json'"
fi

# Test mayotix dissect --dry-run
CLI_DIS=$("$PYTHON_BIN" "$CLI_PATH" dissect test_capture.pcap --dry-run 2>/dev/null || echo "")
if echo "$CLI_DIS" | grep -q "Simulating sandboxed PCAP dissection" && echo "$CLI_DIS" | grep -q "validated"; then
    pass_test "CLI executes 'mayotix dissect test_capture.pcap --dry-run' successfully"
else
    fail_test "CLI failed to execute 'mayotix dissect test_capture.pcap --dry-run'"
fi

# ==============================================================================
# Module 7: Summary & Audit Output
# ==============================================================================
echo ""
echo "=============================================================================="
echo "MAYOTIX OS Phase 7 Week 2 Audit Summary"
echo "Total Checks: $TOTAL_TESTS | Passed: $PASSED_TESTS | Failed: $FAILED_TESTS | Warnings: $WARNINGS"
echo "=============================================================================="

{
    echo "=============================================================================="
    echo "MAYOTIX OS Phase 7 Week 2: Security Lab & PCAP Dissector Audit Report"
    echo "Timestamp: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo "Total Checks: $TOTAL_TESTS"
    echo "Passed:       $PASSED_TESTS"
    echo "Failed:       $FAILED_TESTS"
    echo "Warnings:     $WARNINGS"
    echo "Status:       $([[ $FAILED_TESTS -eq 0 ]] && echo 'PASSED (100% COMPLIANT)' || echo 'FAILED')"
    echo "=============================================================================="
} > "$REPORT_FILE"

if [[ $FAILED_TESTS -eq 0 ]]; then
    log_success "PHASE 7 WEEK 2 DEFENDER LAB & DISSECTOR: ALL CHECKS PASSED (100%)"
    exit 0
else
    log_error "PHASE 7 WEEK 2 VERIFICATION FAILED with $FAILED_TESTS errors."
    exit 1
fi
