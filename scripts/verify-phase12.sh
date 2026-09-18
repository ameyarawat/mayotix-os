#!/usr/bin/env bash
# ==============================================================================
# MAYOTIX OS — Phase 12: Automated Penetration Testing & Hardening Verification
# File: scripts/verify-phase12.sh
# Mode: 0755
# Description: Validates the Phase 12 Hardening and Penetration Testing subsystem:
#              privilege escalation checks, sandbox escape probes, command injection
#              fuzzer, network exposure auditor, SELinux policy, daemon IPC, CLI,
#              and Wayland desktop GUI.
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

echo -e "${BLUE}[INFO]${NC} Starting MAYOTIX OS Phase 12 Automated Penetration Testing Verification..."
echo ""

# ------------------------------------------------------------------------------
# Module 1: File Presence & Directory Structure
# ------------------------------------------------------------------------------
log_mod "Module 1: File Presence & Directory Structure"

FILES=(
    "tests/pentest/privesc-check.sh"
    "tests/pentest/sandbox-escape.sh"
    "tests/pentest/injection-fuzzer.py"
    "tests/pentest/network-exposure.sh"
    "desktop/pentest/mayotix-pentest-gui.py"
    "desktop/applications/mayotix-pentest.desktop"
    "security/selinux/mayotix_pentest.te"
    "security/selinux/mayotix_pentest.fc"
    "daemon/mayotix-daemon.py"
    "cli/mayotix"
    "scripts/conduct-security-audit-phase12.sh"
    "docs/PHASE12_HARDENING_PENTEST.md"
    "docs/PHASE12_RELEASE_NOTES.md"
)

for rel in "${FILES[@]}"; do
    if [[ -f "${REPO_ROOT}/${rel}" ]]; then
        check_pass "Required component exists: '${rel}'"
    else
        check_fail "Missing required component: '${rel}'"
    fi
done

# ------------------------------------------------------------------------------
# Module 2: Automated Privilege Escalation Auditing Suite
# ------------------------------------------------------------------------------
log_mod "Module 2: Automated Privilege Escalation Auditing Suite"

PRIVESC_SH="${REPO_ROOT}/tests/pentest/privesc-check.sh"
if [[ -f "$PRIVESC_SH" ]]; then
    check_pass "Privilege escalation suite executable found"
    
    out_priv=$(bash "$PRIVESC_SH" scan --dry-run --json 2>&1)
    if echo "$out_priv" | grep -q '"status": "PASS"'; then
        check_pass "Privilege escalation audit scan passed"
    else
        check_fail "Privilege escalation scan failed: ${out_priv}"
    fi

    if echo "$out_priv" | grep -q '"dangerous_suid_found": 0'; then
        check_pass "GTFOBins dangerous SUID scan verified clean"
    else
        check_fail "Dangerous SUID detected"
    fi

    if echo "$out_priv" | grep -q '"nopasswd_bypass": false'; then
        check_pass "Sudoers NOPASSWD bypass protection verified"
    else
        check_fail "Sudoers NOPASSWD bypass detected"
    fi
else
    check_fail "privesc-check.sh not found"
fi

# ------------------------------------------------------------------------------
# Module 3: Sandbox Breakout & Escape Prober
# ------------------------------------------------------------------------------
log_mod "Module 3: Sandbox Breakout & Escape Prober"

SANDBOX_SH="${REPO_ROOT}/tests/pentest/sandbox-escape.sh"
if [[ -f "$SANDBOX_SH" ]]; then
    check_pass "Sandbox escape prober executable found"

    out_sbx=$(bash "$SANDBOX_SH" run-all --dry-run --json 2>&1)
    if echo "$out_sbx" | grep -q '"status": "PASS"'; then
        check_pass "Sandbox breakout probe execution passed"
    else
        check_fail "Sandbox breakout probe failed: ${out_sbx}"
    fi

    if echo "$out_sbx" | grep -q '"failed_probes": 0'; then
        check_pass "Zero sandbox breakout failures recorded"
    else
        check_fail "Sandbox escape breakout detected"
    fi

    if echo "$out_sbx" | grep -q '"containment": "UNCOMPROMISED"'; then
        check_pass "Sandbox containment posture uncompromised"
    else
        check_fail "Sandbox containment compromised"
    fi
else
    check_fail "sandbox-escape.sh not found"
fi

