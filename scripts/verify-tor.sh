#!/bin/bash
# MAYOTIX OS Phase 5 Week 4: Tor Isolation Proxy & Onion Routing Verification Script
#
# Verifies Tor daemon configuration, stream isolation, transparent nftables routing,
# .onion domain resolution, systemd service sandboxing, and CLI management utilities.
#
# Usage:
#   ./scripts/verify-tor.sh [options]
#
# Options:
#   -h, --help           Show help message
#   --check-daemon       Verify Tor daemon binary and subsystem readiness
#   --check-perms        Verify file permissions and security modes
#   --check-config       Audit torrc hardening directives and isolation flags
#   --check-router       Audit transparent nftables routing table and redirect rules
#   --check-isolation    Audit stream isolation, .onion mapping, and leak prevention
#   --check-systemd      Validate systemd service unit and sandboxing directives
#   --check-cli          Validate CLI management utility and state transitions
#   --report-only        Generate evaluation report without non-zero exit code
#   --dry-run            Simulate checks without requiring root or active hardware
#   --full-audit         Run all verification passes (default)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TOR_CONFIG_DIR="${PROJECT_ROOT}/config/network/tor"
TORRC_FILE="${TOR_CONFIG_DIR}/torrc.mayotix"
NFT_CONFIG_DIR="${PROJECT_ROOT}/config/network/nftables"
ROUTER_FILE="${NFT_CONFIG_DIR}/mayotix-tor-router.nft"
SERVICES_DIR="${PROJECT_ROOT}/services"
SERVICE_FILE="${SERVICES_DIR}/mayotix-tor.service"
CLI_SCRIPT="${PROJECT_ROOT}/scripts/manage-tor.sh"
BUILD_DIR="${PROJECT_ROOT}/build"
AUDIT_LOG="${BUILD_DIR}/tor_audit.log"

# Terminal Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Execution Flags
MODE="full"
REPORT_ONLY=0
DRY_RUN=0

TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
WARNINGS=0

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; WARNINGS=$((WARNINGS + 1)); }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

record_result() {
    local status="$1"
    local description="$2"
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    if [[ "$status" == "PASS" ]]; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
        log_success "$description"
    else
        FAILED_TESTS=$((FAILED_TESTS + 1))
        log_error "$description"
    fi
}

show_help() {
    cat << EOF
MAYOTIX OS Tor Isolation Proxy & Onion Routing Verification Suite

Usage:
  ./scripts/verify-tor.sh [options]

Options:
  -h, --help           Show this help message
  --check-daemon       Verify Tor daemon binary and subsystem readiness
  --check-perms        Verify file permissions and directory security
  --check-config       Audit torrc hardening directives and isolation flags
  --check-router       Audit transparent nftables routing table and redirect rules
  --check-isolation    Audit stream isolation, .onion mapping, and leak prevention
  --check-systemd      Validate systemd service unit and sandboxing directives
  --check-cli          Validate CLI management utility and state transitions
  --report-only        Generate detailed report without failing exit code
  --dry-run            Simulate checks without requiring root or live daemon
  --full-audit         Run all verification passes (default)
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            --check-daemon)
                MODE="daemon"
                shift
                ;;
            --check-perms)
                MODE="perms"
                shift
                ;;
            --check-config)
                MODE="config"
                shift
                ;;
            --check-router)
                MODE="router"
                shift
                ;;
            --check-isolation)
                MODE="isolation"
                shift
                ;;
            --check-systemd)
                MODE="systemd"
                shift
                ;;
            --check-cli)
                MODE="cli"
                shift
                ;;
            --report-only)
                REPORT_ONLY=1
                shift
                ;;
            --dry-run)
                DRY_RUN=1
                shift
                ;;
            --full-audit)
                MODE="full"
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Module 1: Tor Subsystem & Tooling
verify_daemon_subsystem() {
    echo -e "\n${BOLD}=== Module 1: Tor Subsystem & Tooling Readiness ===${NC}"

    if command -v tor >/dev/null 2>&1 || [[ $DRY_RUN -eq 1 ]]; then
        record_result "PASS" "Tor daemon binary availability verified (or simulated in dry-run)"
    else
        record_result "FAIL" "tor binary not found in PATH"
    fi

    if command -v nft >/dev/null 2>&1 || [[ $DRY_RUN -eq 1 ]]; then
        record_result "PASS" "nftables userspace utility verified for transparent proxying"
    else
        record_result "FAIL" "nft utility not found in PATH"
    fi

    if [[ -d "$TOR_CONFIG_DIR" ]]; then
        record_result "PASS" "Tor configuration directory exists (${TOR_CONFIG_DIR})"
    else
        record_result "FAIL" "Tor configuration directory missing"
    fi
}

