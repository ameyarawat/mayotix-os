#!/bin/bash
# MAYOTIX OS Phase 4 Compliance Test Suite
#
# Automated pre-flight suite validating:
#   - Rootless container sysctl parameters
#   - Signature policy presence
#   - Devbox recipe syntax
#   - Pre-commit hook installation
#
# Usage:
#   ./scripts/test-phase4-compliance.sh          # Run all checks
#   ./scripts/test-phase4-compliance.sh --verbose # Verbose output

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

VERBOSE=0

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose) VERBOSE=1 ;;
        -h|--help)
            echo "Usage: $0 [--verbose]"
            echo "  --verbose   Enable verbose output"
            exit 0
            ;;
        *) log_error "Unknown option: $1" ;;
    esac
    shift
done

log_info() { [[ $VERBOSE -eq 1 ]] && echo -e "${BLUE}[INFO]${NC} $*" || :; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Check rootless container sysctl parameters
check_rootless_sysctl() {
    log_info "Checking rootless container sysctl parameters..."
    # Check user.max_user_namespaces (standard upstream Linux 6.x & Fedora/RHEL)
    if [[ -r /proc/sys/user/max_user_namespaces ]]; then
        local value
        value=$(cat /proc/sys/user/max_user_namespaces)
        if [[ "$value" -gt 0 ]]; then
            log_success "user.max_user_namespaces is set to $value (allowing unprivileged user namespaces)"
            return 0
        else
            log_error "user.max_user_namespaces is set to $value (expected > 0)"
            return 1
        fi
    elif [[ -r /proc/sys/kernel/unprivileged_userns_clone ]]; then
        local value
        value=$(cat /proc/sys/kernel/unprivileged_userns_clone)
        if [[ "$value" -eq 1 ]]; then
            log_success "kernel.unprivileged_userns_clone is set to 1 (allowing unprivileged user namespaces)"
            return 0
        else
            log_error "kernel.unprivileged_userns_clone is set to $value (expected 1)"
            return 1
        fi
    else
        # Fallback to checking sysctl configuration files
        if grep -qE "user\.max_user_namespaces|kernel\.unprivileged_userns_clone" /etc/sysctl.conf /etc/sysctl.d/*.conf 2>/dev/null; then
            log_success "Container user namespace parameters configured in sysctl"
            return 0
        else
            log_error "User namespace parameters not configured in sysctl"
            return 1
        fi
    fi
}

# Check signature policy presence
check_signature_policy() {
    log_info "Checking signature policy presence..."
    local policy_path="/etc/containers/policy.json"
    if [[ -f "$policy_path" ]]; then
        # Try to validate JSON (if jq is available)
        if command -v jq >/dev/null 2>&1; then
            if jq empty "$policy_path" 2>/dev/null; then
                log_success "Signature policy exists and is valid JSON"
                return 0
            else
                log_error "Signature policy exists but is invalid JSON"
                return 1
            fi
        else
            # Without jq, we just check existence and note that we cannot validate JSON
            log_success "Signature policy exists (cannot validate JSON without jq)"
            return 0
        fi
    else
        log_error "Signature policy not found at $policy_path"
        return 1
    fi
}

# Check devbox recipe syntax
check_devbox_recipes() {
    log_info "Checking devbox recipe syntax..."
    local recipe_dir="${PROJECT_ROOT}/desktop/dev-environments/recipes"
    local failed=0

    if [[ ! -d "$recipe_dir" ]]; then
        log_error "Recipe directory not found: $recipe_dir"
        return 1
    fi

    for containerfile in "$recipe_dir"/*.Containerfile; do
        if [[ ! -f "$containerfile" ]]; then
            continue
        fi

        log_info "Checking $containerfile..."
        # Check for FROM instruction
        if ! grep -q "^FROM" "$containerfile"; then
            log_error "Missing FROM instruction in $containerfile"
            ((failed++))
            continue
        fi

        # Check for non-root user (we look for a USER instruction that is not 0 or root, or a comment about non-root)
        # We'll check for a USER instruction with a non-zero UID or a user named 'developer' (as per our recipes)
        if ! grep -q "^USER" "$containerfile"; then
            log_warn "No explicit USER instruction in $containerfile (may rely on base image)"
            # We don't fail because the base image might set the user
        else
            # Check if the USER instruction sets a non-root user (we'll accept any non-zero or named user)
            # We'll just note that we found a USER instruction and assume it's correct if it's not 'USER root' or 'USER 0'
            if grep -q "^USER.*root\|^USER.*0[^0-9]" "$containerfile"; then
                log_error "USER instruction in $containerfile sets to root (UID 0)"
                ((failed++))
            fi
        fi

        # Additional checks: ensure there's a comment about non-root or security (optional)
        # We'll skip for now.

        log_success "Basic syntax check passed for $containerfile"
    done

    if [[ $failed -eq 0 ]]; then
        log_success "All devbox recipes passed syntax check"
        return 0
    else
        log_error "$failed devbox recipe(ies) had syntax issues"
        return 1
    fi
}

# Check pre-commit hook installation
check_pre_commit_hooks() {
    log_info "Checking pre-commit hook installation..."
    local failed=0

    # Check if we are in a git repository
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        log_error "Not a git repository. Cannot check git hooks."
        return 1
    fi

    # Check the hooks path
    local hooks_path
    hooks_path=$(git config core.hooksPath || echo "")
    local expected_hooks_path="${PROJECT_ROOT}/.githooks"

    if [[ "$hooks_path" == "$expected_hooks_path" ]] || [[ "$hooks_path" == ".githooks" ]] || [[ "$hooks_path" == "./.githooks" ]]; then
        log_success "Git hooks path is correctly set to .githooks"
    else
        log_error "Git hooks path is set to '$hooks_path', expected '.githooks' (run ./scripts/install-git-hooks.sh)"
        ((failed++))
    fi

    # Check that the pre-commit hook exists and is executable
    local pre_commit_hook="${expected_hooks_path}/pre-commit"
    if [[ ! -f "$pre_commit_hook" ]]; then
        log_error "Pre-commit hook not found at $pre_commit_hook"
        ((failed++))
    elif [[ ! -x "$pre_commit_hook" ]]; then
        log_error "Pre-commit hook at $pre_commit_hook is not executable"
        ((failed++))
    else
        log_success "Pre-commit hook exists and is executable"
    fi

    if [[ $failed -eq 0 ]]; then
        log_success "Pre-commit hook installation check passed"
        return 0
    else
        log_error "$failed issue(s) found with pre-commit hook installation"
        return 1
    fi
}

# Main function
main() {
    log_info "MAYOTIX OS Phase 4 Compliance Test Suite"
    echo ""

    local checks_passed=0
    local total_checks=4

    # Run each check
    if check_rootless_sysctl; then
        ((checks_passed++))
    fi
    echo ""

    if check_signature_policy; then
        ((checks_passed++))
    fi
    echo ""

    if check_devbox_recipes; then
        ((checks_passed++))
    fi
    echo ""

    if check_pre_commit_hooks; then
        ((checks_passed++))
    fi
    echo ""

    # Summary
    echo "----------------------------------------------------------------"
    echo "Phase 4 Compliance Check Summary: $checks_passed/$total_checks passed"
    if [[ $checks_passed -eq $total_checks ]]; then
        log_success "All Phase 4 compliance checks passed!"
        return 0
    else
        log_error "Some Phase 4 compliance checks failed."
        return 1
    fi
}

main "$@"