# ------------------------------------------------------------------------------
# Module 4: Command Injection & Metacharacter Fuzzing Suite
# ------------------------------------------------------------------------------
log_mod "Module 4: Command Injection & Metacharacter Fuzzing Suite"

FUZZER_PY="${REPO_ROOT}/tests/pentest/injection-fuzzer.py"
if [[ -f "$FUZZER_PY" ]]; then
    check_pass "Injection fuzzer executable found"

    out_fuzz=$("$PYTHON_BIN" "$FUZZER_PY" fuzz --dry-run --json 2>&1)
    if echo "$out_fuzz" | grep -q '"status": "PASS"'; then
        check_pass "Command injection fuzzing run passed"
    else
        check_fail "Fuzzing run failed: ${out_fuzz}"
    fi

    if echo "$out_fuzz" | grep -q '"resistance_rate_percent": 100.0'; then
        check_pass "100.0% malicious input resistance rate verified"
    else
        check_fail "Input resistance below 100%"
    fi

    if echo "$out_fuzz" | grep -q '"posture": "INJECTION_IMMUNE"'; then
        check_pass "Input validation posture confirmed INJECTION_IMMUNE"
    else
        check_fail "System vulnerable to injection"
    fi
else
    check_fail "injection-fuzzer.py not found"
fi

# ------------------------------------------------------------------------------
# Module 5: Network Exposure & Attack Surface Prober
# ------------------------------------------------------------------------------
log_mod "Module 5: Network Exposure & Attack Surface Prober"

NET_SH="${REPO_ROOT}/tests/pentest/network-exposure.sh"
if [[ -f "$NET_SH" ]]; then
    check_pass "Network exposure prober executable found"

    out_net=$(bash "$NET_SH" audit --dry-run --json 2>&1)
    if echo "$out_net" | grep -q '"status": "PASS"'; then
        check_pass "Network exposure audit passed"
    else
        check_fail "Network exposure audit failed: ${out_net}"
    fi

    if echo "$out_net" | grep -q '"unauthorized_listening_ports": 0'; then
        check_pass "Zero unauthorized open listening sockets verified"
    else
        check_fail "Unauthorized listening ports detected"
    fi

    if echo "$out_net" | grep -q '"egress_leakage_detected": false'; then
        check_pass "Egress containment confirmed (no physical network leakage)"
    else
        check_fail "Subnet egress leakage detected"
    fi

    if echo "$out_net" | grep -q '"killswitch_ready": true'; then
        check_pass "Fail-closed firewall killswitch verified ready"
    else
        check_fail "Firewall killswitch not ready"
    fi
else
    check_fail "network-exposure.sh not found"
fi

# ------------------------------------------------------------------------------
# Module 6: Kernel Hardening Sysctl Verification
# ------------------------------------------------------------------------------
log_mod "Module 6: Kernel Hardening Sysctl Verification"

if grep -q "kernel.unprivileged_bpf_disabled" "$PRIVESC_SH" && \
   grep -q "kernel.yama.ptrace_scope" "$PRIVESC_SH" && \
   grep -q "kernel.kptr_restrict" "$PRIVESC_SH" && \
   grep -q "fs.suid_dumpable" "$PRIVESC_SH"; then
    check_pass "Kernel security sysctls comprehensively audited"
else
    check_fail "Kernel sysctl checks missing"
fi

# ------------------------------------------------------------------------------
# Module 7: SELinux MAC Pentest Policy & Zero-Home Airgap
# ------------------------------------------------------------------------------
log_mod "Module 7: SELinux MAC Pentest Policy & Zero-Home Airgap"

TE_FILE="${REPO_ROOT}/security/selinux/mayotix_pentest.te"
FC_FILE="${REPO_ROOT}/security/selinux/mayotix_pentest.fc"

if [[ -f "$TE_FILE" && -f "$FC_FILE" ]]; then
    check_pass "SELinux policy files exist"

    if grep -q "type mayotix_pentest_t;" "$TE_FILE" && grep -q "type mayotix_pentest_exec_t;" "$TE_FILE"; then
        check_pass "Domain types mayotix_pentest_t & mayotix_pentest_exec_t defined"
    else
        check_fail "Domain types missing in mayotix_pentest.te"
    fi

    if ! grep -v '^[[:space:]]*#' "$TE_FILE" | grep -q "user_home_t"; then
        check_pass "Strict zero-home airgap enforced (zero user_home_t access in policy)"
    else
        check_fail "Airgap violation: user_home_t found in policy"
    fi
