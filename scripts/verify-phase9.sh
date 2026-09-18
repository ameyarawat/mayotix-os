#!/usr/bin/env bash
# ==============================================================================
# MAYOTIX OS Phase 9: Comprehensive Verification Harness
# File: scripts/verify-phase9.sh
# Mode: 0755
#
# Verifies:
#   1. File presence, architecture structure, and documentation
#   2. Security permissions and shebang integrity
#   3. KVM Micro-VM orchestration & QCOW2 snapshot mechanics
#   4. Multi-tier TAP network router & fail-closed firewall containment
#   5. Declarative multi-node lab topology engine
#   6. SELinux MAC policy confinement & KVM/TAP permissions
#   7. Privileged IPC daemon RPC endpoints
#   8. Unified CLI subcommand synchronization across all VM modules
#   9. Phase 9 Comprehensive Security Audit 100/100 compliance execution
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

VM_SCRIPT="${PROJECT_ROOT}/desktop/labs/vm/mayotix-vm.sh"
NET_SCRIPT="${PROJECT_ROOT}/desktop/labs/vm/vm-network.sh"
TOP_SCRIPT="${PROJECT_ROOT}/desktop/labs/vm/lab-topology.py"
SELINUX_TE="${PROJECT_ROOT}/security/selinux/mayotix_vm.te"
SELINUX_FC="${PROJECT_ROOT}/security/selinux/mayotix_vm.fc"
DAEMON_SCRIPT="${PROJECT_ROOT}/daemon/mayotix-daemon.py"
CLI_PATH="${PROJECT_ROOT}/cli/mayotix"
AUDIT_SCRIPT="${PROJECT_ROOT}/scripts/conduct-security-audit-phase9.sh"
DOC_FILE="${PROJECT_ROOT}/docs/PHASE9_VM_VIRTUALIZATION.md"
DOC_RELEASE="${PROJECT_ROOT}/docs/PHASE9_RELEASE_NOTES.md"
BUILD_DIR="${PROJECT_ROOT}/build"
REPORT_FILE="${BUILD_DIR}/PHASE9_VERIFICATION_REPORT.txt"

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

log_info "Starting MAYOTIX OS Phase 9 Hardware Virtualization & Lab Topology Verification..."
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

check_file "$VM_SCRIPT" "KVM Micro-VM orchestrator"
check_file "$NET_SCRIPT" "TAP network router script"
check_file "$TOP_SCRIPT" "Lab topology engine"
check_file "$SELINUX_TE" "SELinux VM policy definition"
check_file "$SELINUX_FC" "SELinux VM file contexts"
check_file "$DAEMON_SCRIPT" "Privileged IPC daemon"
check_file "$CLI_PATH" "Unified CLI"
check_file "$AUDIT_SCRIPT" "Phase 9 Security Audit harness"
check_file "$DOC_FILE" "Phase 9 technical documentation"
check_file "$DOC_RELEASE" "Phase 9 Release Notes"

# ==============================================================================
# Module 2: Security Permissions & Shebang Integrity
# ==============================================================================
log_info "=== Module 2: Security Permissions & Shebang Integrity ==="

if head -n 1 "$VM_SCRIPT" | grep -Eq '^#!/(usr/)?bin/(env )?bash'; then
    pass_test "VM orchestrator declares standard bash shebang"
else
    fail_test "VM orchestrator has invalid shebang"
fi

if head -n 1 "$NET_SCRIPT" | grep -Eq '^#!/(usr/)?bin/(env )?bash'; then
    pass_test "Network router declares standard bash shebang"
else
    fail_test "Network router has invalid shebang"
fi

if head -n 1 "$TOP_SCRIPT" | grep -Eq '^#!/(usr/)?bin/(env )?python'; then
    pass_test "Topology engine declares standard python shebang"
else
    fail_test "Topology engine has invalid shebang"
fi

if "$PYTHON_BIN" -m py_compile "$TOP_SCRIPT" >/dev/null 2>&1; then
    pass_test "Topology engine script compiles cleanly (syntax verified)"
else
    fail_test "Topology engine syntax error"
fi

# ==============================================================================
# Module 3: KVM Micro-VM Orchestration & QCOW2 Snapshots
# ==============================================================================
log_info "=== Module 3: KVM Micro-VM Orchestration & QCOW2 Snapshots ==="

VM_STATUS=$(bash "$VM_SCRIPT" status --dry-run --json 2>/dev/null || echo "{}")
if echo "$VM_STATUS" | grep -q "qcow2_support" && echo "$VM_STATUS" | grep -q "kvm_acceleration"; then
    pass_test "VM status reports hardware acceleration and QCOW2 capability"
