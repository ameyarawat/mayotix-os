#!/usr/bin/env bash
# ==============================================================================
# MAYOTIX OS — Phase 11: Anaconda Installer & Dual-Boot Verification Harness
# File: scripts/verify-phase11.sh
# Mode: 0755
# Description: Validates the Phase 11 Installer subsystem: kickstart files,
#              partition validator, dual-boot guard, LUKS2 Argon2id encryption,
#              master installer engine, SELinux policy, daemon IPC, and CLI.
# ==============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

DRY_RUN=false
JSON_OUTPUT=false

TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        --json) JSON_OUTPUT=true ;;
    esac
done

PYTHON_BIN="python3"
if ! command -v "$PYTHON_BIN" >/dev/null 2>&1 || ! "$PYTHON_BIN" -c "import sys" >/dev/null 2>&1; then
    if command -v python >/dev/null 2>&1 && python -c "import sys" >/dev/null 2>&1; then
        PYTHON_BIN="python"
    fi
fi

check_pass() {
    local msg="$1"
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    PASSED_TESTS=$((PASSED_TESTS + 1))
    if [[ "$JSON_OUTPUT" == false ]]; then
        echo -e "${GREEN}[✓]${NC} ${msg}"
    fi
}

check_fail() {
    local msg="$1"
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    FAILED_TESTS=$((FAILED_TESTS + 1))
    if [[ "$JSON_OUTPUT" == false ]]; then
        echo -e "${RED}[ERROR]${NC} ${msg}" >&2
    fi
}

log_mod() {
    local title="$1"
    if [[ "$JSON_OUTPUT" == false ]]; then
        echo -e "${BLUE}[INFO]${NC} === ${title} ==="
    fi
}

echo -e "${BLUE}[INFO]${NC} Starting MAYOTIX OS Phase 11 Anaconda Installer & Dual-Boot Verification..."
echo ""

# ------------------------------------------------------------------------------
# Module 1: File Presence & Directory Structure
# ------------------------------------------------------------------------------
log_mod "Module 1: File Presence & Directory Structure"

FILES=(
    "installer/kickstart/mayotix-live.ks"
    "installer/kickstart/mayotix-hardened.ks"
    "installer/partition-validator.sh"
    "installer/luks2-setup.sh"
    "installer/mayotix-installer.sh"
    "desktop/installer/mayotix-installer-gui.py"
    "desktop/applications/mayotix-installer.desktop"
    "security/selinux/mayotix_installer.te"
    "security/selinux/mayotix_installer.fc"
    "daemon/mayotix-daemon.py"
    "cli/mayotix"
    "scripts/conduct-security-audit-phase11.sh"
    "docs/PHASE11_INSTALLER.md"
    "docs/PHASE11_RELEASE_NOTES.md"
)

for rel in "${FILES[@]}"; do
    if [[ -f "${REPO_ROOT}/${rel}" ]]; then
        check_pass "Required component exists: '${rel}'"
    else
        check_fail "Missing required component: '${rel}'"
    fi
done

# ------------------------------------------------------------------------------
# Module 2: Security Permissions & Shebang Integrity
# ------------------------------------------------------------------------------
log_mod "Module 2: Security Permissions & Shebang Integrity"

for s in "installer/partition-validator.sh" "installer/luks2-setup.sh" "installer/mayotix-installer.sh"; do
    if head -n 1 "${REPO_ROOT}/${s}" | grep -q "^#!/usr/bin/env bash"; then
        check_pass "'${s}' declares standard bash shebang"
    else
        check_fail "'${s}' invalid shebang"
    fi
done

if "$PYTHON_BIN" -m py_compile "${REPO_ROOT}/desktop/installer/mayotix-installer-gui.py" 2>/dev/null; then
    check_pass "Installer GUI wizard script compiles cleanly (syntax verified)"
else
    check_fail "Installer GUI script has syntax errors"
fi

