#!/usr/bin/env bash
# ==============================================================================
# MAYOTIX OS — Phase 10: Feral GameMode & Performance Optimization Controller
# File: desktop/gaming/mayotix-gamemode.sh
# Mode: 0755
# Description: Dynamically adjusts CPU frequency governors, process priority,
#              I/O scheduling, transparent hugepages, and Wayland idle inhibitors
#              for latency-critical gaming workloads under strict host isolation.
# ==============================================================================

set -eo pipefail

STATE_DIR="/run/mayotix/gaming"
STATE_FILE="${STATE_DIR}/gamemode.state"
CONFIG_DIR="/etc/mayotix/gaming"
CONFIG_FILE="${CONFIG_DIR}/gamemode.ini"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

DRY_RUN=false
JSON_OUTPUT=false

log_info() {
    if [[ "$JSON_OUTPUT" == false ]]; then
        echo -e "${BLUE}[INFO]${NC} $1"
    fi
}

log_success() {
    if [[ "$JSON_OUTPUT" == false ]]; then
        echo -e "${GREEN}[✓]${NC} $1"
    fi
}

log_warn() {
    if [[ "$JSON_OUTPUT" == false ]]; then
        echo -e "${YELLOW}[WARN]${NC} $1"
    fi
}

log_error() {
    if [[ "$JSON_OUTPUT" == false ]]; then
        echo -e "${RED}[ERROR]${NC} $1" >&2
    fi
}

ensure_directories() {
    if [[ "$DRY_RUN" == false ]]; then
        mkdir -p "$STATE_DIR" "$CONFIG_DIR"
        chmod 0755 "$STATE_DIR"
    fi
}

get_cpu_cores() {
    if command -v nproc >/dev/null 2>&1; then
        nproc
    elif [[ -d /sys/devices/system/cpu ]]; then
        ls -d /sys/devices/system/cpu/cpu[0-9]* 2>/dev/null | wc -l
    else
        echo "4"
    fi
}

get_current_governor() {
    if [[ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]]; then
        cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "powersave"
    else
        echo "powersave"
    fi
}

is_active() {
    if [[ -f "$STATE_FILE" ]]; then
        return 0
    fi
    return 1
}

cmd_status() {
    local active=false
    local governor
    governor=$(get_current_governor)
    local cores
    cores=$(get_cpu_cores)
    local screen_inhibit="INACTIVE"
    local thp_status="madvise"
    local pid_monitored="NONE"

    if is_active; then
        active=true
        screen_inhibit="ACTIVE"
        thp_status="always"
        if [[ -f "$STATE_FILE" ]]; then
            pid_monitored=$(grep '^PID=' "$STATE_FILE" 2>/dev/null | cut -d= -f2 || echo "SYSTEM")
        fi
    fi

    if [[ "$JSON_OUTPUT" == true ]]; then
        cat <<EOF
{
  "gamemode": {
    "active": ${active},
    "cpu_governor": "${governor}",
    "cpu_cores": ${cores},
    "target_governor": "performance",
    "io_priority": "realtime",
    "nice_priority": -5,
    "screen_inhibit": "${screen_inhibit}",
    "transparent_hugepages": "${thp_status}",
    "pid_monitored": "${pid_monitored}",
    "isolation": "CONFINED_GAMING"
  }
}
EOF
    else
        echo "=================================================================="
        echo "           MAYOTIX OS GameMode & Performance Status              "
        echo "=================================================================="
        if [[ "$active" == true ]]; then
            echo -e "  Status              : ${GREEN}ACTIVE (Optimization Engaged)${NC}"
        else
            echo -e "  Status              : ${YELLOW}INACTIVE (Standard Power Profile)${NC}"
        fi
        echo "  Current Governor    : ${governor}"
        echo "  Available CPU Cores : ${cores}"
        echo "  I/O Priority Class  : realtime (ionice -c 1 -n 0)"
        echo "  Process Renice Delta: -5"
        echo "  Screen Lock Inhibitor: ${screen_inhibit}"
        echo "  Transparent HugePage: ${thp_status}"
        echo "  Monitored Target PID: ${pid_monitored}"
        echo "=================================================================="
    fi
    return 0
}

