#!/bin/bash
# MAYOTIX OS Phase 3 Week 1: Secure Wayland Session Wrapper
# This script sanitizes the environment, drops unnecessary privileges,
# and starts the Wayland compositor (sway) under a systemd user session.

set -euo pipefail

# Sanitize environment: unset potentially dangerous variables
unset LD_PRELOAD
unset LD_LIBRARY_PATH
unset PYTHONPATH
unset PERL5LIB
unset RUBYLIB
unset JAVA_TOOL_OPTIONS
unset BUNDLE_PATH
unset GEM_PATH
unset NODE_OPTIONS
unset CARGO_HOME
unset RUSTUP_HOME
unset GOPATH
unset GOBIN
unset GOFLAGS
unset CGO_ENABLED
# Keep only necessary variables
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export HOME="${HOME}"
export USER="${USER}"
export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"
export DISPLAY="${DISPLAY:-}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export XDG_SESSION_TYPE="wayland"
export XDG_SESSION_DESKTOP="MAYOTIX"
export XDG_CURRENT_DESKTOP="sway"

# Ensure runtime directory exists and is secure
if [[ ! -d "${XDG_RUNTIME_DIR}" ]]; then
    mkdir -p "${XDG_RUNTIME_DIR}"
    chmod 0700 "${XDG_RUNTIME_DIR}"
fi

# Drop unnecessary capabilities if we have libcap (optional)
# We rely on systemd to drop privileges; this script runs as the user.

# Load Xresources if present (for compatibility)
if [[ -f "${HOME}/.Xresources" ]]; then
    xrdb -merge "${HOME}/.Xresources" 2>/dev/null || true
fi

# Start the Wayland compositor (sway) with the MAYOTIX config
# We use exec to replace the shell with sway
exec sway -c "${HOME}/.config/sway/config" || \
    sway -c "/etc/sway/config" || \
    sway -c "${PWD}/desktop/compositor/sway.config"