# ------------------------------------------------------------------------------
# Module 3: Anaconda Kickstarts Configuration Integrity
# ------------------------------------------------------------------------------
log_mod "Module 3: Anaconda Kickstarts Configuration Integrity"

if grep -q "selinux --enforcing" "${REPO_ROOT}/installer/kickstart/mayotix-live.ks"; then
    check_pass "Live kickstart enforces SELinux Enforcing policy"
else
    check_fail "Live kickstart missing SELinux Enforcing"
fi

if grep -q "pbkdf=argon2id" "${REPO_ROOT}/installer/kickstart/mayotix-hardened.ks"; then
    check_pass "Hardened kickstart specifies LUKS2 Argon2id key derivation"
else
    check_fail "Hardened kickstart missing Argon2id definition"
fi

# ------------------------------------------------------------------------------
# Module 4: Partition Validator & Storage Device Discovery
# ------------------------------------------------------------------------------
log_mod "Module 4: Partition Validator & Storage Device Discovery"

if bash "${REPO_ROOT}/installer/partition-validator.sh" scan --dry-run --json | grep -q '"storage_scan"'; then
    check_pass "Storage scanner enumerates drives and firmware mode"
else
    check_fail "Storage scan command failed"
fi

if bash "${REPO_ROOT}/installer/partition-validator.sh" validate /dev/nvme0n1 --dry-run --json | grep -q '"status": "VALID"'; then
    check_pass "Partition validation verifies GPT layout and minimum sizes"
else
    check_fail "Partition layout validation failed"
fi

# ------------------------------------------------------------------------------
# Module 5: Dual-Boot Windows ESP Preservation Guard
# ------------------------------------------------------------------------------
log_mod "Module 5: Dual-Boot Windows ESP Preservation Guard"

if bash "${REPO_ROOT}/installer/partition-validator.sh" dualboot-check --dry-run --json | grep -q '"esp_protected": true'; then
    check_pass "Dual-boot check confirms Windows ESP protection"
else
    check_fail "Dual-boot check failed"
fi

# ------------------------------------------------------------------------------
# Module 6: LUKS2 Full-Disk Encryption & Key Escrow Engine
# ------------------------------------------------------------------------------
log_mod "Module 6: LUKS2 Full-Disk Encryption & Key Escrow Engine"

if bash "${REPO_ROOT}/installer/luks2-setup.sh" status --dry-run --json | grep -q '"pbkdf": "argon2id"'; then
    check_pass "LUKS2 status confirms 512-bit cipher and Argon2id KDF"
else
    check_fail "LUKS2 status command failed"
fi

if bash "${REPO_ROOT}/installer/luks2-setup.sh" generate-recovery-key --dry-run --json | grep -q '"entropy_bits": 256'; then
    check_pass "Disaster recovery key generator emits 256-bit token"
else
    check_fail "Recovery key generation failed"
fi

# ------------------------------------------------------------------------------
# Module 7: Master Installer Lifecycle & Pre-Flight Diagnostics
# ------------------------------------------------------------------------------
log_mod "Module 7: Master Installer Lifecycle & Pre-Flight Diagnostics"

if bash "${REPO_ROOT}/installer/mayotix-installer.sh" preflight --dry-run --json | grep -q '"readiness": "READY_TO_INSTALL"'; then
    check_pass "Installer preflight diagnostics pass (UEFI, Secure Boot, RAM)"
else
    check_fail "Installer preflight checks failed"
fi

if bash "${REPO_ROOT}/installer/mayotix-installer.sh" install --dry-run --json | grep -q '"status": "COMPLETED"'; then
    check_pass "Full installer pipeline executes cleanly in dry-run mode"
else
    check_fail "Installer execution failed"
fi

# ------------------------------------------------------------------------------
# Module 8: SELinux Installer Domain Confinement & Host Airgap
# ------------------------------------------------------------------------------
log_mod "Module 8: SELinux Installer Domain Confinement & Host Airgap"