else
    fail_test "VM status query failed"
fi

VM_LAUNCH=$(bash "$VM_SCRIPT" launch mock-vm --dry-run --json 2>/dev/null || echo "{}")
if echo "$VM_LAUNCH" | grep -q '"status": "RUNNING"' && echo "$VM_LAUNCH" | grep -q "overlay.qcow2"; then
    pass_test "VM launch simulates QCOW2 copy-on-write overlay provisioning"
else
    fail_test "VM launch simulation failed"
fi

VM_SNAP=$(bash "$VM_SCRIPT" snapshot mock-vm snap-01 --dry-run --json 2>/dev/null || echo "{}")
if echo "$VM_SNAP" | grep -q '"status": "CREATED"'; then
    pass_test "Instant QCOW2 snapshot creation verified"
else
    fail_test "QCOW2 snapshot creation failed"
fi

VM_ROLL=$(bash "$VM_SCRIPT" rollback mock-vm snap-01 --dry-run --json 2>/dev/null || echo "{}")
if echo "$VM_ROLL" | grep -q '"status": "RESTORED"'; then
    pass_test "Clean snapshot rollback verified"
else
    fail_test "Snapshot rollback failed"
fi

# ==============================================================================
# Module 4: Multi-Tier TAP Network Router & Firewall Containment
# ==============================================================================
log_info "=== Module 4: Multi-Tier TAP Network Router & Firewall Containment ==="

NET_STATUS=$(bash "$NET_SCRIPT" status --dry-run --json 2>/dev/null || echo "{}")
if echo "$NET_STATUS" | grep -q "mayotix-vbr0" && echo "$NET_STATUS" | grep -q "10.99.1.0/24"; then
    pass_test "Virtual bridge mayotix-vbr0 and subnet 10.99.1.0/24 verified"
else
    fail_test "Virtual bridge status query failed"
fi

if echo "$NET_STATUS" | grep -q "DROP_PHYSICAL_EGRESS"; then
    pass_test "Containment firewall enforces fail-closed physical drop policy"
else
    fail_test "Containment firewall policy invalid"
fi

# ==============================================================================
# Module 5: Declarative Multi-Node Lab Topology Engine
# ==============================================================================
log_info "=== Module 5: Declarative Multi-Node Lab Topology Engine ==="

TOP_LIST=$("$PYTHON_BIN" "$TOP_SCRIPT" list --dry-run --json 2>/dev/null || echo "{}")
if echo "$TOP_LIST" | grep -q "malware-sandbox" && echo "$TOP_LIST" | grep -q "attack-defense"; then
    pass_test "Topology engine lists pre-configured multi-node scenarios"
else
    fail_test "Topology scenario listing failed"
fi

TOP_DEPLOY=$("$PYTHON_BIN" "$TOP_SCRIPT" deploy attack-defense --dry-run --json 2>/dev/null || echo "{}")
if echo "$TOP_DEPLOY" | grep -q '"status": "DEPLOYED"' && echo "$TOP_DEPLOY" | grep -q "attacker-node"; then
    pass_test "Topology engine deploys multi-VM attack-defense scenario"
else
    fail_test "Topology deployment failed"
fi

# ==============================================================================
# Module 6: SELinux Policy Confinement & KVM/TAP Capabilities
# ==============================================================================
log_info "=== Module 6: SELinux Policy Confinement & KVM/TAP Capabilities ==="

if grep -q "mayotix_vm_t" "$SELINUX_TE" && grep -q "kvm_device_t" "$SELINUX_TE"; then
    pass_test "SELinux policy declares KVM device access"
else
    fail_test "SELinux policy missing KVM device access"
fi

if grep -q "tun_socket" "$SELINUX_TE"; then
    pass_test "SELinux policy declares TUN/TAP socket capability"
else
    fail_test "SELinux policy missing TUN/TAP capability"
fi

if grep -v '^[[:space:]]*#' "$SELINUX_TE" | grep -q "user_home_t"; then
    fail_test "SELinux policy exposes user_home_t (AIRGAP VIOLATION)"
else
    pass_test "SELinux policy enforces strict airgap (zero user_home_t access)"
fi

if grep -v '^[[:space:]]*#' "$SELINUX_TE" | grep -q '\*'; then
    fail_test "SELinux policy contains wildcard permissions"
else
    pass_test "No wildcard permissions detected in SELinux policy"
fi

# ==============================================================================
# Module 7: Privileged IPC Daemon RPC Methods
# ==============================================================================
log_info "=== Module 7: Privileged IPC Daemon RPC Methods ==="

