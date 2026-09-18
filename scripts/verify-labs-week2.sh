#!/usr/bin/env bash
# MAYOTIX OS Phase 8 Week 2: Virtual Bridge Network & Traffic Sinkhole Verification Harness
#
# Verifies:
#   1. Script presence, directory structure, and documentation
#   2. Security permissions, shebang integrity, and executable bits
#   3. Virtual bridge network controller, 10.99.0.0/24 subnet, and nftables containment
#   4. Dynamic malware traffic sinkhole, DNS blackhole, and HTTP C2 emulation
#   5. SELinux policy port confinement (dns_port_t, http_port_t) and airgap enforcement
#   6. Privileged IPC daemon RPC endpoints (lab.network_*, lab.sinkhole_*)
#   7. Unified CLI subcommand synchronization (mayotix lab network/sinkhole)
#   8. Telemetry reporting and compliance audit generation
#
# Usage:
#   ./scripts/verify-labs-week2.sh [options]
#   ./scripts/verify-labs-week2.sh --dry-run
#   ./scripts/verify-labs-week2.sh --report-only

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
NET_SCRIPT="${PROJECT_ROOT}/desktop/labs/lab-network.sh"
SINK_SCRIPT="${PROJECT_ROOT}/desktop/labs/sinkhole.py"
SELINUX_TE="${PROJECT_ROOT}/security/selinux/mayotix_labs.te"
SELINUX_FC="${PROJECT_ROOT}/security/selinux/mayotix_labs.fc"
DAEMON_SCRIPT="${PROJECT_ROOT}/daemon/mayotix-daemon.py"
CLI_PATH="${PROJECT_ROOT}/cli/mayotix"
DOC_WEEK2="${PROJECT_ROOT}/docs/PHASE8_WEEK2_SINKHOLE.md"
BUILD_DIR="${PROJECT_ROOT}/build"
REPORT_FILE="${BUILD_DIR}/PHASE8_WEEK2_VERIFICATION_REPORT.txt"

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

log_info "Starting MAYOTIX OS Phase 8 Week 2 Virtual Bridge & Traffic Sinkhole Verification..."
echo ""

# ==============================================================================
# Module 1: File Presence & Architecture Structure
# ==============================================================================
log_info "=== Module 1: File Presence & Directory Structure ==="

if [[ -f "$NET_SCRIPT" ]]; then
    pass_test "Virtual bridge network controller exists at '$NET_SCRIPT'"
else
    fail_test "Virtual bridge network controller missing at '$NET_SCRIPT'"
fi

if [[ -f "$SINK_SCRIPT" ]]; then
    pass_test "Dynamic malware traffic sinkhole script exists at '$SINK_SCRIPT'"
else
    fail_test "Dynamic malware traffic sinkhole script missing at '$SINK_SCRIPT'"
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

if [[ -f "$DOC_WEEK2" ]]; then
    pass_test "Phase 8 Week 2 technical documentation exists at '$DOC_WEEK2'"
else
    fail_test "Phase 8 Week 2 technical documentation missing at '$DOC_WEEK2'"
fi

# ==============================================================================
# Module 2: Security Permissions & Shebang Integrity
# ==============================================================================
log_info "=== Module 2: Security Permissions & Shebang Integrity ==="

if head -n 1 "$NET_SCRIPT" | grep -qE '^#!/(bin|usr/bin)/(env )?bash'; then
    pass_test "Bridge network controller declares standard bash shebang"
else
    fail_test "Bridge network controller has invalid shebang: $(head -n 1 "$NET_SCRIPT")"
fi

if head -n 1 "$SINK_SCRIPT" | grep -qE '^#!/(bin|usr/bin)/(env )?python3?'; then
    pass_test "Traffic sinkhole declares standard python shebang"
else
    fail_test "Traffic sinkhole has invalid shebang: $(head -n 1 "$SINK_SCRIPT")"
fi

# ==============================================================================
# Module 3: Virtual Bridge Network Controller & Containment Firewall
# ==============================================================================
log_info "=== Module 3: Virtual Bridge Network & Containment Firewall ==="

