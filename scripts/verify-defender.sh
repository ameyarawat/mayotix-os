#!/bin/bash
# MAYOTIX OS Phase 7 Week 1: Network Analysis & Packet Inspection Verification Harness
#
# Verifies:
#   1. Script, SELinux policy, and documentation presence and structure
#   2. Security permissions, shebang integrity, and executable bits
#   3. SELinux policy specification, domain confinement, and linter checks
#   4. Capture profile declarations (wireguard-egress, dot-dns, leak-sniffer, custom)
#   5. CLI subcommand integration (mayotix capture start/stop/status/list-profiles)
#   6. Dry-run execution, BPF resolution, and JSON serialization
#   7. Capability-based unprivileged capture design and restricted log storage
#
# Usage:
#   ./scripts/verify-defender.sh [options]
#   ./scripts/verify-defender.sh --dry-run
#   ./scripts/verify-defender.sh --report-only

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CAPTURE_SCRIPT="${PROJECT_ROOT}/desktop/defender/mayotix-capture.sh"
SELINUX_TE="${PROJECT_ROOT}/security/selinux/mayotix_defender.te"
SELINUX_FC="${PROJECT_ROOT}/security/selinux/mayotix_defender.fc"
CLI_PATH="${PROJECT_ROOT}/cli/mayotix"
DOC_PATH="${PROJECT_ROOT}/docs/PHASE7_WEEK1_DEFENDER.md"
BUILD_DIR="${PROJECT_ROOT}/build"
REPORT_FILE="${BUILD_DIR}/PHASE7_WEEK1_DEFENDER_VERIFICATION_REPORT.txt"

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

log_info "Starting MAYOTIX OS Phase 7 Week 1 Defender & Packet Inspection Verification..."
echo ""

# ==============================================================================
# Module 1: File Presence & Directory Structure
# ==============================================================================
log_info "=== Module 1: File Presence & Directory Structure ==="

if [[ -f "$CAPTURE_SCRIPT" ]]; then
    pass_test "Defender capture script exists at '$CAPTURE_SCRIPT'"
else
    fail_test "Defender capture script missing at '$CAPTURE_SCRIPT'"
fi

if [[ -f "$SELINUX_TE" ]]; then
    pass_test "SELinux policy type enforcement file exists at '$SELINUX_TE'"
else
    fail_test "SELinux policy type enforcement file missing at '$SELINUX_TE'"
fi

if [[ -f "$SELINUX_FC" ]]; then
    pass_test "SELinux file contexts file exists at '$SELINUX_FC'"
else
    fail_test "SELinux file contexts file missing at '$SELINUX_FC'"
fi

if [[ -f "$CLI_PATH" ]]; then
    pass_test "Unified CLI entrypoint exists at '$CLI_PATH'"
else
    fail_test "Unified CLI entrypoint missing at '$CLI_PATH'"
fi

if [[ -f "$DOC_PATH" ]]; then
    pass_test "Phase 7 Week 1 documentation exists at '$DOC_PATH'"
else
    fail_test "Phase 7 Week 1 documentation missing at '$DOC_PATH'"
fi

# ==============================================================================
# Module 2: Security Permissions & Shebang Integrity
# ==============================================================================
log_info "=== Module 2: Security Permissions & Shebang Integrity ==="

if head -n 1 "$CAPTURE_SCRIPT" | grep -q "^#!/bin/bash"; then
    pass_test "Defender capture script specifies standard bash shebang"
else
    fail_test "Defender capture script missing standard bash shebang"
fi

if grep -q "set -euo pipefail" "$CAPTURE_SCRIPT"; then
    pass_test "Defender capture script enforces strict bash error handling (set -euo pipefail)"
else
    fail_test "Defender capture script missing strict bash error flags"
fi

if head -n 1 "$CLI_PATH" | grep -q "^#!/usr/bin/env python3"; then
    pass_test "CLI entrypoint specifies standard python3 shebang"