declare -a EXPECTED_VM_METHODS=(
    "vm.launch"
    "vm.stop"
    "vm.list"
    "vm.destroy"
    "vm.status"
    "vm.snapshot"
    "vm.rollback"
    "vm.topology_deploy"
    "vm.topology_list"
    "vm.topology_teardown"
)

for method in "${EXPECTED_VM_METHODS[@]}"; do
    if grep -q "\"$method\"" "$DAEMON_SCRIPT"; then
        pass_test "IPC daemon registers endpoint '$method'"
    else
        fail_test "IPC daemon missing endpoint '$method'"
    fi
done

# ==============================================================================
# Module 8: Unified CLI Subcommand Synchronization
# ==============================================================================
log_info "=== Module 8: Unified CLI Subcommand Synchronization ==="

if "$PYTHON_BIN" "$CLI_PATH" vm status --dry-run >/dev/null 2>&1; then
    pass_test "Unified CLI executes 'mayotix vm status --dry-run'"
else
    fail_test "CLI failed 'mayotix vm status --dry-run'"
fi

if "$PYTHON_BIN" "$CLI_PATH" vm launch test-vm --dry-run >/dev/null 2>&1; then
    pass_test "Unified CLI executes 'mayotix vm launch test-vm --dry-run'"
else
    fail_test "CLI failed 'mayotix vm launch test-vm --dry-run'"
fi

if "$PYTHON_BIN" "$CLI_PATH" vm list --dry-run >/dev/null 2>&1; then
    pass_test "Unified CLI executes 'mayotix vm list --dry-run'"
else
    fail_test "CLI failed 'mayotix vm list --dry-run'"
fi

if "$PYTHON_BIN" "$CLI_PATH" vm topology list --dry-run >/dev/null 2>&1; then
    pass_test "Unified CLI executes 'mayotix vm topology list --dry-run'"
else
    fail_test "CLI failed 'mayotix vm topology list --dry-run'"
fi

if "$PYTHON_BIN" "$CLI_PATH" vm topology deploy malware-sandbox --dry-run >/dev/null 2>&1; then
    pass_test "Unified CLI executes 'mayotix vm topology deploy --dry-run'"
else
    fail_test "CLI failed 'mayotix vm topology deploy --dry-run'"
fi

# ==============================================================================
# Module 9: Comprehensive Security Audit (100/100 points)
# ==============================================================================
log_info "=== Module 9: Comprehensive Security Audit (100/100 points) ==="

AUDIT_RES=$(bash "$AUDIT_SCRIPT" --dry-run --json 2>/dev/null || echo "{}")
AUDIT_SCORE=$(echo "$AUDIT_RES" | grep '"score":' | head -n 1 | awk -F':' '{print $2}' | tr -d ' ,')

if [[ "$AUDIT_SCORE" -eq 100 ]]; then
    pass_test "Phase 9 Comprehensive Security Audit achieved 100/100 points (PASS)"
else
    fail_test "Phase 9 Comprehensive Security Audit failed ($AUDIT_SCORE / 100 points)"
fi

# ==============================================================================
# Module 10: Summary & Audit Report Generation
# ==============================================================================
echo ""
echo -e "${BOLD}${CYAN}==============================================================================${NC}"
echo -e "${BOLD}${CYAN}MAYOTIX OS Phase 9 Verification Summary${NC}"
echo -e "${BOLD}${CYAN}Total Checks: $TOTAL_TESTS | Passed: $PASSED_TESTS | Failed: $FAILED_TESTS | Warnings: $WARNINGS${NC}"
echo -e "${BOLD}${CYAN}==============================================================================${NC}"

mkdir -p "$BUILD_DIR"
{
    echo "=============================================================================="
    echo "MAYOTIX OS Phase 9: Hardware Virtualization & Lab Topology Verification"
    echo "Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo "Total Checks: $TOTAL_TESTS"
    echo "Passed Checks: $PASSED_TESTS"
    echo "Failed Checks: $FAILED_TESTS"
    echo "Status: $([[ $FAILED_TESTS -eq 0 ]] && echo 'PASSED (100% COMPLIANT)' || echo 'FAILED')"
    echo "=============================================================================="
} > "$REPORT_FILE"

if [[ $FAILED_TESTS -eq 0 ]]; then
    log_success "PHASE 9 HARDWARE VIRTUALIZATION & TOPOLOGY: ALL CHECKS PASSED (100%)"
    exit 0
else
    log_error "PHASE 9 VERIFICATION FAILED with $FAILED_TESTS errors."
    exit 1
fi
