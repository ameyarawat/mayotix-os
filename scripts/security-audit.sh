#!/bin/bash
# MAYOTIX OS Security Audit Framework
#
# Comprehensive security audit for MAYOTIX OS components
#
# Usage:
#   ./scripts/security-audit.sh                    # Full audit
#   ./scripts/security-audit.sh --quick            # Quick check
#   ./scripts/security-audit.sh --report           # Generate report

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[⚠]${NC} $*"; }
log_error() { echo -e "${RED}[✗]${NC} $*"; }
log_section() { echo -e "\n${PURPLE}━━━ $* ━━━${NC}"; }

QUICK=0
GENERATE_REPORT=0
AUDIT_RESULTS=()

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --quick) QUICK=1 ;;
        --report) GENERATE_REPORT=1 ;;
        *) log_error "Unknown option: $1" ;;
    esac
    shift
done

# Audit: Secrets and credentials
audit_secrets() {
    log_section "Secrets & Credentials Audit"

    local found=0
    local patterns=(
        "PRIVATE KEY"
        "-----BEGIN"
        "api_key"
        "password.*="
        "secret.*="
        "AWS_SECRET"
        "GITHUB_TOKEN"
        "DATABASE_URL"
    )

    for pattern in "${patterns[@]}"; do
        if grep -r "$pattern" "$PROJECT_ROOT" \
            --exclude-dir=.git \
            --exclude-dir=build \
            --exclude="*.iso" \
            --exclude="*.log" \
            2>/dev/null | grep -v "MAYOTIX_ARCHITECTURE.md" | grep -v "example"; then
            log_error "Found potential secret: $pattern"
            found=1
        fi
    done

    if [[ $found -eq 0 ]]; then
        log_success "No secrets found"
        AUDIT_RESULTS+=("Secrets: PASS")
    else
        log_error "Secrets found in repository"
        AUDIT_RESULTS+=("Secrets: FAIL")
    fi
}

# Audit: File permissions
audit_permissions() {
    log_section "File Permissions Audit"

    local critical_files=(
        "/etc/shadow:640"
        "/etc/sudoers:440"
        "/root:700"
        "/etc/ssh:755"
    )

    local all_pass=1
    for check in "${critical_files[@]}"; do
        local file="${check%:*}"
        local expected="${check#*:}"

        if [[ -e "$file" ]]; then
            local actual
            actual=$(stat -c '%a' "$file" 2>/dev/null || echo "???")

            if [[ "$actual" == "$expected" ]]; then
                log_success "$file: $actual"
            else
                log_warn "$file: expected $expected, got $actual"
                all_pass=0
            fi
        fi
    done

    if [[ $all_pass -eq 1 ]]; then
        AUDIT_RESULTS+=("Permissions: PASS")
    else
        AUDIT_RESULTS+=("Permissions: WARN")
    fi
}

# Audit: SELinux policies
audit_selinux() {
    log_section "SELinux Policy Audit"

    if ! command -v getenforce &>/dev/null; then
        log_warn "SELinux tools not available (not Linux?)"
        AUDIT_RESULTS+=("SELinux: SKIP")
        return
    fi

    local mode
    mode=$(getenforce 2>/dev/null || echo "Disabled")

    if [[ "$mode" == "Enforcing" ]]; then
        log_success "SELinux is enforcing"
        AUDIT_RESULTS+=("SELinux: PASS")
    elif [[ "$mode" == "Permissive" ]]; then
        log_warn "SELinux is in permissive mode (should be enforcing)"
        AUDIT_RESULTS+=("SELinux: WARN")
    else
        log_error "SELinux is disabled"
        AUDIT_RESULTS+=("SELinux: FAIL")
    fi
}

# Audit: Firewall
audit_firewall() {
    log_section "Firewall Audit"

    if ! command -v firewall-cmd &>/dev/null; then
        log_warn "Firewall tools not available"
        AUDIT_RESULTS+=("Firewall: SKIP")
        return
    fi

    local status
    status=$(firewall-cmd --state 2>/dev/null || echo "not running")

    if [[ "$status" == "running" ]]; then
        log_success "Firewall is running"

        # Check for reasonable rules
        local zones
        zones=$(firewall-cmd --get-zones 2>/dev/null | wc -w)
        log_info "Active zones: $zones"

        AUDIT_RESULTS+=("Firewall: PASS")
    else
        log_error "Firewall is not running"
        AUDIT_RESULTS+=("Firewall: FAIL")
    fi
}

# Audit: Audit daemon
audit_auditd() {
    log_section "Audit Daemon Audit"

    if ! command -v auditctl &>/dev/null; then
        log_warn "Audit tools not available"
        AUDIT_RESULTS+=("Auditd: SKIP")
        return
    fi

    local rules
    rules=$(auditctl -l 2>/dev/null | grep -c "^-" || echo "0")

    if [[ $rules -gt 0 ]]; then
        log_success "Audit daemon active with $rules rules"
        AUDIT_RESULTS+=("Auditd: PASS")
    else
        log_warn "Audit daemon has no rules configured"
        AUDIT_RESULTS+=("Auditd: WARN")
    fi
}

