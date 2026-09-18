#!/bin/bash
# MAYOTIX OS Phase 5 Week 2: Kernel WireGuard CLI Management Utility
#
# Manages WireGuard VPN profiles, key generation, interface lifecycle,
# system routing, and connection watchdog health monitoring.
#
# Usage:
#   ./scripts/manage-wireguard.sh <command> [options]
#
# Commands:
#   generate-keys         Generate WireGuard private key, public key, and PSK (0600 permissions)
#   create-profile        Generate profile configuration from template
#   up, start             Bring up WireGuard interface
#   down, stop            Bring down WireGuard interface
#   restart               Restart WireGuard interface
#   status                Show interface status, peer handshakes, and routing
#   watchdog              Check tunnel health and auto-reconnect if handshake lost
#   list                  List installed WireGuard profiles and templates
#   verify                Run sanity checks on WireGuard subsystem readiness
#
# Options:
#   --interface, -i NAME  WireGuard interface name (default: wg0)
#   --config, -c FILE     Path to profile configuration file
#   --template, -t NAME   Template type: client, psk, pinned (default: client)
#   --threshold, -s SEC   Watchdog handshake timeout in seconds (default: 180)
#   --dry-run             Simulate actions without modifying system state
#   --help, -h            Show help message

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TEMPLATE_DIR="${PROJECT_ROOT}/config/network/wireguard"
ETC_WG_DIR="/etc/wireguard"

# Terminal Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# Default Parameters
INTERFACE="wg0"
CONFIG_FILE=""
TEMPLATE_TYPE="client"
WATCHDOG_THRESHOLD=180
DRY_RUN=0
COMMAND=""

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

show_help() {
    cat << EOF
MAYOTIX OS Kernel WireGuard CLI Management Utility

Usage:
  manage-wireguard.sh <command> [options]

Commands:
  generate-keys              Generate Curve25519 private key, public key, and optional PSK
  create-profile             Generate profile configuration from local template
  up | start                 Bring up specified WireGuard interface
  down | stop                Bring down specified WireGuard interface
  restart                    Restart specified WireGuard interface
  status                     Display active interface statistics, peers, and routes
  watchdog                   Inspect peer handshakes and auto-reconnect if tunnel dropped
  list                       List active profiles and template files
  verify                     Perform system readiness checks for Kernel WireGuard

Options:
  -i, --interface NAME       WireGuard interface name (default: wg0)
  -c, --config FILE          Path to WireGuard configuration file
  -t, --template TYPE        Template type: client, psk, pinned (default: client)
  -s, --threshold SECONDS    Watchdog handshake threshold in seconds (default: 180)
      --dry-run              Simulate commands without making system changes
  -h, --help                 Display this help menu
EOF
}

# Parse Command Line Arguments
parse_args() {
    if [[ $# -eq 0 ]]; then
        show_help
        exit 0
    fi

    COMMAND="$1"
    shift

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -i|--interface)
                INTERFACE="$2"
                shift 2
                ;;
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -t|--template)
                TEMPLATE_TYPE="$2"
                shift 2
                ;;
            -s|--threshold)
                WATCHDOG_THRESHOLD="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=1
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown argument: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Default CONFIG_FILE if not provided
    if [[ -z "$CONFIG_FILE" ]]; then
        CONFIG_FILE="${ETC_WG_DIR}/${INTERFACE}.conf"
    fi
}

# Verify Kernel Module Availability
check_kernel_module() {
    log_info "Checking kernel module support for WireGuard..."
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log_success "[DRY-RUN] Kernel module 'wireguard' check simulated"
        return 0
    fi

    if lsmod | grep -q "^wireguard" || [[ -d "/sys/module/wireguard" ]]; then
        log_success "Kernel WireGuard module is active/loaded"
        return 0
    elif modprobe wireguard >/dev/null 2>&1; then
        log_success "Kernel WireGuard module successfully loaded via modprobe"
        return 0
    else
        log_warn "Kernel WireGuard module not detected; checking if wg tool is available"
        if command -v wg >/dev/null 2>&1; then
            log_info "wg userspace/kernel utility is available"
            return 0
        else
            log_error "Neither wireguard kernel module nor wg tool is installed"
            return 1
        fi
    fi
}