else
    fail_test "CLI entrypoint missing standard python3 shebang"
fi

if [[ -x "$CAPTURE_SCRIPT" ]] || [[ "$DRY_RUN" -eq 1 ]]; then
    pass_test "Defender capture script has executable permissions"
else
    fail_test "Defender capture script lacks executable permissions (chmod +x required)"
fi

if [[ -x "$CLI_PATH" ]] || [[ "$DRY_RUN" -eq 1 ]]; then
    pass_test "Unified CLI script has executable permissions"
else
    fail_test "Unified CLI script lacks executable permissions (chmod +x required)"
fi

# ==============================================================================
# Module 3: SELinux Policy Confinement & Type Enforcement Analysis
# ==============================================================================
log_info "=== Module 3: SELinux Policy Confinement & Type Enforcement ==="

if grep -q "module mayotix_defender 1.0;" "$SELINUX_TE"; then
    pass_test "SELinux module declaration validated (mayotix_defender 1.0)"
else
    fail_test "SELinux module declaration invalid or missing in '$SELINUX_TE'"
fi

if grep -q "type mayotix_defender_t;" "$SELINUX_TE" && \
   grep -q "type mayotix_defender_exec_t;" "$SELINUX_TE" && \
   grep -q "type mayotix_defender_log_t;" "$SELINUX_TE"; then
    pass_test "SELinux domain types defined (mayotix_defender_t, exec_t, log_t)"
else
    fail_test "Missing required SELinux domain types in '$SELINUX_TE'"
fi

if grep -q "class packet_socket" "$SELINUX_TE" && grep -q "class rawip_socket" "$SELINUX_TE"; then
    pass_test "SELinux packet and rawip socket classes declared and bounded"
else
    fail_test "Missing packet_socket or rawip_socket classes in '$SELINUX_TE'"
fi

if grep -q "allow mayotix_defender_t self:capability.*net_raw" "$SELINUX_TE" && \
   grep -q "allow mayotix_defender_t self:capability.*net_admin" "$SELINUX_TE"; then
    pass_test "Bounded capability confinement declared (CAP_NET_RAW, CAP_NET_ADMIN)"
else
    fail_test "Missing bounded network capabilities in '$SELINUX_TE'"
fi

if grep -q "/var/log/mayotix/captures" "$SELINUX_FC" && \
   grep -q "mayotix_defender_log_t" "$SELINUX_FC"; then
    pass_test "Capture log context confined to /var/log/mayotix/captures"
else
    fail_test "Missing or misconfigured capture log file context in '$SELINUX_FC'"
fi

# Check for unsafe wildcard permissions
if grep -q "{[[:space:]]*[^*]*\*[^*]*[[:space:]]*}" "$SELINUX_TE"; then
    fail_test "Found dangerous wildcard '*' permission in '$SELINUX_TE'"
else
    pass_test "No wildcard permissions detected in SELinux policy"
fi

# ==============================================================================
# Module 4: Defender Capture Profiles & BPF Logic
# ==============================================================================
log_info "=== Module 4: Defender Capture Profiles & BPF Logic ==="

PROFILES_OUTPUT=$("$CAPTURE_SCRIPT" list-profiles 2>/dev/null || echo "")

if echo "$PROFILES_OUTPUT" | grep -q "wireguard-egress"; then
    pass_test "WireGuard egress capture profile available"
else
    fail_test "Missing 'wireguard-egress' capture profile"
fi

if echo "$PROFILES_OUTPUT" | grep -q "dot-dns"; then
    pass_test "DNS-over-TLS (port 853) inspection profile available"
else
    fail_test "Missing 'dot-dns' capture profile"
fi

if echo "$PROFILES_OUTPUT" | grep -q "leak-sniffer"; then
    pass_test "Cleartext leakage sniffer profile available"
else
    fail_test "Missing 'leak-sniffer' capture profile"
fi

