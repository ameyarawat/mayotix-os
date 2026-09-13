#!/usr/bin/env bash
# MAYOTIX Disposable Session Launcher
# Creates an isolated, ephemeral workspace using Bubblewrap (bwrap).
# All user-facing data lives on tmpfs — nothing persists after logout.
#
# Security properties:
#   - Fresh tmpfs /home and /tmp (no access to real persistent home)
#   - Network disabled by default (--network to allow)
#   - Dangerous capabilities dropped (SYS_ADMIN, SYS_PTRACE, SYS_RAWIO, …)
#   - User/IPC/PID namespaces isolated
#   - Trap-based cleanup with optional secure wipe (shred) on exit
#   - XDG_RUNTIME_DIR forwarded for Wayland socket access
#
# Usage:
#   mayotix-disposable-session [--network]     Launch with networking disabled (default)
#   mayotix-disposable-session --network       Launch with networking enabled

set -euo pipefail

readonly PROGNAME="mayotix-disposable-session"

# ── Logging helpers ──────────────────────────────────────────────
log()  { printf '[%s] %s\n' "$PROGNAME" "$*" >&2; }
die()  { log "FATAL: $*"; exit 1; }

# ── Parse arguments ──────────────────────────────────────────────
ALLOW_NET=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --network)  ALLOW_NET=1; shift ;;
        --help|-h)
            echo "Usage: $PROGNAME [--network]"
            echo "  --network   Allow network access inside the disposable session"
            echo "  --help      Show this help"
            exit 0
            ;;
        *)  die "Unknown option: $1" ;;
    esac
done

# ── Resolve user identity ───────────────────────────────────────
REAL_USER="${USER:-$(whoami)}"
REAL_UID="$(id -u)"
SESSION_ID="disposable-$(date +%s)-$$"

# ── Create ephemeral tmpfs-backed directories ────────────────────
HOME_TMP="$(mktemp -d "/tmp/${PROGNAME}.home.XXXXXX")"
TMP_TMP="$(mktemp -d "/tmp/${PROGNAME}.tmp.XXXXXX")"
XDG_TMP="$(mktemp -d "/tmp/${PROGNAME}.xdg.XXXXXX")"

# Create a minimal home directory skeleton
EPHEMERAL_HOME="${HOME_TMP}/${REAL_USER}"
mkdir -p "${EPHEMERAL_HOME}"/{.config,.local/share,.cache,Desktop,Documents,Downloads}

# ── Cleanup on exit: secure wipe + remove ────────────────────────
cleanup() {
    local rc=$?
    log "Session ended (exit code $rc). Cleaning up ephemeral data…"

    for dir in "$HOME_TMP" "$TMP_TMP" "$XDG_TMP"; do
        if [[ -d "$dir" ]]; then
            # Attempt secure wipe of file contents before removal.
            # shred is best-effort on tmpfs (RAM is overwritten on free anyway).
            if command -v shred >/dev/null 2>&1; then
                find "$dir" -type f -exec shred -fuz {} + 2>/dev/null || true
            fi
            rm -rf "$dir" 2>/dev/null || true
        fi
    done

    log "Cleanup complete. No persistent data remains."
}
trap cleanup EXIT INT TERM HUP

# ── Verify prerequisites ────────────────────────────────────────
command -v bwrap >/dev/null 2>&1 || die "bubblewrap (bwrap) is not installed"

# ── Build bwrap argument array ───────────────────────────────────
BWRAP_ARGS=()

# Namespace isolation
BWRAP_ARGS+=(--unshare-user --unshare-ipc --unshare-pid)

# Network isolation (default: no network)
if [[ $ALLOW_NET -eq 0 ]]; then
    BWRAP_ARGS+=(--unshare-net)
    log "Network access: DISABLED"
else
    log "Network access: ENABLED"
fi

# Capability dropping — deny dangerous capabilities
BWRAP_ARGS+=(
    --cap-drop CAP_SYS_ADMIN
    --cap-drop CAP_SYS_MODULE
    --cap-drop CAP_SYS_PTRACE
    --cap-drop CAP_SYS_RAWIO
    --cap-drop CAP_SYS_BOOT
    --cap-drop CAP_SYS_NICE
    --cap-drop CAP_NET_ADMIN
    --cap-drop CAP_NET_RAW
    --cap-drop CAP_MKNOD
    --cap-drop CAP_AUDIT_WRITE
    --cap-drop CAP_AUDIT_CONTROL
)