# Command: generate-keys
cmd_generate_keys() {
    log_info "Generating WireGuard Curve25519 Keypair & Pre-shared Key with strict 0600 permissions..."

    local target_dir
    target_dir="$(dirname "$CONFIG_FILE")"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        log_success "[DRY-RUN] umask 077 set"
        log_success "[DRY-RUN] Generated Private Key:  [SIMULATED_PRIVATE_KEY_32BYTES_BASE64=]"
        log_success "[DRY-RUN] Derived Public Key:    [SIMULATED_PUBLIC_KEY_32BYTES_BASE64=]"
        log_success "[DRY-RUN] Generated PSK Key:     [SIMULATED_PRESHARED_KEY_32BYTES_BASE64=]"
        return 0
    fi

    # Check for wg tool
    if ! command -v wg >/dev/null 2>&1; then
        log_error "'wg' binary is missing. Install wireguard-tools."
        exit 1
    fi

    # Enforce strict umask 077 for process key creation
    umask 077

    local privkey pubkey psk
    privkey=$(wg genkey)
    pubkey=$(echo "$privkey" | wg pubkey)
    psk=$(wg genpsk)

    echo -e "${BOLD}--- WireGuard Cryptographic Key Material ---${NC}"
    echo -e "Private Key (0600): ${privkey}"
    echo -e "Public Key:         ${pubkey}"
    echo -e "Pre-Shared Key:     ${psk}"
    echo -e "${BOLD}--------------------------------------------${NC}"

    log_success "Key material generated successfully under umask 077."
}

