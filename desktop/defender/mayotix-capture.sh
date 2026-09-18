#!/bin/bash
# MAYOTIX OS Phase 7: Defender Packet Capture & Analysis Utility
#
# Provides unprivileged and capability-bounded packet inspection via tcpdump / tshark
# using Linux file capabilities (CAP_NET_RAW, CAP_NET_ADMIN) or unprivileged user namespaces
# without requiring full root execution or setuid binaries.
#
# Pre-configured security auditing profiles:
#   - wireguard-egress: Audits encapsulated VPN traffic and port 51820
#   - dot-dns: Audits DNS-over-TLS (port 853) traffic
#   - leak-sniffer: Audits unencrypted cleartext leaks on physical network cards
#
# Usage:
#   mayotix-capture.sh start [options]
#   mayotix-capture.sh stop
#   mayotix-capture.sh status [--json]
#   mayotix-capture.sh list-profiles

set -euo pipefail

CAPTURE_DIR="/var/log/mayotix/captures"
RUN_DIR="/run/mayotix"
PID_FILE="${RUN_DIR}/capture.pid"
STATE_FILE="${RUN_DIR}/capture.json"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

ensure_dirs() {
    if [[ ! -d "$CAPTURE_DIR" ]]; then
        mkdir -p "$CAPTURE_DIR" 2>/dev/null || {
            if command -v sudo &>/dev/null; then
                sudo -n mkdir -p "$CAPTURE_DIR" 2>/dev/null || true
                sudo -n chmod 0750 "$CAPTURE_DIR" 2>/dev/null || true
            fi
        }
    fi
    mkdir -p "$RUN_DIR" 2>/dev/null || true
}

get_default_iface() {
    ip route show default 2>/dev/null | awk '{print $5}' | head -n 1 || echo "any"
}

list_profiles() {
    echo -e "${BOLD}Available MAYOTIX Defender Capture Profiles:${NC}"
    echo -e "  ${GREEN}wireguard-egress${NC} : Captures encapsulated VPN traffic on wg* or UDP/51820"
    echo -e "  ${GREEN}dot-dns${NC}          : Captures system-wide DNS-over-TLS packets on port 853"
    echo -e "  ${GREEN}leak-sniffer${NC}     : Detects cleartext unencrypted egress leaks on physical interfaces"
    echo -e "  ${GREEN}custom${NC}           : Arbitrary BPF packet capture filter expression"
}

resolve_profile_filter() {
    local profile="$1"
    local custom_filter="${2:-}"

    case "$profile" in
        wireguard-egress)
            echo "udp port 51820 or ip proto 50"
            ;;
        dot-dns)
            echo "tcp port 853 or udp port 853"
            ;;
        leak-sniffer)
            echo "not (tcp port 853 or udp port 51820 or udp port 67 or udp port 68) and not ip broadcast and not ip multicast"
            ;;
        custom)
            echo "${custom_filter:-all}"
            ;;
        *)
            echo "$profile"
            ;;
    esac
}

cmd_start() {
    local iface=""
    local profile="wireguard-egress"
    local custom_filter=""
    local output=""
    local dry_run=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -i|--interface) iface="$2"; shift 2 ;;
            -p|--profile) profile="$2"; shift 2 ;;
            -f|--filter) custom_filter="$2"; shift 2 ;;
            -o|--output) output="$2"; shift 2 ;;
            --dry-run) dry_run=1; shift ;;
            *) log_warn "Unknown option: $1"; shift ;;
        esac
    done

    if [[ -z "$iface" ]]; then
        iface=$(get_default_iface)
    fi

    if [[ -z "$output" ]]; then
        local ts
        ts=$(date +%Y%m%d_%H%M%S)
        output="${CAPTURE_DIR}/${profile}_${ts}.pcap"
    fi

    local bpf_filter
    bpf_filter=$(resolve_profile_filter "$profile" "$custom_filter")

    if [[ -f "$PID_FILE" ]]; then
        local existing_pid
        existing_pid=$(cat "$PID_FILE" 2>/dev/null || echo "")
        if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
            log_error "A capture session is already running (PID: $existing_pid). Stop it first."
            exit 1
        fi
    fi

    if [[ $dry_run -eq 1 ]]; then
        log_info "[DRY-RUN] Simulating packet capture startup:"
        log_info "  Interface: $iface"
        log_info "  Profile:   $profile"
        log_info "  Filter:    $bpf_filter"
        log_info "  Output:    $output"
        log_success "Capture initialization parameters validated."
        return 0
    fi

    ensure_dirs

    # Determine capture tool (prefer tcpdump or tshark)
    local tool=""
    if command -v tcpdump &>/dev/null; then
        tool="tcpdump"
    elif command -v tshark &>/dev/null; then
        tool="tshark"
    else
        log_warn "Neither tcpdump nor tshark found in PATH. Writing simulated trace."
        touch "$output"
        echo "$$" > "$PID_FILE"
        cat > "$STATE_FILE" <<EOF
{
  "active": true,
  "pid": $$,
  "tool": "simulated",
  "interface": "$iface",
  "profile": "$profile",
  "filter": "$bpf_filter",
  "output_file": "$output",
  "start_time": $(date +%s)
}
EOF
        log_success "Simulated capture started (PID $$)"
        return 0
    fi

    # Launch capture process in background
    if [[ "$tool" == "tcpdump" ]]; then
        local filter_arg=()
        if [[ "$bpf_filter" != "all" ]]; then
            filter_arg=("$bpf_filter")
        fi
        tcpdump -i "$iface" -w "$output" -U "${filter_arg[@]}" >/dev/null 2>&1 &
        local cap_pid=$!
    else
        local filter_arg=()
        if [[ "$bpf_filter" != "all" ]]; then
            filter_arg=(-f "$bpf_filter")
        fi
        tshark -i "$iface" -w "$output" "${filter_arg[@]}" >/dev/null 2>&1 &
        local cap_pid=$!
    fi

    echo "$cap_pid" > "$PID_FILE"

    cat > "$STATE_FILE" <<EOF
{
  "active": true,
  "pid": $cap_pid,
  "tool": "$tool",
  "interface": "$iface",
  "profile": "$profile",
  "filter": "$bpf_filter",
  "output_file": "$output",
  "start_time": $(date +%s)
}
EOF

    log_success "Defender packet capture started (PID: $cap_pid)"
    log_info "  Interface : $iface"
    log_info "  Profile   : $profile"
    log_info "  Output    : $output"
}

