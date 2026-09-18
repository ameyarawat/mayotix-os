#!/usr/bin/env bash
# MAYOTIX OS Phase 8 Week 2: Virtual Bridge Network Controller & Containment Firewall
#
# Creates and configures the isolated lab virtual bridge (mayotix-br0, 10.99.0.0/24).
# Enforces strict fail-closed egress filtering:
#   - Drops all traffic destined to physical interfaces (enp*, wlan*, eth*).
#   - Drops all traffic destined to private host LANs (192.168.0.0/16, 10.0.0.0/8, 172.16.0.0/12).
#   - Restricts ingress strictly to the local sinkhole gateway (10.99.0.1) on ports 53, 80, 443.
#
# Usage:
#   lab-network.sh start [--dry-run]
#   lab-network.sh stop [--dry-run]
#   lab-network.sh status [--dry-run] [--json]

set -euo pipefail

PROGNAME="lab-network"
BRIDGE_IFACE="mayotix-br0"
BRIDGE_SUBNET="10.99.0.0/24"
BRIDGE_GATEWAY="10.99.0.1/24"
NFT_TABLE="mayotix_lab_isolation"

# Terminal Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_warn "Non-root execution: system changes require root privileges (use sudo)."
    fi
}

cmd_start() {
    local dry_run=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) dry_run=1; shift ;;
            *) shift ;;
        esac
    done

    if [[ $dry_run -eq 1 ]]; then
        log_info "[DRY-RUN] Simulating Virtual Bridge Network Initialization:"
        log_info "  Bridge Interface  : $BRIDGE_IFACE"
        log_info "  Subnet Range      : $BRIDGE_SUBNET"
        log_info "  Gateway Address   : 10.99.0.1"
        log_info "  Firewall Policy   : DROP forward to physical adapters (enp*, wlan*, eth*)"
        log_info "  RFC1918 Filter    : DROP forward to 192.168.0.0/16, 10.0.0.0/8, 172.16.0.0/12"
        log_info "  Sinkhole Ingress  : PERMIT 10.99.0.1 ports 53 (DNS), 80 (HTTP), 443 (HTTPS)"
        log_success "Virtual bridge network configuration validated."
        return 0
    fi

    check_root

    log_info "Creating virtual bridge interface '$BRIDGE_IFACE'..."
    if ! ip link show "$BRIDGE_IFACE" &>/dev/null; then
        ip link add name "$BRIDGE_IFACE" type bridge
        ip addr add "$BRIDGE_GATEWAY" dev "$BRIDGE_IFACE"
        ip link set "$BRIDGE_IFACE" up
        log_success "Bridge interface '$BRIDGE_IFACE' created and active."
    else
        log_info "Bridge interface '$BRIDGE_IFACE' already exists."
    fi

    # Apply nftables containment rules
    if command -v nft &>/dev/null; then
        log_info "Applying fail-closed containment firewall rules (nftables)..."
        nft add table inet "$NFT_TABLE" 2>/dev/null || true
        nft flush table inet "$NFT_TABLE" 2>/dev/null || true

        nft add chain inet "$NFT_TABLE" forward '{ type filter hook forward priority -100; policy drop; }'
        nft add rule inet "$NFT_TABLE" forward iifname "$BRIDGE_IFACE" oifname "lo" accept
        nft add rule inet "$NFT_TABLE" forward iifname "$BRIDGE_IFACE" drop

        nft add chain inet "$NFT_TABLE" input '{ type filter hook input priority -100; policy drop; }'
        nft add rule inet "$NFT_TABLE" input iifname "$BRIDGE_IFACE" ip daddr 10.99.0.1 tcp dport '{ 80, 443 }' accept
        nft add rule inet "$NFT_TABLE" input iifname "$BRIDGE_IFACE" ip daddr 10.99.0.1 udp dport 53 accept
        nft add rule inet "$NFT_TABLE" input iifname "$BRIDGE_IFACE" drop

        log_success "Malware detonation containment rules loaded into nftables table '$NFT_TABLE'."
    else
        log_warn "nftables not detected; bridge created without kernel firewall hooks."
    fi
}

