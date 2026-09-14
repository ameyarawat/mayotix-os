#!/bin/bash
# MAYOTIX OS SELinux Policy Linter & Verifier
#
# Performs static analysis on SELinux policy files (.te) to catch common pitfalls
# and validates that policies compile without errors.
#
# Usage:
#   ./scripts/lint-selinux-policies.sh          # Lint all policies
#   ./scripts/lint-selinux-policies.sh mayotix.te   # Lint specific policy

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
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

SPECIFIC_FILE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        *.te) SPECIFIC_FILE="$1" ;;
        *) log_error "Unknown file: $1 (only .te files are supported for linting)"; exit 1 ;;
    esac
    shift
done

# Lint a single .te file
lint_te_file() {
    local file=$1
    local errors=0
    local warnings=0

    log_info "Linting $file..."

    # Check for module or policy_module declaration
    if ! grep -qE "^(module|policy_module)" "$file"; then
        log_warn "Missing module or policy_module declaration"
        ((warnings++))
    fi

    # Check for unconfined domains (domains that transition to unconfined_t)
    if grep -q "transition.*unconfined_t" "$file"; then
        log_warn "Found transition to unconfined_t (potentially unsafe)"
        ((warnings++))
    fi

    # Check for wildcard permissions (e.g., { read write * } or just *)
    if grep -q "{[[:space:]]*[^*]*\*[^*]*[[:space:]]*}" "$file"; then
        log_warn "Found wildcard permissions in a set"
        ((warnings++))
    fi
    # Also check for a standalone * (though rare in SELinux)
    if grep -q "[[:space:]]*\*[[:space:]]" "$file" && ! grep -q ".*\*.*\*" "$file"; then
        # Avoid matching comments or other contexts; this is a simple check
        log_warn "Found standalone wildcard permission"
        ((warnings++))
    fi

    # Check for missing require block when using external types
    # If there are type declarations and no require block, suggest adding one
    if grep -q "type.*;" "$file" && ! grep -q "^require" "$file"; then
        # Check if there are any types that are not defined in this file (simplistic: if there's a type and no type definition)
        # We'll just warn if there are any type usages and no require block
        if grep -q "type.* [a-zA-Z0-9_]*;" "$file" && ! grep -q "^type.* [a-zA-Z0-9_]*;" "$file" | head -1; then
            log_warn "Consider adding a require block for external types"
            ((warnings++))
        fi
    fi

    # Check for permissive domains (domain set to permissive via permissive statement)
    if grep -q "^permissive" "$file"; then
        log_warn "Found permissive domain declaration (should be avoided in production)"
        ((warnings++))
    fi

    # Check for unused allow rules (we can't statically determine unused, but we can note if there are allows with no transitions)
    # This is more of a note; we'll skip for now.

    # Check for correct file context structure (if .fc exists, we don't lint it here, but we can note)
    # We'll leave .fc and .if linting to other tools or simple validation.

    # Summary for the file
    if [[ $warnings -eq 0 ]]; then
        log_success "$file: lint passed with no warnings"
    else
        log_warn "$file: lint completed with $warnings warning(s)"
    fi

    return 0  # We don't fail on warnings for now, but we can change if needed
}

# Validate that a .te file compiles
validate_te_compile() {
    local file=$1
    local base_name
    base_name=$(basename "$file" .te)

    log_info "Compiling $file to check for syntax errors..."

    mkdir -p "$BUILD_DIR"
    if checkmodule -M -m "$file" -o "${BUILD_DIR}/${base_name}.mod" 2>&1; then
        log_success "$file: compilation successful"
        return 0
    else
        log_error "$file: compilation failed"
        return 1
    fi
}

# Main function
main() {
    log_info "MAYOTIX OS SELinux Policy Linter & Verifier"
    echo ""

    local lint_failed=0
    local compile_failed=0

    if [[ -n "$SPECIFIC_FILE" ]]; then
        # Lint and compile a specific file
        lint_te_file "${SELINUX_DIR}/${SPECIFIC_FILE}" || ((lint_failed++))
        validate_te_compile "${SELINUX_DIR}/${SPECIFIC_FILE}" || ((compile_failed++))
    else
        # Lint and compile all .te files
        for te_file in "$SELINUX_DIR"/*.te; do
            if [[ -f "$te_file" ]]; then
                lint_te_file "$te_file" || ((lint_failed++))
                validate_te_compile "$te_file" || ((compile_failed++))
            fi
        done
    fi

    echo ""
    if [[ $lint_failed -eq 0 && $compile_failed -eq 0 ]]; then
        log_success "All policies linted and compiled successfully"
        return 0
    else
        if [[ $lint_failed -gt 0 ]]; then
            log_error "$lint_failed policy(ies) had linting warnings"
        fi
        if [[ $compile_failed -gt 0 ]]; then
            log_error "$compile_failed policy(ies) failed to compile"
        fi
        return 1
    fi
}

main "$@"