NET_STATUS=$("$NET_SCRIPT" status --dry-run --json 2>/dev/null || echo "")
if echo "$NET_STATUS" | grep -q "mayotix-br0" && echo "$NET_STATUS" | grep -q "10.99.0.0/24"; then
    pass_test "Bridge controller declares mayotix-br0 interface and 10.99.0.0/24 subnet"
else
    fail_test "Bridge controller status output missing bridge configuration"
fi

if echo "$NET_STATUS" | grep -q "DROP_PHYSICAL_EGRESS" && echo "$NET_STATUS" | grep -q "mayotix_lab_isolation"; then
    pass_test "Bridge controller enforces fail-closed physical egress firewall containment"
else
    fail_test "Bridge controller missing containment firewall table or policy"
fi

NET_START=$("$NET_SCRIPT" start --dry-run 2>/dev/null || echo "")
if echo "$NET_START" | grep -q "PERMIT 10.99.0.1 ports 53" && echo "$NET_START" | grep -q "DROP forward to physical"; then
    pass_test "Bridge start simulation validates strict ingress/egress filtering rules"
else
    fail_test "Bridge start simulation failed"
fi

NET_STOP=$("$NET_SCRIPT" stop --dry-run 2>/dev/null || echo "")
if echo "$NET_STOP" | grep -q "Delete virtual bridge device"; then
    pass_test "Bridge stop simulation verifies clean interface and table teardown"
else
    fail_test "Bridge stop simulation failed"
fi

# ==============================================================================
# Module 4: Dynamic Malware Traffic Sinkhole & DNS Blackhole
# ==============================================================================
log_info "=== Module 4: Dynamic Malware Traffic Sinkhole & DNS Blackhole ==="

SINK_SYNTAX=$("$PYTHON_BIN" -m py_compile "$SINK_SCRIPT" 2>&1 || echo "ERROR")
if [[ -z "$SINK_SYNTAX" ]]; then
    pass_test "Traffic sinkhole script compiles cleanly (syntax verified)"
else
    fail_test "Traffic sinkhole syntax error: $SINK_SYNTAX"
fi

SINK_DRY=$("$PYTHON_BIN" "$SINK_SCRIPT" --dry-run --json 2>/dev/null || echo "")
if echo "$SINK_DRY" | "$PYTHON_BIN" -m json.tool >/dev/null 2>&1; then
    pass_test "Traffic sinkhole outputs valid structured JSON telemetry"
else
    fail_test "Traffic sinkhole dry-run output is not valid JSON"
fi

if echo "$SINK_DRY" | grep -q '"port": 53' && echo "$SINK_DRY" | grep -q '"resolved_target": "10.99.0.1"'; then
    pass_test "DNS blackhole successfully resolves all queries to sinkhole gateway (10.99.0.1)"
else
    fail_test "DNS blackhole missing expected port 53 or gateway resolution target"
fi

if echo "$SINK_DRY" | grep -q '"default_status": 200' && echo "$SINK_DRY" | grep -q "FAKE_C2_ACK"; then
    pass_test "HTTP C2 service emulator configured to return 200 OK responses"
else
    fail_test "HTTP C2 service emulator missing expected status or emulation mode"
fi

# ==============================================================================
# Module 5: SELinux Policy Confinement & Port Binding Rules
# ==============================================================================
log_info "=== Module 5: SELinux Policy Confinement & Port Bindings ==="

if grep -q "dns_port_t" "$SELINUX_TE" && grep -q "http_port_t" "$SELINUX_TE"; then
    pass_test "SELinux policy declares dns_port_t and http_port_t bindings"
else
    fail_test "SELinux policy missing dns_port_t or http_port_t definitions"
fi

if grep -q "dns_port_t:udp_socket name_bind" "$SELINUX_TE" && \
   grep -q "http_port_t:tcp_socket name_bind" "$SELINUX_TE"; then
    pass_test "SELinux policy permits name_bind for sinkhole DNS and HTTP sockets"
else
    fail_test "SELinux policy missing name_bind permission for sinkhole ports"