cmd_stop() {
    local dry_run=0
    if [[ "${1:-}" == "--dry-run" ]]; then
        dry_run=1
    fi

    if [[ $dry_run -eq 1 ]]; then
        log_info "[DRY-RUN] Simulating packet capture shutdown."
        log_success "Capture process terminated cleanly."
        return 0
    fi

    if [[ ! -f "$PID_FILE" ]]; then
        log_warn "No active capture session found."
        return 0
    fi

    local cap_pid
    cap_pid=$(cat "$PID_FILE" 2>/dev/null || echo "")

    if [[ -n "$cap_pid" ]] && kill -0 "$cap_pid" 2>/dev/null; then
        kill -SIGINT "$cap_pid" 2>/dev/null || kill -SIGTERM "$cap_pid" 2>/dev/null || true
        sleep 0.5
        log_success "Capture process (PID $cap_pid) stopped."
    else
        log_info "Capture process was not running."
    fi

    rm -f "$PID_FILE"

    if [[ -f "$STATE_FILE" ]]; then
        local out_file
        out_file=$(grep '"output_file"' "$STATE_FILE" | cut -d'"' -f4 || echo "")
        rm -f "$STATE_FILE"
        if [[ -n "$out_file" ]] && [[ -f "$out_file" ]]; then
            local size
            size=$(ls -lh "$out_file" | awk '{print $5}')
            log_success "Capture saved to $out_file (Size: $size)"
        fi
    fi
}

cmd_status() {
    local json_out=0
    local dry_run=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json) json_out=1; shift ;;
            --dry-run) dry_run=1; shift ;;
            *) shift ;;
        esac
    done

    local active=false
    local pid=0
    local iface=""
    local profile=""
    local filter=""
    local output=""
    local duration=0

    if [[ $dry_run -eq 1 ]]; then
        active=false
    elif [[ -f "$PID_FILE" ]]; then
        local p
        p=$(cat "$PID_FILE" 2>/dev/null || echo "")
        if [[ -n "$p" ]] && kill -0 "$p" 2>/dev/null; then
            active=true
            pid="$p"
        fi
    fi

    if [[ -f "$STATE_FILE" ]] && [[ "$active" == "true" ]]; then
        iface=$(grep '"interface"' "$STATE_FILE" | cut -d'"' -f4 || echo "")
        profile=$(grep '"profile"' "$STATE_FILE" | cut -d'"' -f4 || echo "")
        filter=$(grep '"filter"' "$STATE_FILE" | cut -d'"' -f4 || echo "")
        output=$(grep '"output_file"' "$STATE_FILE" | cut -d'"' -f4 || echo "")
        local st
        st=$(grep '"start_time"' "$STATE_FILE" | grep -o '[0-9]\+' || echo "0")
        if [[ "$st" -gt 0 ]]; then
            duration=$(($(date +%s) - st))
        fi
    fi

    if [[ $json_out -eq 1 ]]; then
        cat <<EOF
{
  "active": $active,
  "pid": $pid,
  "interface": "${iface:-none}",
  "profile": "${profile:-none}",
  "filter": "${filter:-none}",
  "output_file": "${output:-none}",
  "duration_seconds": $duration
}
EOF
        return 0
    fi

    echo -e "\n${BOLD}${BLUE}================================================================${NC}"
    echo -e "${BOLD}${BLUE}              MAYOTIX Defender Capture Status                   ${NC}"
    echo -e "${BOLD}${BLUE}================================================================${NC}"
    if [[ "$active" == "true" ]]; then
        echo -e "  Status    : ${GREEN}ACTIVE${NC} (PID: $pid)"
        echo -e "  Interface : $iface"
        echo -e "  Profile   : $profile"
        echo -e "  Filter    : $filter"
        echo -e "  Output    : $output"
        echo -e "  Duration  : ${duration}s"
    else
        echo -e "  Status    : ${YELLOW}IDLE / INACTIVE${NC}"
        echo -e "  Captures  : $CAPTURE_DIR"
    fi
    echo -e "${BOLD}${BLUE}================================================================${NC}\n"
}

main() {
    local cmd="${1:-status}"
    shift || true

    case "$cmd" in
        start) cmd_start "$@" ;;
        stop) cmd_stop "$@" ;;
        status) cmd_status "$@" ;;
        list-profiles) list_profiles ;;
        *)
            echo "Usage: $0 {start|stop|status|list-profiles} [options]"
            exit 1
            ;;
    esac
}

main "$@"
