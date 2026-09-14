#!/bin/bash
# MAYOTIX OS Phase 4: Container Hardening Configuration Script
# Configures rootless Podman/Buildah user namespaces, subuid/subgid mapping,
# storage settings, and registry security restrictions.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_SRC="${PROJECT_ROOT}/config/containers"
CONTAINERS_DIR="/etc/containers"
SYSCTL_DIR="/etc/sysctl.d"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[✗]${NC} $*"; exit 1; }

DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=1
    log_info "Running in dry-run mode. No system changes will be applied."
fi

check_privileges() {
    if [[ $EUID -ne 0 ]] && [[ $DRY_RUN -eq 0 ]]; then
        log_error "This script must be run as root (or with --dry-run)."
    fi
}

configure_sysctl() {
    log_info "Configuring kernel sysctl parameters for secure user namespaces..."
    local sysctl_file="${SYSCTL_DIR}/99-mayotix-containers.conf"

    local sysctl_content="# MAYOTIX OS Container Hardening Sysctl
# Allow unprivileged user namespaces while bounding resource exhaustion
user.max_user_namespaces = 15000
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 1024
"
    if [[ $DRY_RUN -eq 1 ]]; then
        echo -e "[DRY-RUN] Would write to ${sysctl_file}:\n${sysctl_content}"
    else
        mkdir -p "${SYSCTL_DIR}"
        echo "${sysctl_content}" > "${sysctl_file}"
        sysctl -p "${sysctl_file}" 2>/dev/null || log_warn "Failed to reload sysctl immediately."
        log_success "Applied container sysctl hardening."
    fi
}

configure_subuid_subgid() {
    log_info "Configuring subuid and subgid allocations for rootless namespaces..."
    local default_user="${SUDO_USER:-mayotix}"

    # Range 100000-165535 (65536 UIDs/GIDs)
    if [[ $DRY_RUN -eq 1 ]]; then
        echo "[DRY-RUN] Would assign subuid/subgid range 100000:65536 for user: ${default_user}"
    else
        touch /etc/subuid /etc/subgid
        if ! grep -q "^${default_user}:" /etc/subuid 2>/dev/null; then
            echo "${default_user}:100000:65536" >> /etc/subuid
            log_success "Configured /etc/subuid for ${default_user}."
        fi
        if ! grep -q "^${default_user}:" /etc/subgid 2>/dev/null; then
            echo "${default_user}:100000:65536" >> /etc/subgid
            log_success "Configured /etc/subgid for ${default_user}."
        fi
    fi
}

deploy_container_configs() {
    log_info "Deploying hardened container registry and storage configurations..."

    if [[ $DRY_RUN -eq 1 ]]; then
        echo "[DRY-RUN] Would install ${CONFIG_SRC}/registries.conf to ${CONTAINERS_DIR}/registries.conf"
        echo "[DRY-RUN] Would install ${CONFIG_SRC}/storage.conf to ${CONTAINERS_DIR}/storage.conf"
    else
        mkdir -p "${CONTAINERS_DIR}"
        if [[ -f "${CONFIG_SRC}/registries.conf" ]]; then
            cp "${CONFIG_SRC}/registries.conf" "${CONTAINERS_DIR}/registries.conf"
            chmod 644 "${CONTAINERS_DIR}/registries.conf"
            log_success "Deployed registries.conf"
        fi
        if [[ -f "${CONFIG_SRC}/storage.conf" ]]; then
            cp "${CONFIG_SRC}/storage.conf" "${CONTAINERS_DIR}/storage.conf"
            chmod 644 "${CONTAINERS_DIR}/storage.conf"
            log_success "Deployed storage.conf"
        fi
    fi
}

main() {
    log_info "Starting MAYOTIX OS Container Hardening setup..."
    check_privileges
    configure_sysctl
    configure_subuid_subgid
    deploy_container_configs
    log_success "Container Hardening setup completed successfully."
}

main "$@"