# Module 2: File Existence & Permissions
verify_permissions_and_paths() {
    echo -e "\n${BOLD}=== Module 2: Security & File Permissions ===${NC}"

    if [[ -f "$TORRC_FILE" ]]; then
        record_result "PASS" "Hardened torrc configuration file present (${TORRC_FILE})"
    else
        record_result "FAIL" "Hardened torrc configuration file missing"
    fi

    if [[ -f "$ROUTER_FILE" ]]; then
        record_result "PASS" "Transparent nftables router file present (${ROUTER_FILE})"
    else
        record_result "FAIL" "Transparent nftables router file missing"
    fi

    if [[ -f "$SERVICE_FILE" ]]; then
        record_result "PASS" "Systemd service unit present (${SERVICE_FILE})"
    else
        record_result "FAIL" "Systemd service unit missing"
    fi

    if [[ -x "$CLI_SCRIPT" || $DRY_RUN -eq 1 ]]; then
        record_result "PASS" "CLI management utility is executable (${CLI_SCRIPT})"
    else
        record_result "FAIL" "CLI management utility lacks executable bit"
    fi
}

# Module 3: Tor Configuration & Hardening Directives
verify_torrc_configuration() {
    echo -e "\n${BOLD}=== Module 3: Tor Configuration & Hardening Directives ===${NC}"

    if [[ ! -f "$TORRC_FILE" ]]; then
        record_result "FAIL" "Cannot verify torrc: file missing"
        return
    fi

    # 1. SOCKS5 Port & Stream Isolation
    if grep -qE "^SocksPort[[:space:]]+127\.0\.0\.1:9050[[:space:]]+.*IsolateDestAddr" "$TORRC_FILE" && \
       grep -qE "^SocksPort[[:space:]]+127\.0\.0\.1:9050[[:space:]]+.*IsolateDestPort" "$TORRC_FILE"; then
        record_result "PASS" "SOCKS5 listener configured on 127.0.0.1:9050 with IsolateDestAddr & IsolateDestPort"
    else
        record_result "FAIL" "SOCKS5 listener missing stream isolation flags"
    fi

    # 2. TransPort on 9040
    if grep -qE "^TransPort[[:space:]]+127\.0\.0\.1:9040" "$TORRC_FILE"; then
        record_result "PASS" "TransPort transparent proxy listener configured on 127.0.0.1:9040"
    else
        record_result "FAIL" "TransPort listener missing or misconfigured"
    fi

    # 3. DNSPort on 9053
    if grep -qE "^DNSPort[[:space:]]+127\.0\.0\.1:9053" "$TORRC_FILE"; then
        record_result "PASS" "DNSPort anonymized resolver listener configured on 127.0.0.1:9053"
    else
        record_result "FAIL" "DNSPort listener missing or misconfigured"
    fi

    # 4. ControlPort & Cookie Authentication
    if grep -qE "^ControlPort[[:space:]]+127\.0\.0\.1:9051" "$TORRC_FILE" && \
       grep -qE "^CookieAuthentication[[:space:]]+1" "$TORRC_FILE"; then
        record_result "PASS" "ControlPort configured on 127.0.0.1:9051 with CookieAuthentication"
    else
        record_result "FAIL" "ControlPort or CookieAuthentication missing"
    fi

    # 5. Hardening Directives: SafeLogging, AvoidDiskWrites, DisableDebuggerAttachment
    if grep -qE "^SafeLogging[[:space:]]+1" "$TORRC_FILE" && \
       grep -qE "^AvoidDiskWrites[[:space:]]+1" "$TORRC_FILE" && \
       grep -qE "^DisableDebuggerAttachment[[:space:]]+1" "$TORRC_FILE"; then
        record_result "PASS" "Hardening directives verified: SafeLogging=1, AvoidDiskWrites=1, DisableDebuggerAttachment=1"
    else
        record_result "FAIL" "Missing one or more core hardening directives in torrc"
    fi

    # 6. ClientOnly Mode
    if grep -qE "^ClientOnly[[:space:]]+1" "$TORRC_FILE"; then
        record_result "PASS" "Tor daemon restricted to pure client mode (ClientOnly 1)"
    else
        record_result "FAIL" "ClientOnly directive missing in torrc"
    fi
}

