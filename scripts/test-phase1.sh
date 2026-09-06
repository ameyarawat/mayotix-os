#!/bin/bash
# MAYOTIX OS Phase 1 Acceptance Tests
# Validates that Phase 1 deliverables meet acceptance criteria
#
# Usage:
#   ./scripts/test-phase1.sh              # Run all tests
#   ./scripts/phase1/test-phase1.sh --quick  # Run quick tests only

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
log_warn() { echo -e "${YELLOW}[⚠]${NC} $*"; }
log_error() { echo -e "${RED}[✗]${NC} $*"; }
log_section() { echo -e "\n${BLUE}━━━ $* ━━━${NC}"; }

TESTS_PASSED=0
TESTS_FAILED=0
QUICK=0

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --quick) QUICK=1 ;;
        *) log_error "Unknown option: $1" ;;
    esac
    shift
done

# Test: Documentation completeness
test_documentation() {
    log_section "Documentation Completeness"

    local required_docs=(
        "MAYOTIX_ARCHITECTURE.md"
        "BUILD.md"
        "DEVELOPMENT.md"
        "SECURITY.md"
        "CONTRIBUTING.md"
        "README.md"
        "CHANGELOG.md"
    )

    for doc in "${required_docs[@]}"; do
        if [[ -f "${PROJECT_ROOT}/${doc}" ]]; then
            log_success "$doc exists"
            ((TESTS_PASSED++))
        else
            log_error "$doc missing"
            ((TESTS_FAILED++))
        fi
    done
}

# Test: Build system completeness
test_build_system() {
    log_section "Build System Completeness"

    local required_scripts=(
        "scripts/build-iso.sh"
        "scripts/security-check.sh"
        "scripts/compile-selinux.sh"
        "scripts/security-audit.sh"
        "scripts/test-boot.sh"
    )

    for script in "${required_scripts[@]}"; do
        if [[ -f "${PROJECT_ROOT}/${script}" ]]; then
            if [[ -x "${PROJECT_ROOT}/${script}" ]]; then
                log_success "$script executable"
                ((TESTS_PASSED++))
            else
                log_warn "$script exists but not executable"
                ((TESTS_FAILED++))
            fi
        else
            log_error "$script missing"
            ((TESTS_FAILED++))
        fi
    done
}

# Test: Configuration files
test_configurations() {
    log_section "Configuration Files"

    local required_configs=(
        "kernel/config"
        "boot/grub2/grub.cfg"
        "boot/dracut/dracut.conf"
        "services/mayotix-security.service"
        "etc/mayotix/system.conf"
    )

    for config in "${required_configs[@]}"; do
        if [[ -f "${PROJECT_ROOT}/${config}" ]]; then
            log_success "$config exists"
            ((TESTS_PASSED++))
        else
            log_error "$config missing"
            ((TESTS_FAILED++))
        fi
    done
}

# Test: Git repository
test_git_repo() {
    log_section "Git Repository"

    if [[ -d "${PROJECT_ROOT}/.git" ]]; then
        log_success "Git repository initialized"
        ((TESTS_PASSED++))

        # Check commits
        local commit_count
        commit_count=$(cd "$PROJECT_ROOT" && git rev-list --all --count)
        if [[ $commit_count -gt 0 ]]; then
            log_success "Repository has $commit_count commits"
            ((TESTS_PASSED++))
        fi

        # Check .gitignore
        if [[ -f "${PROJECT_ROOT}/.gitignore" ]]; then
            log_success ".gitignore configured"
            ((TESTS_PASSED++))
        fi
    else
        log_error "Git repository not initialized"
        ((TESTS_FAILED++))
    fi
}

# Test: SELinux policy structure
test_selinux_policies() {
    log_section "SELinux Policy Structure"

    if [[ ! -d "${PROJECT_ROOT}/security/selinux" ]]; then
        log_warn "SELinux directory not found"
        ((TESTS_FAILED++))
        return
    fi

    # Check for policy files
    local policy_count
    policy_count=$(find "${PROJECT_ROOT}/security/selinux" -name "*.te" 2>/dev/null | wc -l)

    if [[ $policy_count -gt 0 ]]; then
        log_success "Found $policy_count SELinux policy files"
        ((TESTS_PASSED++))
    else
        log_warn "No SELinux policy files found"
        ((TESTS_FAILED++))
    fi
}