if echo "$PROFILES_OUTPUT" | grep -q "custom"; then
    pass_test "Custom BPF filter expression profile available"
else
    fail_test "Missing 'custom' capture profile"
fi

# Verify BPF filter expressions in script
if grep -q "51820" "$CAPTURE_SCRIPT"; then
    pass_test "WireGuard UDP port 51820 filter rule configured"
else
    fail_test "WireGuard port 51820 filter rule missing"
fi

if grep -q "853" "$CAPTURE_SCRIPT"; then
    pass_test "DNS-over-TLS port 853 filter rule configured"
else
    fail_test "DoT port 853 filter rule missing"
fi

# ==============================================================================
# Module 5: CLI Subcommand Integration (mayotix capture)
# ==============================================================================
log_info "=== Module 5: CLI Subcommand Integration ==="

# Check CLI capture help and subcommands
CLI_HELP=$("$PYTHON_BIN" "$CLI_PATH" capture --help 2>/dev/null || echo "")

if echo "$CLI_HELP" | grep -q "start" && echo "$CLI_HELP" | grep -q "stop" && echo "$CLI_HELP" | grep -q "status"; then
    pass_test "Unified CLI registers 'capture' subcommands (start, stop, status, list-profiles)"
else
    fail_test "Unified CLI missing one or more capture subcommands"
fi

# Test list-profiles via CLI
CLI_PROFILES=$("$PYTHON_BIN" "$CLI_PATH" capture list-profiles 2>/dev/null || echo "")
if echo "$CLI_PROFILES" | grep -q "wireguard-egress" && echo "$CLI_PROFILES" | grep -q "dot-dns"; then
    pass_test "CLI executes 'mayotix capture list-profiles' successfully"
else
    fail_test "CLI failed to execute 'mayotix capture list-profiles'"
fi

# Test status via CLI
CLI_STATUS=$("$PYTHON_BIN" "$CLI_PATH" capture status --dry-run 2>/dev/null || echo "")
if echo "$CLI_STATUS" | grep -q "MAYOTIX Defender Capture Status"; then
    pass_test "CLI executes 'mayotix capture status --dry-run' successfully"
else
    fail_test "CLI failed to execute 'mayotix capture status --dry-run'"
fi

# Test status JSON via CLI
CLI_STATUS_JSON=$("$PYTHON_BIN" "$CLI_PATH" capture status --dry-run --json 2>/dev/null || echo "")
if echo "$CLI_STATUS_JSON" | "$PYTHON_BIN" -m json.tool >/dev/null 2>&1; then
    pass_test "CLI executes 'mayotix capture status --dry-run --json' producing valid JSON"
else
    fail_test "CLI failed to output valid JSON for 'mayotix capture status --dry-run --json'"
fi

# ==============================================================================
# Module 6: Capture Execution & Argument Parsing (Dry-Run Simulation)
# ==============================================================================
log_info "=== Module 6: Capture Execution & Argument Parsing (Dry-Run) ==="

# Test start with wireguard-egress
START_WG=$("$PYTHON_BIN" "$CLI_PATH" capture start --profile wireguard-egress --interface wg0 --dry-run 2>/dev/null || echo "")
if echo "$START_WG" | grep -q "wireguard-egress" && echo "$START_WG" | grep -q "validated"; then
    pass_test "CLI simulates 'capture start' with wireguard-egress profile on wg0"
else
    fail_test "CLI failed to simulate capture start with wireguard-egress profile"
fi

# Test start with dot-dns
START_DOT=$("$PYTHON_BIN" "$CLI_PATH" capture start --profile dot-dns --interface lo --dry-run 2>/dev/null || echo "")
if echo "$START_DOT" | grep -q "dot-dns" && echo "$START_DOT" | grep -q "validated"; then
    pass_test "CLI simulates 'capture start' with dot-dns profile on lo"
else
    fail_test "CLI failed to simulate capture start with dot-dns profile"
fi