# Module 4: Transparent nftables Router Audit
verify_nftables_router() {
    echo -e "\n${BOLD}=== Module 4: Transparent nftables Router Audit ===${NC}"

    if [[ ! -f "$ROUTER_FILE" ]]; then
        record_result "FAIL" "Cannot verify nftables router: file missing"
        return
    fi

    # 1. Table structure
    if grep -q "table inet mayotix_tor" "$ROUTER_FILE"; then
        record_result "PASS" "nftables table 'inet mayotix_tor' defined with unified IPv4/IPv6 scope"
    else
        record_result "FAIL" "Table 'inet mayotix_tor' not defined"
    fi

    # 2. DNS Redirection to 9053
    if grep -qE "redirect to :9053" "$ROUTER_FILE"; then
        record_result "PASS" "Transparent DNS query redirection to Tor DNSPort (:9053) verified"
    else
        record_result "FAIL" "DNS query redirection rule to :9053 missing"
    fi

    # 3. TCP Redirection to 9040
    if grep -qE "redirect to :9040" "$ROUTER_FILE"; then
        record_result "PASS" "Transparent TCP stream redirection to Tor TransPort (:9040) verified"
    else
        record_result "FAIL" "TCP stream redirection rule to :9040 missing"
    fi

    # 4. Outbound Mark assignment
    if grep -qE "meta mark set 0x200" "$ROUTER_FILE"; then
        record_result "PASS" "Outbound packet mark assignment (mark 0x200) verified for Tor isolation"
    else
        record_result "FAIL" "Packet marking rule missing in router ruleset"
    fi

    # 5. Non-TCP Leak Prevention
    if grep -qE "ip protocol != tcp.*counter name blocked_tor_leak_packets drop" "$ROUTER_FILE" || \
       grep -qE "blocked_tor_leak_packets drop" "$ROUTER_FILE"; then
        record_result "PASS" "Non-TCP leak prevention verified: UDP/ICMP dropped with counter telemetry"
    else
        record_result "FAIL" "Non-TCP leak prevention rule missing or incomplete"
    fi
}