# Test: Systemd service hardening
test_systemd_services() {
    log_section "Systemd Service Hardening"

    if [[ ! -d "${PROJECT_ROOT}/services" ]]; then
        log_warn "Services directory not found"
        ((TESTS_FAILED++))
        return
    fi

    local service_count
    service_count=$(find "${PROJECT_ROOT}/services" -name "*.service" | wc -l)

    if [[ $service_count -gt 0 ]]; then
        log_success "Found $service_count systemd services"
        ((TESTS_PASSED++))

        # Check for hardening directives in at least one service
        local hardened_services=0
        for service in "${PROJECT_ROOT}"/services/*.service; do
            if grep -q "NoNewPrivileges=yes\|ProtectSystem=\|ProtectHome=" "$service"; then
                ((hardened_services++))
            fi
        done

        if [[ $hardened_services -gt 0 ]]; then
            log_success "$hardened_services services have security hardening"
            ((TESTS_PASSED++))
        fi
    else
        log_error "No systemd services found"
        ((TESTS_FAILED++))
    fi
}

# Test: Security checks
test_security_checks() {
    log_section "Security Checks"

    # No hardcoded secrets
    local secrets_found
    secrets_found=$(grep -r "PRIVATE KEY\|api_key.*=\|password.*=" "${PROJECT_ROOT}" \
        --exclude-dir=.git --exclude-dir=build --exclude="*.iso" \
        2>/dev/null | grep -v "MAYOTIX_ARCHITECTURE.md" | grep -v "example" | wc -l)

    if [[ $secrets_found -eq 0 ]]; then
        log_success "No hardcoded secrets found"
        ((TESTS_PASSED++))
    else
        log_error "$secrets_found potential secrets found"
        ((TESTS_FAILED++))
    fi

    # Check for world-writable sensitive files
    local world_writable
    world_writable=$(find "${PROJECT_ROOT}" -type f -perm /002 -not -path './.git/*' 2>/dev/null | wc -l)

    if [[ $world_writable -eq 0 ]]; then
        log_success "No world-writable files found"
        ((TESTS_PASSED++))
    else
        log_warn "$world_writable world-writable files found"
        ((TESTS_FAILED++))
    fi
}

# Test: CI/CD pipelines
test_cicd() {
    log_section "CI/CD Pipelines"

    if [[ ! -d "${PROJECT_ROOT}/.github/workflows" ]]; then
        log_warn "GitHub workflows directory not found"
        ((TESTS_FAILED++))
        return
    fi

    local workflow_count
    workflow_count=$(find "${PROJECT_ROOT}/.github/workflows" -name "*.yml" -o -name "*.yaml" | wc -l)

    if [[ $workflow_count -gt 0 ]]; then
        log_success "Found $workflow_count CI/CD workflows"
        ((TESTS_PASSED++))
    else
        log_error "No CI/CD workflows found"
        ((TESTS_FAILED++))
    fi
}

# Test: Build verification (skip in quick mode)
test_build_verification() {
    if [[ $QUICK -eq 1 ]]; then
        log_section "Build Verification (SKIPPED in quick mode)"
        return
    fi

    log_section "Build Verification"

    if ! command -v dracut &>/dev/null; then
        log_warn "Dracut not available (install to test full build)"
        ((TESTS_FAILED++))
        return
    fi

    # Test build system syntax
    if bash -n "${PROJECT_ROOT}/scripts/build-iso.sh" 2>/dev/null; then
        log_success "build-iso.sh syntax valid"
        ((TESTS_PASSED++))
    else
        log_error "build-iso.sh has syntax errors"
        ((TESTS_FAILED++))
    fi
}

# Test: Repository structure
test_repo_structure() {
    log_section "Repository Structure"

    local required_dirs=(
        "boot"
        "kernel"
        "services"
        "security"
        "scripts"
        "docs"
        "ci"
        "tests"
    )

    for dir in "${required_dirs[@]}"; do
        if [[ -d "${PROJECT_ROOT}/${dir}" ]]; then
            log_success "Directory: $dir"
            ((TESTS_PASSED++))
        else
            log_warn "Directory missing: $dir"
            ((TESTS_FAILED++))
        fi
    done
}

# Main test runner
main() {
    echo ""
    log_info "MAYOTIX OS Phase 1 Acceptance Tests"
    log_info "Start: $(date)"
    echo ""

    test_repository_structure
    test_documentation
    test_build_system
    test_configurations
    test_git_repo
    test_selinux_policies
    test_systemd_services
    test_security_checks
    test_cicd
    test_build_verification

    # Print summary
    echo ""
    log_section "Test Summary"
    echo ""
    echo "  Passed: ${GREEN}${TESTS_PASSED}${NC}"
    echo "  Failed: ${RED}${TESTS_FAILED}${NC}"
    echo ""

    if [[ $TESTS_FAILED -eq 0 ]]; then
        log_success "Phase 1 acceptance criteria met!"
        return 0
    else
        log_error "Phase 1 has $TESTS_FAILED test failures"
        return 1
    fi
}

# Fix function name mismatch
test_repository_structure() {
    test_repo_structure
}

main "$@"