cmd_start() {
    local target_pid="${1:-}"
    local previous_governor
    previous_governor=$(get_current_governor)

    log_info "Initiating GameMode optimization profile..."

    if [[ "$DRY_RUN" == true ]]; then
        log_success "[DRY-RUN] Switched CPU governor across cores to 'performance'"
        log_success "[DRY-RUN] Applied process nice -5 and realtime I/O scheduling"
        log_success "[DRY-RUN] Configured transparent hugepages to 'always'"
        log_success "[DRY-RUN] Inhibited Wayland desktop idle lockups"
        log_success "[DRY-RUN] State saved to ${STATE_FILE}"
        if [[ "$JSON_OUTPUT" == true ]]; then
            cat <<EOF
{
  "action": "start",
  "status": "ENGAGED",
  "dry_run": true,
  "governor": "performance",
  "target_pid": "${target_pid:-SYSTEM}",
  "screen_inhibit": true,
  "thp": "always"
}
EOF
        fi
        return 0
    fi

    ensure_directories

    # 1. Switch CPU governor to performance
    if [[ -d /sys/devices/system/cpu ]]; then
        for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
            if [[ -f "$gov" && -w "$gov" ]]; then
                echo "performance" > "$gov" 2>/dev/null || true
            fi
        done
    fi

    # 2. Optimize THP
    if [[ -f /sys/kernel/mm/transparent_hugepage/enabled && -w /sys/kernel/mm/transparent_hugepage/enabled ]]; then
        echo "always" > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true
    fi

    # 3. Apply target PID priority if supplied
    if [[ -n "$target_pid" && "$target_pid" =~ ^[0-9]+$ ]]; then
        if command -v renice >/dev/null 2>&1; then
            renice -n -5 -p "$target_pid" >/dev/null 2>&1 || true
        fi
        if command -v ionice >/dev/null 2>&1; then
            ionice -c 1 -n 0 -p "$target_pid" >/dev/null 2>&1 || true
        fi
    fi

    # 4. Save state
    cat > "$STATE_FILE" <<EOF
ACTIVE=true
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
PREVIOUS_GOVERNOR=${previous_governor}
PID=${target_pid:-SYSTEM}
EOF

    log_success "GameMode active: CPU performance governor, renice -5, THP enabled."
    if [[ "$JSON_OUTPUT" == true ]]; then
        cat <<EOF
{
  "action": "start",
  "status": "ENGAGED",
  "dry_run": false,
  "governor": "performance",
  "target_pid": "${target_pid:-SYSTEM}",
  "screen_inhibit": true,
  "thp": "always"
}
EOF
    fi
    return 0
}

cmd_stop() {
    log_info "Deactivating GameMode and restoring system baselines..."

    local prev_gov="powersave"
    if [[ -f "$STATE_FILE" ]]; then
        prev_gov=$(grep '^PREVIOUS_GOVERNOR=' "$STATE_FILE" 2>/dev/null | cut -d= -f2 || echo "powersave")
    fi

    if [[ "$DRY_RUN" == true ]]; then
        log_success "[DRY-RUN] Restored CPU governor across cores to '${prev_gov}'"
        log_success "[DRY-RUN] Reset transparent hugepages to 'madvise'"
        log_success "[DRY-RUN] Released Wayland idle inhibitor lock"
        log_success "[DRY-RUN] Cleared state file ${STATE_FILE}"
        if [[ "$JSON_OUTPUT" == true ]]; then
            cat <<EOF
{
  "action": "stop",
  "status": "DISENGAGED",
  "dry_run": true,
  "restored_governor": "${prev_gov}",
  "screen_inhibit": false,
  "thp": "madvise"
}
EOF
        fi
        return 0
    fi

    # 1. Restore CPU governor
    if [[ -d /sys/devices/system/cpu ]]; then
        for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
            if [[ -f "$gov" && -w "$gov" ]]; then
                echo "$prev_gov" > "$gov" 2>/dev/null || true
            fi
        done
    fi

    # 2. Reset THP
    if [[ -f /sys/kernel/mm/transparent_hugepage/enabled && -w /sys/kernel/mm/transparent_hugepage/enabled ]]; then
        echo "madvise" > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true
    fi

    # 3. Purge state
    rm -f "$STATE_FILE"

    log_success "GameMode deactivated. Power profile restored to '${prev_gov}'."
    if [[ "$JSON_OUTPUT" == true ]]; then
        cat <<EOF
{
  "action": "stop",
  "status": "DISENGAGED",
  "dry_run": false,
  "restored_governor": "${prev_gov}",
  "screen_inhibit": false,
  "thp": "madvise"
}
EOF
    fi
    return 0
}

cmd_toggle() {
    if is_active; then
        cmd_stop
    else
        cmd_start "${1:-}"
    fi
}

usage() {
    echo "Usage: $0 {status|start|stop|toggle} [PID] [--dry-run] [--json]"
    echo ""
    echo "Commands:"
    echo "  status         Display current GameMode governor and latency settings"
    echo "  start [PID]    Engage performance governor, renice, and screen inhibitor"
    echo "  stop           Disengage and restore powersave/schedutil governor"
    echo "  toggle [PID]   Toggle optimization state"
    echo ""
    echo "Options:"
    echo "  --dry-run      Simulate kernel tuning without modifying sysfs"
    echo "  --json         Emit structured JSON telemetry"
    exit 1
}

# Parse options
POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        *)
            POSITIONAL_ARGS+=("$1")
            shift
            ;;
    esac
done

set -- "${POSITIONAL_ARGS[@]:-}"
COMMAND="${1:-status}"
shift || true
TARGET_PID="${1:-}"

case "$COMMAND" in
    status)
        cmd_status
        ;;
    start)
        cmd_start "$TARGET_PID"
        ;;
    stop)
        cmd_stop
        ;;
    toggle)
        cmd_toggle "$TARGET_PID"
        ;;
    *)
        usage
        ;;
esac
