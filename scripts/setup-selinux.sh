#!/bin/bash
# MAYOTIX OS SELinux Setup Script
#
# Sets SELinux to enforcing mode and loads the MAYOTIX policy
#
# Usage:
#   sudo ./scripts/setup-selinux.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SELINUX_DIR="${PROJECT_ROOT}/security/selinux"
BUILD_DIR="${PROJECT_ROOT}/build/selinux"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root (use sudo)"
fi

# Check SELinux tools
check_selinux_tools() {
    log_info "Checking SELinux tools..."
    local required_tools=("semanage" "setenforce" "getenforce" "semodule")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            log_error "Required tool not found: $tool"
        fi
    done
    log_success "All SELinux tools available"
}

# Compile SELinux policies if needed
compile_policies() {
    log_info "Compiling SELinux policies..."
    if [[ ! -d "$BUILD_DIR" ]]; then
        mkdir -p "$BUILD_DIR"
    fi
    # Use the existing compile script
    "${SCRIPT_DIR}/compile-selinux.sh"
    log_success "SELinux policies compiled"
}

# Set SELinux to enforcing mode
set_enforcing() {
    log_info "Setting SELinux to enforcing mode..."
    if [[ "$(getenforce)" != "Enforcing" ]]; then
        setenforce 1
        log_success "SELinux set to enforcing mode"
    else
        log_info "SELinux is already in enforcing mode"
    fi
    # Also set in config file for persistence
    if [[ -f "/etc/selinux/config" ]]; then
        sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
        log_success "Updated /etc/selinux/config to enforcing"
    fi
}

# Load MAYOTIX SELinux policy
load_policy() {
    log_info "Loading MAYOTIX SELinux policy..."
    local pp_file="${BUILD_DIR}/mayotix.pp"
    if [[ ! -f "$pp_file" ]]; then
        log_error "Policy package not found: $pp_file"
    fi
    if semodule -i "$pp_file"; then
        log_success "MAYOTIX SELinux policy loaded"
    else
        log_error "Failed to load MAYOTIX SELinux policy"
    fi
    # Verify policy is loaded
    if semodule -l | grep -q mayotix; then
        log_success "MAYOTIX policy verified in loaded module list"
    else
        log_warn "MAYOTIX policy not found in loaded module list"
    fi
}

# Verify SELinux status and policy
verify_setup() {
    log_info "Verifying SELinux setup..."
    log_info "Current SELinux mode: $(getenforce)"
    log_info "Loaded MAYOTIX policy: $(semodule -l | grep mayotix || echo 'Not found')"
    # Check if policy is active (optional: check avc stats)
    log_success "SELinux setup verification complete"
}

# Main
main() {
    log_info "MAYOTIX OS SELinux Setup"
    check_selinux_tools
    compile_policies
    set_enforcing
    load_policy
    verify_setup
    log_success "SELinux setup complete"
}

main "$@"