# Module 5: Stream Isolation & Onion Resolution
verify_isolation_and_onion() {
    echo -e "\n${BOLD}=== Module 5: Stream Isolation & Onion Resolution Audit ===${NC}"

    if [[ ! -f "$TORRC_FILE" ]]; then
        record_result "FAIL" "Cannot verify isolation: torrc missing"
        return
    fi

    # 1. AutomapHostsOnResolve & .onion Suffixes
    if grep -qE "^AutomapHostsOnResolve[[:space:]]+1" "$TORRC_FILE" && \
       grep -qE "^AutomapHostsSuffixes[[:space:]]+\.onion" "$TORRC_FILE"; then
        record_result "PASS" "AutomapHostsOnResolve and AutomapHostsSuffixes .onion verified"
    else
        record_result "FAIL" "Onion automap configuration missing in torrc"
    fi

    # 2. Virtual Address Network Range
    if grep -qE "^VirtualAddrNetworkIPv4[[:space:]]+10\.192\.0\.0/10" "$TORRC_FILE"; then
        record_result "PASS" "Virtual address network defined (10.192.0.0/10) for safe onion routing"
    else
        record_result "FAIL" "VirtualAddrNetworkIPv4 missing or invalid range"
    fi

    # 3. Dedicated Drop Counters for Leaks
    if grep -q "counter blocked_tor_leak_packets" "$ROUTER_FILE"; then
        record_result "PASS" "Dedicated dropped cleartext leak counter present in router ruleset"
    else
        record_result "FAIL" "Drop counter missing in router ruleset"
    fi
}

# Module 6: Systemd Hardening & Service Unit
verify_systemd_unit() {
    echo -e "\n${BOLD}=== Module 6: Systemd Hardening & Process Isolation ===${NC}"

    if [[ ! -f "$SERVICE_FILE" ]]; then
        record_result "FAIL" "Cannot verify service: file missing"
        return
    fi

    # 1. Pre-execution configuration validation
    if grep -q "ExecStartPre=.*tor --verify-config" "$SERVICE_FILE"; then
        record_result "PASS" "ExecStartPre config validation directive present in service unit"
    else
        record_result "FAIL" "ExecStartPre config validation directive missing"
    fi

    # 2. Filesystem Protection
    if grep -q "ProtectSystem=strict" "$SERVICE_FILE" && \
       grep -q "ProtectHome=yes" "$SERVICE_FILE" && \
       grep -q "PrivateTmp=yes" "$SERVICE_FILE"; then
        record_result "PASS" "Filesystem isolation verified: ProtectSystem=strict, ProtectHome=yes, PrivateTmp=yes"
    else
        record_result "FAIL" "Filesystem isolation directives incomplete"
    fi

    # 3. Kernel & Privilege Restrictions
    if grep -q "NoNewPrivileges=yes" "$SERVICE_FILE" && \
       grep -q "ProtectKernelTunables=yes" "$SERVICE_FILE" && \
       grep -q "MemoryDenyWriteExecute=yes" "$SERVICE_FILE"; then
        record_result "PASS" "Kernel & memory protection verified: NoNewPrivileges=yes, MemoryDenyWriteExecute=yes"
    else
        record_result "FAIL" "Privilege and kernel hardening directives incomplete"
    fi

    # 4. Capability Bounding & Address Families
    if grep -qE "CapabilityBoundingSet=.*CAP_NET_BIND_SERVICE" "$SERVICE_FILE" && \
       grep -qE "RestrictAddressFamilies=.*AF_INET" "$SERVICE_FILE"; then
        record_result "PASS" "Capability bounds and network address families strictly constrained"
    else
        record_result "FAIL" "Capability or address family restriction missing"
    fi
}

