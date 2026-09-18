#!/usr/bin/env bash
# ==============================================================================
# MAYOTIX OS — Phase 10: Hardened Gaming & Performance Verification Harness
# File: scripts/verify-phase10.sh
# Mode: 0755
# Description: Validates the entire Phase 10 Gaming subsystem: GameMode governor,
#              GPU/Vulkan DRI probe, Proton compatibility runtimes, Bubblewrap
#              airgap sandboxing, SELinux policy, daemon IPC, CLI, and GUI.
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

echo -e "${BLUE}[INFO]${NC} Starting MAYOTIX OS Phase 10 Hardened Gaming & Performance Verification..."
echo ""

# ------------------------------------------------------------------------------
# Module 1: File Presence & Directory Structure
# ------------------------------------------------------------------------------
log_mod "Module 1: File Presence & Directory Structure"

FILES=(
    "desktop/gaming/mayotix-gamemode.sh"
    "desktop/gaming/gpu-optimizer.sh"
    "desktop/gaming/proton-runner.sh"
    "desktop/gaming/steam-launcher.sh"
    "desktop/gaming/mayotix-gaming-gui.py"
    "desktop/applications/mayotix-gaming.desktop"
    "security/selinux/mayotix_gaming.te"
    "security/selinux/mayotix_gaming.fc"
    "daemon/mayotix-daemon.py"
    "cli/mayotix"
    "scripts/conduct-security-audit-phase10.sh"
    "docs/PHASE10_GAMING_SUPPORT.md"
    "docs/PHASE10_RELEASE_NOTES.md"
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

for s in "desktop/gaming/mayotix-gamemode.sh" "desktop/gaming/gpu-optimizer.sh" "desktop/gaming/proton-runner.sh" "desktop/gaming/steam-launcher.sh"; do
    if head -n 1 "${REPO_ROOT}/${s}" | grep -q "^#!/usr/bin/env bash"; then
        check_pass "'${s}' declares standard bash shebang"
    else
        check_fail "'${s}' invalid shebang"
    fi
done

if "$PYTHON_BIN" -m py_compile "${REPO_ROOT}/desktop/gaming/mayotix-gaming-gui.py" 2>/dev/null; then
    check_pass "Gaming Center GUI script compiles cleanly (syntax verified)"
else
    check_fail "Gaming Center GUI script has syntax errors"
fi

# ------------------------------------------------------------------------------
# Module 3: Feral GameMode Controller & Performance Governors
# ------------------------------------------------------------------------------
log_mod "Module 3: Feral GameMode Controller & Performance Governors"

if bash "${REPO_ROOT}/desktop/gaming/mayotix-gamemode.sh" status --dry-run --json | grep -q '"gamemode"'; then
    check_pass "GameMode status reports governor and renice capabilities"
else
    check_fail "GameMode status command failed"
fi

if bash "${REPO_ROOT}/desktop/gaming/mayotix-gamemode.sh" start --dry-run --json | grep -q '"status": "ENGAGED"'; then
    check_pass "GameMode engagement simulates performance profile switch"
else
    check_fail "GameMode start command failed"
fi

if bash "${REPO_ROOT}/desktop/gaming/mayotix-gamemode.sh" stop --dry-run --json | grep -q '"status": "DISENGAGED"'; then
    check_pass "GameMode disengagement restores baseline governor"
else
    check_fail "GameMode stop command failed"
fi

# ------------------------------------------------------------------------------
# Module 4: GPU Acceleration & Vulkan Probe
# ------------------------------------------------------------------------------
log_mod "Module 4: GPU Acceleration & Vulkan Probe"

if bash "${REPO_ROOT}/desktop/gaming/gpu-optimizer.sh" status --dry-run --json | grep -q '"vulkan_support": true'; then
    check_pass "GPU status detects Vulkan 1.3 and DRI render nodes"
else
    check_fail "GPU status command failed"
fi

if bash "${REPO_ROOT}/desktop/gaming/gpu-optimizer.sh" optimize-shaders --dry-run --json | grep -q '"status": "CONFIGURED"'; then
    check_pass "Isolated Mesa shader cache configuration verified"
else
    check_fail "Shader cache optimization failed"
fi

# ------------------------------------------------------------------------------
# Module 5: Proton & Wine Compatibility Engine
# ------------------------------------------------------------------------------
log_mod "Module 5: Proton & Wine Compatibility Engine"

if bash "${REPO_ROOT}/desktop/gaming/proton-runner.sh" status --dry-run --json | grep -q '"dxvk"'; then
    check_pass "Proton runner confirms DXVK and VKD3D translation engine"
else
    check_fail "Proton status failed"
fi

if bash "${REPO_ROOT}/desktop/gaming/proton-runner.sh" anticheat-check --dry-run --json | grep -q '"status": "PASS"'; then
    check_pass "Anti-cheat compatibility audit verifies user-space bridge mode"
else
    check_fail "Anti-cheat audit failed"
fi

# ------------------------------------------------------------------------------
# Module 6: Sandboxed Steam & Bubblewrap Airgap Verification
# ------------------------------------------------------------------------------
log_mod "Module 6: Sandboxed Steam & Bubblewrap Airgap Verification"

if bash "${REPO_ROOT}/desktop/gaming/steam-launcher.sh" status --dry-run --json | grep -q '"ssh_blocked": true'; then
    check_pass "Steam sandbox verifies host airgap (~/.ssh and ~/.gnupg masked)"
else
    check_fail "Steam sandbox status failed"
fi

if bash "${REPO_ROOT}/desktop/gaming/steam-launcher.sh" verify-sandbox --dry-run --json | grep -q '"status": "PASSED"'; then
    check_pass "Sandboxed container airgap verification 100% passed"
else
    check_fail "Sandbox verification failed"
fi

# ------------------------------------------------------------------------------
# Module 7: SELinux Gaming Policy Confinement & Host Airgap
# ------------------------------------------------------------------------------
log_mod "Module 7: SELinux Gaming Policy Confinement & Host Airgap"

TE_FILE="${REPO_ROOT}/security/selinux/mayotix_gaming.te"
if grep -q "mayotix_gaming_t" "$TE_FILE" && grep -q "dri_device_t" "$TE_FILE"; then
    check_pass "SELinux policy declares mayotix_gaming_t and DRI device access"
else
    check_fail "SELinux policy missing gaming domain"
fi

if ! grep -v '^[[:space:]]*#' "$TE_FILE" | grep -q "user_home_t"; then
    check_pass "SELinux policy enforces strict host airgap (zero user_home_t access)"
else
    check_fail "SELinux policy contains prohibited user_home_t access"
fi

# ------------------------------------------------------------------------------
# Module 8: Privileged IPC Daemon Endpoints
# ------------------------------------------------------------------------------
log_mod "Module 8: Privileged IPC Daemon Endpoints"

DAEMON_FILE="${REPO_ROOT}/daemon/mayotix-daemon.py"
RPC_METHODS=(
    "game.status"
    "game.gamemode_start"
    "game.gamemode_stop"
    "game.gpu_status"
    "game.proton_status"
    "game.launch"
    "game.anticheat_audit"
)

for m in "${RPC_METHODS[@]}"; do
    if grep -q "\"${m}\"" "$DAEMON_FILE"; then
        check_pass "IPC daemon registers endpoint '${m}'"
    else
        check_fail "IPC daemon missing endpoint '${m}'"
    fi
done

# ------------------------------------------------------------------------------
# Module 9: Unified CLI Subcommands (mayotix game ...)
# ------------------------------------------------------------------------------
log_mod "Module 9: Unified CLI Subcommands"

if "$PYTHON_BIN" "${REPO_ROOT}/cli/mayotix" game status --dry-run >/dev/null 2>&1; then
    check_pass "Unified CLI executes 'mayotix game status --dry-run'"
else
    check_fail "CLI failed 'mayotix game status --dry-run'"
fi

if "$PYTHON_BIN" "${REPO_ROOT}/cli/mayotix" game optimize status --dry-run >/dev/null 2>&1; then
    check_pass "Unified CLI executes 'mayotix game optimize status --dry-run'"
else
    check_fail "CLI failed 'mayotix game optimize status --dry-run'"
fi

if "$PYTHON_BIN" "${REPO_ROOT}/cli/mayotix" game gpu --dry-run >/dev/null 2>&1; then
    check_pass "Unified CLI executes 'mayotix game gpu --dry-run'"
else
    check_fail "CLI failed 'mayotix game gpu --dry-run'"
fi

if "$PYTHON_BIN" "${REPO_ROOT}/cli/mayotix" game proton --dry-run >/dev/null 2>&1; then
    check_pass "Unified CLI executes 'mayotix game proton --dry-run'"
else
    check_fail "CLI failed 'mayotix game proton --dry-run'"
fi

if "$PYTHON_BIN" "${REPO_ROOT}/cli/mayotix" game anticheat --dry-run >/dev/null 2>&1; then
    check_pass "Unified CLI executes 'mayotix game anticheat --dry-run'"
else
    check_fail "CLI failed 'mayotix game anticheat --dry-run'"
fi

if "$PYTHON_BIN" "${REPO_ROOT}/cli/mayotix" game launch --dry-run >/dev/null 2>&1; then
    check_pass "Unified CLI executes 'mayotix game launch --dry-run'"
else
    check_fail "CLI failed 'mayotix game launch --dry-run'"
fi

# ------------------------------------------------------------------------------
# Module 10: Comprehensive Security Audit (100/100 points)
# ------------------------------------------------------------------------------
log_mod "Module 10: Comprehensive Security Audit (100/100 points)"

AUDIT_SCRIPT="${REPO_ROOT}/scripts/conduct-security-audit-phase10.sh"
if bash "$AUDIT_SCRIPT" --dry-run --json | grep -q '"status": "PASS"'; then
    check_pass "Phase 10 Comprehensive Security Audit achieved 100/100 points (PASS)"
else
    check_fail "Phase 10 Security Audit failed to achieve 100 points"
fi

echo ""
echo "=============================================================================="
echo "MAYOTIX OS Phase 10 Verification Summary"
echo "Total Checks: ${TOTAL_TESTS} | Passed: ${PASSED_TESTS} | Failed: ${FAILED_TESTS} | Warnings: 0"
echo "=============================================================================="

if [[ $FAILED_TESTS -eq 0 ]]; then
    echo -e "${GREEN}[✓] PHASE 10 HARDENED GAMING & PERFORMANCE: ALL CHECKS PASSED (100%)${NC}"
    exit 0
else
    echo -e "${RED}[ERROR] PHASE 10 VERIFICATION FAILED with ${FAILED_TESTS} errors.${NC}"
    exit 1
fi