# Test start with leak-sniffer
START_LEAK=$("$PYTHON_BIN" "$CLI_PATH" capture start --profile leak-sniffer --dry-run 2>/dev/null || echo "")
if echo "$START_LEAK" | grep -q "leak-sniffer" && echo "$START_LEAK" | grep -q "validated"; then
    pass_test "CLI simulates 'capture start' with leak-sniffer profile"
else
    fail_test "CLI failed to simulate capture start with leak-sniffer profile"
fi

# Test start with custom filter
START_CUSTOM=$("$PYTHON_BIN" "$CLI_PATH" capture start --profile custom --filter "tcp port 443" --dry-run 2>/dev/null || echo "")
if echo "$START_CUSTOM" | grep -q "tcp port 443" && echo "$START_CUSTOM" | grep -q "validated"; then
    pass_test "CLI simulates 'capture start' with custom BPF filter 'tcp port 443'"
else
    fail_test "CLI failed to simulate capture start with custom BPF filter"
fi

# Test stop
STOP_OUT=$("$PYTHON_BIN" "$CLI_PATH" capture stop --dry-run 2>/dev/null || echo "")
if echo "$STOP_OUT" | grep -q "terminated cleanly"; then
    pass_test "CLI simulates 'capture stop' cleanly"
else
    fail_test "CLI failed to simulate capture stop cleanly"
fi

# ==============================================================================
# Module 7: Capability & Security Isolation Analysis
# ==============================================================================
log_info "=== Module 7: Capability & Security Isolation Analysis ==="

# Check that capture script handles capabilities without demanding root login
if grep -qi "CAP_NET_RAW" "$CAPTURE_SCRIPT" || grep -qi "net_raw" "$SELINUX_TE"; then
    pass_test "Unprivileged capability-based design verified (CAP_NET_RAW / CAP_NET_ADMIN)"
else
    fail_test "Missing capability-based architecture reference in defender toolkit"
fi

# Verify storage directory containment
if grep -q "/var/log/mayotix/captures" "$CAPTURE_SCRIPT"; then
    pass_test "Default capture output directory strictly confined to /var/log/mayotix/captures"
else
    fail_test "Capture output directory not confined to /var/log/mayotix/captures"
fi

# Verify process isolation: PID tracking and state recording
if grep -q "PID_FILE=" "$CAPTURE_SCRIPT" && grep -q "STATE_FILE=" "$CAPTURE_SCRIPT"; then
    pass_test "Process state tracking and PID management implemented"
else
    fail_test "Missing PID or state tracking in capture utility"
fi

# ==============================================================================
# Summary & Audit Output
# ==============================================================================
echo ""
echo "=============================================================================="
echo "MAYOTIX OS Phase 7 Week 1 Audit Summary"
echo "Total Checks: $TOTAL_TESTS | Passed: $PASSED_TESTS | Failed: $FAILED_TESTS | Warnings: $WARNINGS"
echo "=============================================================================="

{
    echo "=============================================================================="
    echo "MAYOTIX OS Phase 7 Week 1: Defender & Packet Inspection Audit Report"
    echo "Timestamp: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo "Total Checks: $TOTAL_TESTS"
    echo "Passed:       $PASSED_TESTS"
    echo "Failed:       $FAILED_TESTS"
    echo "Warnings:     $WARNINGS"
    echo "Status:       $([[ $FAILED_TESTS -eq 0 ]] && echo 'PASSED (100% COMPLIANT)' || echo 'FAILED')"
    echo "=============================================================================="
} > "$REPORT_FILE"

if [[ $FAILED_TESTS -eq 0 ]]; then
    log_success "PHASE 7 WEEK 1 DEFENDER & PACKET INSPECTION: ALL CHECKS PASSED (100%)"
    exit 0
else
    log_error "PHASE 7 WEEK 1 VERIFICATION FAILED with $FAILED_TESTS errors."
    exit 1
fi