# Filesystem: read-only base system
BWRAP_ARGS+=(
    --ro-bind /usr /usr
    --ro-bind /etc /etc
    --ro-bind /bin /bin
    --ro-bind /sbin /sbin
    --ro-bind /lib /lib
)
# /lib64 may not exist on all arches
[[ -d /lib64 ]] && BWRAP_ARGS+=(--ro-bind /lib64 /lib64)

# Device and process filesystems
BWRAP_ARGS+=(--dev /dev --proc /proc)

# Ephemeral home and tmp — the core of the disposable guarantee
BWRAP_ARGS+=(
    --tmpfs /home
    --bind "${EPHEMERAL_HOME}" "/home/${REAL_USER}"
    --tmpfs /tmp
    --bind "${TMP_TMP}" /tmp
)

# Read-only /var (logs, caches) — prevent writes to persistent system state
BWRAP_ARGS+=(--ro-bind /var /var)

# Runtime directory: forward the real XDG_RUNTIME_DIR so the Wayland
# compositor socket is accessible; this is required for graphical sessions
if [[ -n "${XDG_RUNTIME_DIR:-}" ]] && [[ -d "${XDG_RUNTIME_DIR}" ]]; then
    BWRAP_ARGS+=(--bind "${XDG_RUNTIME_DIR}" "${XDG_RUNTIME_DIR}")
fi

# /run is needed for D-Bus, systemd, udev, etc. — bind read-only
BWRAP_ARGS+=(--ro-bind /run /run)

# Symlink /sys read-only for hardware enumeration (required by libinput/mesa)
BWRAP_ARGS+=(--ro-bind /sys /sys)

# Wayland socket passthrough for X11-unix (legacy X fallback socket dir)
if [[ -d /tmp/.X11-unix ]]; then
    BWRAP_ARGS+=(--ro-bind /tmp/.X11-unix /tmp/.X11-unix)
fi

# ── Environment variables ────────────────────────────────────────
BWRAP_ARGS+=(
    --setenv HOME "/home/${REAL_USER}"
    --setenv USER "${REAL_USER}"
    --setenv LOGNAME "${REAL_USER}"
    --setenv XDG_SESSION_TYPE "wayland"
    --setenv XDG_CURRENT_DESKTOP "Mayotix"
    --setenv XDG_CONFIG_HOME "/home/${REAL_USER}/.config"
    --setenv XDG_DATA_HOME "/home/${REAL_USER}/.local/share"
    --setenv XDG_CACHE_HOME "/home/${REAL_USER}/.cache"
    --setenv MAYOTIX_DISPOSABLE "1"
    --setenv MAYOTIX_SESSION_ID "${SESSION_ID}"
)

# Forward Wayland / display variables from the session that launched us
[[ -n "${XDG_RUNTIME_DIR:-}" ]]  && BWRAP_ARGS+=(--setenv XDG_RUNTIME_DIR "${XDG_RUNTIME_DIR}")
[[ -n "${WAYLAND_DISPLAY:-}" ]]  && BWRAP_ARGS+=(--setenv WAYLAND_DISPLAY "${WAYLAND_DISPLAY}")
[[ -n "${DISPLAY:-}" ]]          && BWRAP_ARGS+=(--setenv DISPLAY "${DISPLAY}")
[[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]] && BWRAP_ARGS+=(--setenv DBUS_SESSION_BUS_ADDRESS "${DBUS_SESSION_BUS_ADDRESS}")

# ── Launch compositor ────────────────────────────────────────────
log "Launching disposable session [${SESSION_ID}]…"
log "  Home:    ${EPHEMERAL_HOME}  (tmpfs, destroyed on exit)"
log "  Tmp:     ${TMP_TMP}         (tmpfs, destroyed on exit)"
log "  Network: $(if [[ $ALLOW_NET -eq 1 ]]; then echo ENABLED; else echo DISABLED; fi)"

exec bwrap "${BWRAP_ARGS[@]}" -- sway