# Audit: Systemd services
audit_systemd() {
    log_section "Systemd Service Audit"

    if [[ ! -d "${PROJECT_ROOT}/services" ]]; then
        log_warn "Services directory not found"
        AUDIT_RESULTS+=("Systemd: SKIP")
        return
    fi

    local validated=0
    local total=0

    for service in "${PROJECT_ROOT}"/services/*.service; do
        if [[ -f "$service" ]]; then
            ((total++))
            if systemd-analyze verify "$service" &>/dev/null; then
                ((validated++))
            else
                log_warn "$(basename "$service") has issues"
            fi
        fi
    done

    if [[ $validated -eq $total ]]; then
        log_success "All $total services validated"
        AUDIT_RESULTS+=("Systemd: PASS")
    else
        log_warn "$validated/$total services valid"
        AUDIT_RESULTS+=("Systemd: WARN")
    fi
}

# Audit: Kernel configuration
audit_kernel() {
    log_section "Kernel Security Audit"

    local kernel_config="${PROJECT_ROOT}/kernel/config"
    if [[ ! -f "$kernel_config" ]]; then
        log_warn "Kernel config not found"
        AUDIT_RESULTS+=("Kernel: SKIP")
        return
    fi

    local security_options=(
        "CONFIG_RANDOMIZE_BASE=y"
        "CONFIG_STRICT_KERNEL_RWX=y"
        "CONFIG_SECURITY_SELINUX=y"
        "CONFIG_MODULE_SIG_FORCE=y"
        "CONFIG_KEXEC=n"
    )

    local all_pass=1
    for option in "${security_options[@]}"; do
        if grep -q "^$option" "$kernel_config"; then
            log_success "$option"
        else
            log_warn "$option not found or not set correctly"
            all_pass=0
        fi
    done

    if [[ $all_pass -eq 1 ]]; then
        AUDIT_RESULTS+=("Kernel: PASS")
    else
        AUDIT_RESULTS+=("Kernel: WARN")
    fi
}

# Audit: SUID binaries
audit_suid() {
    log_section "SUID Binary Audit"

    local suid_count
    suid_count=$(find "$PROJECT_ROOT" -perm -4000 -type f 2>/dev/null | wc -l)

    if [[ $suid_count -eq 0 ]]; then
        log_success "No SUID binaries found (good)"
        AUDIT_RESULTS+=("SUID: PASS")
    else
        log_warn "Found $suid_count SUID binaries"
        find "$PROJECT_ROOT" -perm -4000 -type f 2>/dev/null | head -5
        AUDIT_RESULTS+=("SUID: WARN")
    fi
}

# Audit: Package dependencies
audit_dependencies() {
    log_section "Dependency Audit"

    if [[ $QUICK -eq 1 ]]; then
        log_info "Skipping dependency scan (--quick mode)"
        AUDIT_RESULTS+=("Dependencies: SKIP")
        return
    fi

    log_info "Scanning dependencies for known vulnerabilities..."

    if command -v cargo &>/dev/null && [[ -f "${PROJECT_ROOT}/Cargo.lock" ]]; then
        if cargo audit --deny warnings &>/dev/null; then
            log_success "Cargo dependencies: safe"
            AUDIT_RESULTS+=("Cargo: PASS")
        else
            log_warn "Cargo audit found issues"
            AUDIT_RESULTS+=("Cargo: WARN")
        fi
    fi

    if command -v pip &>/dev/null && [[ -f "${PROJECT_ROOT}/requirements.txt" ]]; then
        if pip-audit &>/dev/null; then
            log_success "Python dependencies: safe"
            AUDIT_RESULTS+=("Python: PASS")
        else
            log_warn "Python audit found issues"
            AUDIT_RESULTS+=("Python: WARN")
        fi
    fi
}

# Generate report
generate_report() {
    log_section "Audit Report"

    local report_file="${PROJECT_ROOT}/build/security-audit-$(date +%Y%m%d-%H%M%S).json"
    mkdir -p "$(dirname "$report_file")"

    {
        echo "{"
        echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
        echo "  \"results\": ["

        for ((i=0; i<${#AUDIT_RESULTS[@]}; i++)); do
            local result="${AUDIT_RESULTS[$i]}"
            local status="${result##*: }"
            local category="${result%: *}"

            echo -n "    {\"category\": \"$category\", \"status\": \"$status\"}"
            if [[ $i -lt $((${#AUDIT_RESULTS[@]} - 1)) ]]; then
                echo ","
            else
                echo ""
            fi
        done

        echo "  ]"
        echo "}"
    } > "$report_file"

    log_success "Report saved: $report_file"
}

# Main
main() {
    log_info "MAYOTIX OS Security Audit Framework"
    log_info "Start time: $(date)"

    audit_secrets
    audit_permissions
    audit_selinux
    audit_firewall
    audit_auditd
    audit_systemd
    audit_kernel
    audit_suid
    audit_dependencies

    log_section "Audit Summary"
    for result in "${AUDIT_RESULTS[@]}"; do
        echo "  $result"
    done

    if [[ $GENERATE_REPORT -eq 1 ]]; then
        generate_report
    fi

    log_success "Audit complete: $(date)"
}

main "$@"
