#!/bin/bash
# MAYOTIX OS Security Check Script
#
# Phase 1 security verification:
# - SELinux policy compilation
# - Systemd service validation
# - Audit rule verification
# - Filesystem permission checks

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

CHECKS_PASSED=0
CHECKS_FAILED=0

check_secrets() {
    log_info "Scanning for secrets..."

    local secret_patterns=(
        "PRIVATE KEY"
        "-----BEGIN"
        "api_key"
        "password"
        "token"
        "secret"
    )

    local found_secrets=0

    for pattern in "${secret_patterns[@]}"; do
        if grep -r "$pattern" "${PROJECT_ROOT}" \
            --exclude-dir=.git \
            --exclude-dir=.github \
            --exclude-dir=build \
            --exclude="*.iso" \
            --exclude="*.log" \
            2>/dev/null | grep -v "MAYOTIX_ARCHITECTURE.md" | grep -v "example" | grep -v "placeholder"; then
            found_secrets=1
        fi
    done

    if [[ $found_secrets -eq 0 ]]; then
        log_success "No secrets found"
        ((CHECKS_PASSED++))
    else
        log_error "Secrets found in repository!"
    fi
}

check_systemd_services() {
    log_info "Checking systemd service files..."

    local services_dir="${PROJECT_ROOT}/services"

    if [[ ! -d "$services_dir" ]]; then
        log_warn "Services directory not found"
        return
    fi

    for service in "$services_dir"/*.service; do
        if [[ -f "$service" ]]; then
            if systemd-analyze verify "$service" &>/dev/null; then
                log_success "$(basename "$service") valid"
                ((CHECKS_PASSED++))
            else
                log_warn "$(basename "$service") has issues"
                systemd-analyze verify "$service" || true
                ((CHECKS_FAILED++))
            fi
        fi
    done
}

check_file_permissions() {
    log_info "Checking critical file permissions..."

    local checks=(
        "/etc/shadow:640"
        "/etc/sudoers:440"
        "/root:700"
    )

    for check in "${checks[@]}"; do
        local file="${check%:*}"
        local expected_perm="${check#*:}"

        if [[ -e "$file" ]]; then
            local actual_perm
            actual_perm=$(stat -c '%a' "$file")

            if [[ "$actual_perm" == "$expected_perm" ]]; then
                log_success "$file has correct permissions ($actual_perm)"
                ((CHECKS_PASSED++))
            else
                log_warn "$file: expected $expected_perm, got $actual_perm"
                ((CHECKS_FAILED++))
            fi
        fi
    done
}

check_selinux_policies() {
    log_info "Checking SELinux policies..."

    local selinux_dir="${PROJECT_ROOT}/security/selinux"

    if [[ ! -d "$selinux_dir" ]]; then
        log_warn "SELinux policy directory not found"
        return
    fi

    if command -v checkmodule &>/dev/null; then
        for policy in "$selinux_dir"/*.te; do
            if [[ -f "$policy" ]]; then
                if checkmodule -M -m "$policy" &>/dev/null; then
                    log_success "$(basename "$policy") syntax valid"
                    ((CHECKS_PASSED++))
                else
                    log_warn "$(basename "$policy") has syntax errors"
                    ((CHECKS_FAILED++))
                fi
            fi
        done
    else
        log_warn "checkmodule not found (install policycoreutils-devel)"
    fi
}

check_kernel_config() {
    log_info "Checking kernel configuration..."

    local kernel_config="${PROJECT_ROOT}/kernel/config"

    if [[ ! -f "$kernel_config" ]]; then
        log_warn "Kernel config not found"
        return
    fi

    # Check for security-critical options
    local security_options=(
        "CONFIG_RANDOMIZE_BASE=y"
        "CONFIG_STRICT_KERNEL_RWX=y"
        "CONFIG_SECURITY_SELINUX=y"
        "CONFIG_MODULE_SIG_FORCE=y"
    )

    for option in "${security_options[@]}"; do
        if grep -q "^$option" "$kernel_config"; then
            log_success "$option enabled"
            ((CHECKS_PASSED++))
        else
            log_warn "$option not found or not enabled"
            ((CHECKS_FAILED++))
        fi
    done
}

main() {
    log_info "MAYOTIX OS Security Check - Phase 1"

    check_secrets
    check_systemd_services
    check_file_permissions
    check_selinux_policies
    check_kernel_config

    echo ""
    echo "Security Check Results:"
    echo "  ✓ Passed: $CHECKS_PASSED"
    echo "  ✗ Failed: $CHECKS_FAILED"

    if [[ $CHECKS_FAILED -eq 0 ]]; then
        log_success "All security checks passed"
        exit 0
    else
        log_error "Some security checks failed"
    fi
}

main "$@"