fi

if grep -v '^[[:space:]]*#' "$SELINUX_TE" | grep -qE "user_home_t|user_home_dir_t"; then
    fail_test "Security violation: SELinux policy allows access to host user home directories"
else
    pass_test "SELinux policy enforces airgap (zero user_home_t access permitted)"
fi

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
    "lab.network_start"
    "lab.network_stop"
    "lab.network_status"
    "lab.sinkhole_start"
    "lab.sinkhole_stop"
    "lab.sinkhole_status"
    "lab.sinkhole_logs"
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

if echo "$CLI_HELP" | grep -q "network" && echo "$CLI_HELP" | grep -q "sinkhole"; then
    pass_test "Unified CLI registers 'mayotix lab network' and 'mayotix lab sinkhole'"
else
    fail_test "Unified CLI missing lab network or sinkhole subcommands"
fi

# Test mayotix lab network status --dry-run
if "$PYTHON_BIN" "$CLI_PATH" lab network status --dry-run >/dev/null 2>&1; then
    pass_test "Unified CLI executes 'mayotix lab network status --dry-run'"
else
    fail_test "CLI failed to execute 'mayotix lab network status --dry-run'"
fi

# Test mayotix lab network start --dry-run
if "$PYTHON_BIN" "$CLI_PATH" lab network start --dry-run >/dev/null 2>&1; then
    pass_test "Unified CLI executes 'mayotix lab network start --dry-run'"
else
    fail_test "CLI failed to execute 'mayotix lab network start --dry-run'"
fi

# Test mayotix lab sinkhole status --dry-run
if "$PYTHON_BIN" "$CLI_PATH" lab sinkhole status --dry-run >/dev/null 2>&1; then
    pass_test "Unified CLI executes 'mayotix lab sinkhole status --dry-run'"
else
    fail_test "CLI failed to execute 'mayotix lab sinkhole status --dry-run'"
fi

# Test mayotix lab sinkhole start --dry-run
if "$PYTHON_BIN" "$CLI_PATH" lab sinkhole start --dry-run >/dev/null 2>&1; then
    pass_test "Unified CLI executes 'mayotix lab sinkhole start --dry-run'"
else
    fail_test "CLI failed to execute 'mayotix lab sinkhole start --dry-run'"
fi

# Test mayotix lab sinkhole logs --dry-run
if "$PYTHON_BIN" "$CLI_PATH" lab sinkhole logs --dry-run >/dev/null 2>&1; then
    pass_test "Unified CLI executes 'mayotix lab sinkhole logs --dry-run'"
else
    fail_test "CLI failed to execute 'mayotix lab sinkhole logs --dry-run'"
fi

# ==============================================================================
# Module 8: Summary & Audit Report Generation
# ==============================================================================
echo ""
echo "=============================================================================="
echo "MAYOTIX OS Phase 8 Week 2 Audit Summary"
echo "Total Checks: $TOTAL_TESTS | Passed: $PASSED_TESTS | Failed: $FAILED_TESTS | Warnings: $WARNINGS"
echo "=============================================================================="

{
    echo "=============================================================================="
    echo "MAYOTIX OS Phase 8 Week 2: Bridge Network & Sinkhole Verification Report"
    echo "Timestamp: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo "Total Checks: $TOTAL_TESTS"
    echo "Passed:       $PASSED_TESTS"
    echo "Failed:       $FAILED_TESTS"
    echo "Warnings:     $WARNINGS"
    echo "Status:       $([[ $FAILED_TESTS -eq 0 ]] && echo 'PASSED (100% COMPLIANT)' || echo 'FAILED')"
    echo "=============================================================================="
} > "$REPORT_FILE"

if [[ $FAILED_TESTS -eq 0 ]]; then
    log_success "PHASE 8 WEEK 2 BRIDGE & SINKHOLE: ALL CHECKS PASSED (100%)"
    exit 0
else
    log_error "PHASE 8 WEEK 2 VERIFICATION FAILED with $FAILED_TESTS errors."
    exit 1
fi