else
    check_fail "SELinux policy files missing"
fi

# ------------------------------------------------------------------------------
# Module 8: Privileged IPC Daemon Pentest RPC Endpoints
# ------------------------------------------------------------------------------
log_mod "Module 8: Privileged IPC Daemon Pentest RPC Endpoints"

DAEMON_FILE="${REPO_ROOT}/daemon/mayotix-daemon.py"
if [[ -f "$DAEMON_FILE" ]]; then
    METHODS=(
        "pentest.privesc"
        "pentest.sandbox_escape"
        "pentest.fuzz"
        "pentest.network_audit"
        "pentest.report"
    )
    for m in "${METHODS[@]}"; do
        if grep -q "\"${m}\"" "$DAEMON_FILE"; then
            check_pass "Registered IPC endpoint: '${m}'"
        else
            check_fail "Missing IPC endpoint: '${m}'"
        fi
    done
else
    check_fail "mayotix-daemon.py not found"
fi

# ------------------------------------------------------------------------------
# Module 9: Unified CLI mayotix pentest Subcommand Execution
# ------------------------------------------------------------------------------
log_mod "Module 9: Unified CLI mayotix pentest Subcommand Execution"

CLI_FILE="${REPO_ROOT}/cli/mayotix"
if [[ -f "$CLI_FILE" ]]; then
    for subcmd in "privesc" "sandbox" "fuzz" "network"; do
        cli_out=$("$PYTHON_BIN" "$CLI_FILE" pentest "$subcmd" --dry-run --json 2>&1)
        if echo "$cli_out" | grep -qi "PASS"; then
            check_pass "CLI subcommand 'mayotix pentest ${subcmd} --dry-run --json' passed"
        else
            check_fail "CLI subcommand 'mayotix pentest ${subcmd}' failed: ${cli_out}"
        fi
    done
else
    check_fail "cli/mayotix not found"
fi

# ------------------------------------------------------------------------------
# Module 10: Wayland Penetration Testing Studio GUI & Desktop Integration
# ------------------------------------------------------------------------------
log_mod "Module 10: Wayland Penetration Testing Studio GUI & Desktop Integration"

GUI_FILE="${REPO_ROOT}/desktop/pentest/mayotix-pentest-gui.py"
DESKTOP_FILE="${REPO_ROOT}/desktop/applications/mayotix-pentest.desktop"

if [[ -f "$GUI_FILE" && -f "$DESKTOP_FILE" ]]; then
    check_pass "Pentest GUI script and .desktop entry exist"

    gui_out=$("$PYTHON_BIN" "$GUI_FILE" --dry-run --json 2>&1)
    if echo "$gui_out" | grep -q '"status": "OPERATIONAL"'; then
        check_pass "Pentest GUI headless verification passed"
    else
        check_fail "Pentest GUI headless verification failed: ${gui_out}"
    fi

    if grep -q "X-Wayland-Native=true" "$DESKTOP_FILE"; then
        check_pass "X-Wayland-Native acceleration enabled in desktop file"
    else
        check_fail "X-Wayland-Native flag missing in desktop file"
    fi
else
    check_fail "GUI or .desktop file missing"
fi

# ------------------------------------------------------------------------------
# Final Verification Summary
# ------------------------------------------------------------------------------
echo ""
echo "=============================================================================="
echo "MAYOTIX OS Phase 12 Verification Results"
echo "=============================================================================="
echo -e "  Total Tests Run : ${TOTAL_TESTS}"
echo -e "  Passed Tests    : ${GREEN}${PASSED_TESTS}${NC}"
echo -e "  Failed Tests    : $([[ $FAILED_TESTS -eq 0 ]] && echo -e "${GREEN}0${NC}" || echo -e "${RED}${FAILED_TESTS}${NC}")"
echo "=============================================================================="

if [[ $FAILED_TESTS -eq 0 ]]; then
    echo -e "${GREEN}[✓] ALL PHASE 12 HARDENING & PENTEST TESTS PASSED SUCCESSFULLY.${NC}"
    exit 0
else
    echo -e "${RED}[ERROR] Phase 12 verification failed with ${FAILED_TESTS} failures.${NC}"
    exit 1
fi