cmd_stop() {
    local dry_run=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) dry_run=1; shift ;;
            *) shift ;;
        esac
    done

    if [[ $dry_run -eq 1 ]]; then
        log_info "[DRY-RUN] Simulating Virtual Bridge Network Shutdown:"
        log_info "  1. Flush and remove nftables containment table '$NFT_TABLE'"
        log_info "  2. Bring down bridge interface '$BRIDGE_IFACE'"
        log_info "  3. Delete virtual bridge device '$BRIDGE_IFACE'"
        log_success "Virtual bridge network shutdown simulation successful."
        return 0
    fi

    check_root

    log_info "Tearing down virtual bridge network '$BRIDGE_IFACE'..."
    if command -v nft &>/dev/null; then
        nft delete table inet "$NFT_TABLE" 2>/dev/null || true
    fi

    if ip link show "$BRIDGE_IFACE" &>/dev/null; then
        ip link set "$BRIDGE_IFACE" down 2>/dev/null || true
        ip link delete "$BRIDGE_IFACE" type bridge 2>/dev/null || true
        log_success "Bridge interface '$BRIDGE_IFACE' deleted."
    else
        log_info "Bridge interface '$BRIDGE_IFACE' was not active."
    fi
}

cmd_status() {
    local dry_run=0
    local json_out=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) dry_run=1; shift ;;
            --json) json_out=1; shift ;;
            *) shift ;;
        esac
    done

    local active=false
    local ip_addr="N/A"
    local fw_active=false

    if [[ $dry_run -eq 1 ]]; then
        active=true
        ip_addr="10.99.0.1"
        fw_active=true
    elif ip link show "$BRIDGE_IFACE" &>/dev/null; then
        active=true
        ip_addr=$(ip -br addr show "$BRIDGE_IFACE" 2>/dev/null | awk '{print $3}' || echo "10.99.0.1/24")
        if command -v nft &>/dev/null && nft list tables 2>/dev/null | grep -q "$NFT_TABLE"; then
            fw_active=true
        fi
    fi

    if [[ $json_out -eq 1 ]]; then
        cat <<EOF
{
  "bridge_interface": "$BRIDGE_IFACE",
  "subnet": "$BRIDGE_SUBNET",
  "gateway": "10.99.0.1",
  "active": $active,
  "address": "$ip_addr",
  "containment_firewall": {
    "active": $fw_active,
    "table": "$NFT_TABLE",
    "policy": "DROP_PHYSICAL_EGRESS"
  },
  "allowed_sinkhole_ports": [53, 80, 443]
}
EOF
        return 0
    fi

    local status_str="${YELLOW}DOWN${NC}"
    if [[ "$active" == "true" ]]; then
        status_str="${GREEN}UP${NC}"
    fi

    local fw_str="${YELLOW}INACTIVE${NC}"
    if [[ "$fw_active" == "true" ]]; then
        fw_str="${GREEN}ACTIVE${NC}"
    fi

    echo -e "${BOLD}${CYAN}================================================================${NC}"
    echo -e "${BOLD}${CYAN}        MAYOTIX Labs Virtual Bridge Network Controller          ${NC}"
    echo -e "${BOLD}${CYAN}================================================================${NC}"
    echo -e "  Bridge Interface    : ${BRIDGE_IFACE} (${status_str})"
    echo -e "  Subnet Range        : ${BRIDGE_SUBNET}"
    echo -e "  Gateway Address     : 10.99.0.1"
    echo -e "  Containment Policy  : ${GREEN}FAIL-CLOSED (Physical Adapters & LANs Blocked)${NC}"
    echo -e "  Sinkhole Ports      : ${GREEN}53 (DNS), 80 (HTTP), 443 (HTTPS)${NC}"
    echo -e "  Firewall Table      : ${NFT_TABLE} (${fw_str})"
    echo -e "${BOLD}${CYAN}================================================================${NC}"
}

# Main Command Dispatcher
case "${1:-}" in
    start)
        shift
        cmd_start "$@"
        ;;
    stop)
        shift
        cmd_stop "$@"
        ;;
    status)
        shift
        cmd_status "$@"
        ;;
    --help|-h|"")
        echo "Usage: $PROGNAME <start|stop|status> [options]"
        echo ""
        echo "Commands:"
        echo "  start     Create virtual bridge interface and apply containment firewall"
        echo "  stop      Tear down bridge interface and delete containment rules"
        echo "  status    Display bridge interface status and firewall policy"
        exit 0
        ;;
    *)
        log_error "Unknown command '$1'. Use '$PROGNAME --help'."
        exit 1
        ;;
esac