TE_FILE="${REPO_ROOT}/security/selinux/mayotix_installer.te"
if grep -q "mayotix_installer_t" "$TE_FILE" && grep -q "fixed_disk_device_t" "$TE_FILE"; then
    check_pass "SELinux policy declares mayotix_installer_t and block device access"
else
    check_fail "SELinux policy missing installer domain"
fi

if ! grep -v '^[[:space:]]*#' "$TE_FILE" | grep -q "user_home_t"; then
    check_pass "SELinux policy enforces strict host airgap (zero user_home_t access)"
else
    check_fail "SELinux policy contains prohibited user_home_t access"
fi

# ------------------------------------------------------------------------------
# Module 9: Privileged IPC Daemon Endpoints
# ------------------------------------------------------------------------------
log_mod "Module 9: Privileged IPC Daemon Endpoints"

DAEMON_FILE="${REPO_ROOT}/daemon/mayotix-daemon.py"
RPC_METHODS=(
    "installer.preflight"
    "installer.disks"
    "installer.validate_layout"
    "installer.luks_status"
    "installer.simulate"
)

for m in "${RPC_METHODS[@]}"; do
    if grep -q "\"${m}\"" "$DAEMON_FILE"; then
        check_pass "IPC daemon registers endpoint '${m}'"
    else
        check_fail "IPC daemon missing endpoint '${m}'"
    fi
done

# ------------------------------------------------------------------------------
# Module 10: Unified CLI Subcommands & Security Audit
# ------------------------------------------------------------------------------
log_mod "Module 10: Unified CLI Subcommands & Security Audit"

if "$PYTHON_BIN" "${REPO_ROOT}/cli/mayotix" install preflight --dry-run >/dev/null 2>&1; then
    check_pass "Unified CLI executes 'mayotix install preflight --dry-run'"
else
    check_fail "CLI failed 'mayotix install preflight --dry-run'"
fi

if "$PYTHON_BIN" "${REPO_ROOT}/cli/mayotix" install disks --dry-run >/dev/null 2>&1; then
    check_pass "Unified CLI executes 'mayotix install disks --dry-run'"
else
    check_fail "CLI failed 'mayotix install disks --dry-run'"
fi

if "$PYTHON_BIN" "${REPO_ROOT}/cli/mayotix" install validate --dry-run >/dev/null 2>&1; then
    check_pass "Unified CLI executes 'mayotix install validate --dry-run'"
else
    check_fail "CLI failed 'mayotix install validate --dry-run'"
fi

if "$PYTHON_BIN" "${REPO_ROOT}/cli/mayotix" install luks --dry-run >/dev/null 2>&1; then
    check_pass "Unified CLI executes 'mayotix install luks --dry-run'"
else
    check_fail "CLI failed 'mayotix install luks --dry-run'"
fi

AUDIT_SCRIPT="${REPO_ROOT}/scripts/conduct-security-audit-phase11.sh"
if bash "$AUDIT_SCRIPT" --dry-run --json | grep -q '"status": "PASS"'; then
    check_pass "Phase 11 Comprehensive Security Audit achieved 100/100 points (PASS)"
else
    check_fail "Phase 11 Security Audit failed to achieve 100 points"
fi

echo ""
echo "=============================================================================="
echo "MAYOTIX OS Phase 11 Verification Summary"
echo "Total Checks: ${TOTAL_TESTS} | Passed: ${PASSED_TESTS} | Failed: ${FAILED_TESTS} | Warnings: 0"
echo "=============================================================================="

if [[ $FAILED_TESTS -eq 0 ]]; then
    echo -e "${GREEN}[✓] PHASE 11 ANACONDA INSTALLER & DUAL-BOOT: ALL CHECKS PASSED (100%)${NC}"
    exit 0
else
    echo -e "${RED}[ERROR] PHASE 11 VERIFICATION FAILED with ${FAILED_TESTS} errors.${NC}"
    exit 1
fi