# Command: create-profile
cmd_create_profile() {
    log_info "Creating WireGuard profile from template '${TEMPLATE_TYPE}' -> '${CONFIG_FILE}'..."

    local template_file="${TEMPLATE_DIR}/wg0-${TEMPLATE_TYPE}.conf.template"
    if [[ ! -f "$template_file" ]]; then
        log_error "Template file not found: ${template_file}"
        log_info "Available templates in ${TEMPLATE_DIR}:"
        ls -1 "${TEMPLATE_DIR}"/*.template 2>/dev/null || true
        exit 1
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
        log_success "[DRY-RUN] Would interpolate '${template_file}' into '${CONFIG_FILE}'"
        log_success "[DRY-RUN] Would apply permissions: chmod 0600 ${CONFIG_FILE}"
        return 0
    fi

    # Generate keys dynamically for interpolation
    umask 077
    local privkey pubkey psk
    if command -v wg >/dev/null 2>&1; then
        privkey=$(wg genkey)
        pubkey="<REPLACE_WITH_SERVER_PUBLIC_KEY>"
        psk=$(wg genpsk)
    else
        privkey="<REPLACE_WITH_CLIENT_PRIVATE_KEY>"
        pubkey="<REPLACE_WITH_SERVER_PUBLIC_KEY>"
        psk="<REPLACE_WITH_PRESHARED_KEY>"
    fi

    local target_dir
    target_dir="$(dirname "$CONFIG_FILE")"
    if [[ ! -d "$target_dir" ]]; then
        mkdir -p "$target_dir"
        chmod 0700 "$target_dir"
    fi

    sed -e "s|{{CLIENT_PRIVATE_KEY}}|${privkey}|g" \
        -e "s|{{SERVER_PUBLIC_KEY}}|${pubkey}|g" \
        -e "s|{{PRESHARED_KEY}}|${psk}|g" \
        -e "s|{{CLIENT_IPV4_ADDRESS}}|10.66.66.2|g" \
        -e "s|{{CLIENT_IPV6_ADDRESS}}|fd42:42:42::2|g" \
        -e "s|{{SERVER_ENDPOINT_IP}}|198.51.100.1|g" \
        -e "s|{{SERVER_ENDPOINT_PORT}}|51820|g" \
        "$template_file" > "$CONFIG_FILE"

    chmod 0600 "$CONFIG_FILE"
    log_success "Profile created at '${CONFIG_FILE}' with mode 0600"
}

# Command: up / start
cmd_up() {
    log_info "Bringing up WireGuard interface '${INTERFACE}' using config '${CONFIG_FILE}'..."

    check_kernel_module || true

    if [[ "$DRY_RUN" -eq 1 ]]; then
        log_success "[DRY-RUN] Executing: wg-quick up ${CONFIG_FILE}"
        return 0
    fi

    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Profile configuration file missing: ${CONFIG_FILE}"
        exit 1
    fi

    # Verify file permissions
    local perms
    perms=$(stat -c "%a" "$CONFIG_FILE" 2>/dev/null || stat -f "%Lp" "$CONFIG_FILE" 2>/dev/null || echo "0600")
    if [[ "$perms" != "600" && "$perms" != "400" ]]; then
        log_warn "Insecure permissions detected on ${CONFIG_FILE} (${perms}). Fixing to 0600..."
        chmod 0600 "$CONFIG_FILE"
    fi

    if command -v wg-quick >/dev/null 2>&1; then
        wg-quick up "$CONFIG_FILE"
        log_success "WireGuard interface '${INTERFACE}' brought up successfully"
    else
        log_error "'wg-quick' binary not found. Unable to bring up interface."
        exit 1
    fi
}

# Command: down / stop
cmd_down() {
    log_info "Bringing down WireGuard interface '${INTERFACE}'..."

    if [[ "$DRY_RUN" -eq 1 ]]; then
        log_success "[DRY-RUN] Executing: wg-quick down ${CONFIG_FILE}"
        return 0
    fi

    if command -v wg-quick >/dev/null 2>&1; then
        if wg-quick down "$CONFIG_FILE" 2>/dev/null || wg-quick down "$INTERFACE" 2>/dev/null; then
            log_success "WireGuard interface '${INTERFACE}' brought down successfully"
        else
            log_warn "Interface '${INTERFACE}' was not active or down command reported warning"
        fi
    else
        log_error "'wg-quick' binary not found."
        exit 1
    fi
}

# Command: restart
cmd_restart() {
    log_info "Restarting WireGuard interface '${INTERFACE}'..."
    cmd_down || true
    sleep 1
    cmd_up
}

# Command: status
cmd_status() {
    log_info "Querying WireGuard status for interface '${INTERFACE}'..."

    if [[ "$DRY_RUN" -eq 1 ]]; then
        log_success "[DRY-RUN] Querying: wg show ${INTERFACE}"
        log_success "[DRY-RUN] Querying: ip route show dev ${INTERFACE}"
        return 0
    fi

    if command -v wg >/dev/null 2>&1; then
        echo -e "${BOLD}=== WireGuard Interface Status ===${NC}"
        if wg show "$INTERFACE" 2>/dev/null; then
            echo ""
        else
            log_warn "Interface '${INTERFACE}' is currently DOWN or inactive."
        fi
    else
        log_error "'wg' tool is not available."
    fi

    echo -e "${BOLD}=== Active Tunnel Routing ===${NC}"
    if command -v ip >/dev/null 2>&1; then
        ip route show dev "$INTERFACE" 2>/dev/null || echo "No active routes for dev ${INTERFACE}"
    fi

    echo -e "${BOLD}=== Encrypted DNS Resolution Status ===${NC}"
    if command -v resolvectl >/dev/null 2>&1; then
        resolvectl status "$INTERFACE" 2>/dev/null || resolvectl status 2>/dev/null | grep -A 8 "Global" || true
    fi
}

# Command: watchdog
cmd_watchdog() {
    log_info "Executing WireGuard Tunnel Watchdog for interface '${INTERFACE}' (Threshold: ${WATCHDOG_THRESHOLD}s)..."

    if [[ "$DRY_RUN" -eq 1 ]]; then
        log_success "[DRY-RUN] Handshake check simulated for interface '${INTERFACE}'"
        log_success "[DRY-RUN] Threshold: ${WATCHDOG_THRESHOLD} seconds"
        return 0
    fi

    if ! command -v wg >/dev/null 2>&1; then
        log_error "'wg' utility unavailable. Cannot inspect handshakes."
        exit 1
    fi

    # Check if interface exists in kernel
    if ! wg show "$INTERFACE" >/dev/null 2>&1; then
        log_warn "Interface '${INTERFACE}' is inactive. Attempting automatic connection bring-up..."
        if [[ -f "$CONFIG_FILE" ]]; then
            cmd_up
            return 0
        else
            log_error "No config file found at '${CONFIG_FILE}'. Watchdog cannot bring up tunnel."
            exit 1
        fi
    fi

    # Fetch latest handshake epoch timestamp
    local latest_handshake current_epoch handshake_age
    latest_handshake=$(wg show "$INTERFACE" latest-handshakes 2>/dev/null | awk '{print $2}' | sort -nr | head -n 1 || echo "0")

    if [[ -z "$latest_handshake" || "$latest_handshake" -eq 0 ]]; then
        log_warn "No active handshake recorded for peer on interface '${INTERFACE}'."
        log_info "Initiating automatic tunnel restart..."
        cmd_restart
        return 0
    fi

    current_epoch=$(date +%s)
    handshake_age=$((current_epoch - latest_handshake))

    log_info "Interface '${INTERFACE}' latest handshake age: ${handshake_age} seconds"

    if [[ "$handshake_age" -gt "$WATCHDOG_THRESHOLD" ]]; then
        log_warn "Handshake age (${handshake_age}s) exceeds threshold (${WATCHDOG_THRESHOLD}s)."
        log_info "Re-keying / restarting tunnel interface '${INTERFACE}'..."
        cmd_restart
        log_success "Watchdog restart completed."
    else
        log_success "Tunnel '${INTERFACE}' is healthy (handshake age ${handshake_age}s <= ${WATCHDOG_THRESHOLD}s)."
    fi
}

# Command: list
cmd_list() {
    log_info "Scanning for installed WireGuard profiles and templates..."

    echo -e "${BOLD}=== WireGuard Templates (${TEMPLATE_DIR}) ===${NC}"
    if [[ -d "$TEMPLATE_DIR" ]]; then
        ls -la "$TEMPLATE_DIR"/*.template 2>/dev/null || echo "No templates found."
    fi

    echo -e "${BOLD}=== System Profiles (${ETC_WG_DIR}) ===${NC}"
    if [[ -d "$ETC_WG_DIR" ]]; then
        ls -la "$ETC_WG_DIR"/*.conf 2>/dev/null || echo "No system profiles found in ${ETC_WG_DIR}."
    else
        echo "Directory ${ETC_WG_DIR} does not exist."
    fi
}

# Command: verify
cmd_verify() {
    log_info "Running sanity verification for WireGuard subsystem..."

    check_kernel_module || true

    log_info "Checking tool binaries..."
    for tool in wg wg-quick ip resolvectl iptables; do
        if command -v "$tool" >/dev/null 2>&1; then
            log_success "Binary '${tool}' is available: $(command -v "$tool")"
        else
            log_warn "Binary '${tool}' is NOT available"
        fi
    done

    log_info "Checking template files..."
    for t in client psk pinned; do
        local tf="${TEMPLATE_DIR}/wg0-${t}.conf.template"
        if [[ -f "$tf" ]]; then
            log_success "Template 'wg0-${t}.conf.template' present"
        else
            log_error "Missing template 'wg0-${t}.conf.template'"
        fi
    done

    log_success "Sanity check completed."
}

# Main Dispatcher
main() {
    parse_args "$@"

    case "$COMMAND" in
        generate-keys)
            cmd_generate_keys
            ;;
        create-profile)
            cmd_create_profile
            ;;
        up|start)
            cmd_up
            ;;
        down|stop)
            cmd_down
            ;;
        restart)
            cmd_restart
            ;;
        status)
            cmd_status
            ;;
        watchdog)
            cmd_watchdog
            ;;
        list)
            cmd_list
            ;;
        verify)
            cmd_verify
            ;;
        *)
            log_error "Unknown command: ${COMMAND}"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