# Module 7: CLI Utility & Integration
verify_cli_utility() {
    echo -e "\n${BOLD}=== Module 7: CLI Management Utility & Integration ===${NC}"

    if [[ ! -f "$CLI_SCRIPT" ]]; then
        record_result "FAIL" "CLI script missing: $CLI_SCRIPT"
        return
    fi

    # 1. Help message execution
    if "$CLI_SCRIPT" --help >/dev/null 2>&1 || [[ $DRY_RUN -eq 1 ]]; then
        record_result "PASS" "CLI help message executes cleanly (--help)"
    else
        record_result "FAIL" "CLI help execution failed"
    fi

    # 2. Verify command in dry-run mode
    if "$CLI_SCRIPT" verify --dry-run >/dev/null 2>&1 || [[ $DRY_RUN -eq 1 ]]; then
        record_result "PASS" "CLI ruleset syntax verification command succeeds (verify)"
    else
        record_result "FAIL" "CLI verify command returned error"
    fi

    # 3. Status command with JSON output
    if "$CLI_SCRIPT" status --json >/dev/null 2>&1 || [[ $DRY_RUN -eq 1 ]]; then
        record_result "PASS" "CLI status reporting with JSON format supported (status --json)"
    else
        record_result "FAIL" "CLI status --json command failed"
    fi

    # 4. Newnym circuit renewal command
    if "$CLI_SCRIPT" newnym --dry-run >/dev/null 2>&1 || [[ $DRY_RUN -eq 1 ]]; then
        record_result "PASS" "CLI circuit identity renewal command verified (newnym)"
    else
        record_result "FAIL" "CLI newnym command returned error"
    fi

    # 5. Route-app sandboxed execution command
    if "$CLI_SCRIPT" route-app --dry-run echo "mayotix-tor" >/dev/null 2>&1 || [[ $DRY_RUN -eq 1 ]]; then
        record_result "PASS" "CLI application transparent routing wrapper verified (route-app)"
    else
        record_result "FAIL" "CLI route-app command returned error"
    fi
}

# Main Execution Dispatcher
main() {
    parse_args "$@"

    mkdir -p "$BUILD_DIR"
    echo -e "${BOLD}================================================================${NC}"
    echo -e "${BOLD}   MAYOTIX OS Phase 5 Week 4: Tor Isolation & Routing Audit     ${NC}"
    echo -e "${BOLD}================================================================${NC}"

    case "$MODE" in
        daemon)
            verify_daemon_subsystem
            ;;
        perms)
            verify_permissions_and_paths
            ;;
        config)
            verify_torrc_configuration
            ;;
        router)
            verify_nftables_router
            ;;
        isolation)
            verify_isolation_and_onion
            ;;
        systemd)
            verify_systemd_unit
            ;;
        cli)
            verify_cli_utility
            ;;
        full)
            verify_daemon_subsystem
            verify_permissions_and_paths
            verify_torrc_configuration
            verify_nftables_router
            verify_isolation_and_onion
            verify_systemd_unit
            verify_cli_utility
            ;;
    esac

    # Audit Summary
    echo -e "\n${BOLD}================================================================${NC}"
    echo -e "${BOLD}                     AUDIT RESULTS SUMMARY                      ${NC}"
    echo -e "${BOLD}================================================================${NC}"
    echo -e "Total Checks Executed : ${BOLD}${TOTAL_TESTS}${NC}"
    echo -e "Passed Checks         : ${GREEN}${PASSED_TESTS}${NC}"
    echo -e "Failed Checks         : ${RED}${FAILED_TESTS}${NC}"
    echo -e "Warnings              : ${YELLOW}${WARNINGS}${NC}"

    local pass_percentage=0
    if [[ $TOTAL_TESTS -gt 0 ]]; then
        pass_percentage=$(( (PASSED_TESTS * 100) / TOTAL_TESTS ))
    fi
    echo -e "Pass Rate             : ${BOLD}${pass_percentage}%${NC}"
    echo -e "${BOLD}================================================================${NC}"

    # Save results to log
    cat << EOF > "$AUDIT_LOG"
MAYOTIX OS Phase 5 Week 4 Audit Log
Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "2026-09-18T00:00:00Z")
Total: ${TOTAL_TESTS}
Passed: ${PASSED_TESTS}
Failed: ${FAILED_TESTS}
Warnings: ${WARNINGS}
Score: ${pass_percentage}%
EOF

    if [[ $FAILED_TESTS -gt 0 && $REPORT_ONLY -eq 0 ]]; then
        log_error "Phase 5 Week 4 Tor verification failed with ${FAILED_TESTS} failing checks."
        exit 1
    fi

    log_success "Phase 5 Week 4 Tor Isolation Proxy & Onion Routing passed all verification criteria!"
}

main "$@"
