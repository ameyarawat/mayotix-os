#!/bin/bash
# MAYOTIX OS SELinux Policy Syntax Validator
#
# Validates SELinux policy files before compilation
# Checks for common syntax errors and policy patterns
#
# Usage:
#   ./scripts/validate-selinux.sh                 # Validate all policies
#   ./scripts/validate-selinux.sh mayotix.te      # Validate specific policy

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SELINUX_DIR="${PROJECT_ROOT}/security/selinux"

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
        *.te|*.fc|*.if) SPECIFIC_FILE="$1" ;;
        *) log_error "Unknown file: $1"; exit 1 ;;
    esac
    shift
done

# Validate .te file structure
validate_te() {
    local file=$1
    local errors=0

    log_info "Validating $file..."

    # Check for policy_module declaration
    if ! grep -q "^policy_module" "$file"; then
        log_warn "Missing policy_module declaration"
        ((errors++))
    fi

    # Check for balanced braces
    local open_braces
    local close_braces
    open_braces=$(grep -o '{' "$file" | wc -l)
    close_braces=$(grep -o '}' "$file" | wc -l)
    if [[ $open_braces -ne $close_braces ]]; then
        log_error "Unbalanced braces: { count $open_braces, } count $close_braces"
        ((errors++))
    fi

    # Check for require section if types are used
    if grep -q "type.*;" "$file" && ! grep -q "^require" "$file"; then
        if ! grep -q "^type.*;" "$file" | head -1; then
            log_warn "Consider adding require section for external types"
        fi
    fi

    if [[ $errors -eq 0 ]]; then
        log_success "$file structure valid"
        return 0
    else
        log_error "$file has $errors validation issues"
        return 1
    fi
}

# Validate .fc file structure
validate_fc() {
    local file=$1
    local errors=0

    log_info "Validating $file..."

    # Check for file context entries
    if ! grep -q "^/" "$file"; then
        log_warn "No absolute path file contexts found"
    fi

    # Check for valid context format (system_u:object_r:type_t:s0)
    if grep -q "^/" "$file"; then
        if ! grep "^/" "$file" | grep -q ":s0$"; then
            log_warn "File contexts should end with :s0"
        fi
    fi

    if [[ $errors -eq 0 ]]; then
        log_success "$file structure valid"
        return 0
    else
        log_error "$file has $errors validation issues"
        return 1
    fi
}

# Validate .if file structure
validate_if() {
    local file=$1
    local errors=0

    log_info "Validating $file..."

    # Check for interface declarations
    if ! grep -q "^interface" "$file"; then
        log_warn "No interface declarations found"
    fi

    # Check for summary comments
    if grep -q "^interface" "$file"; then
        if ! grep -q "## <summary>" "$file"; then
            log_warn "Interface definitions should have summary documentation"
        fi
    fi

    if [[ $errors -eq 0 ]]; then
        log_success "$file structure valid"
        return 0
    else
        log_error "$file has $errors validation issues"
        return 1
    fi
}

# Main validation
main() {
    log_info "MAYOTIX OS SELinux Policy Validator"
    echo ""

    local failed=0

    if [[ -n "$SPECIFIC_FILE" ]]; then
        case "$SPECIFIC_FILE" in
            *.te)
                validate_te "${SELINUX_DIR}/${SPECIFIC_FILE}" || ((failed++))
                ;;
            *.fc)
                validate_fc "${SELINUX_DIR}/${SPECIFIC_FILE}" || ((failed++))
                ;;
            *.if)
                validate_if "${SELINUX_DIR}/${SPECIFIC_FILE}" || ((failed++))
                ;;
        esac
    else
        # Validate all files
        for te_file in "$SELINUX_DIR"/*.te; do
            if [[ -f "$te_file" ]]; then
                validate_te "$te_file" || ((failed++))
            fi
        done

        for fc_file in "$SELINUX_DIR"/*.fc; do
            if [[ -f "$fc_file" ]]; then
                validate_fc "$fc_file" || ((failed++))
            fi
        done

        for if_file in "$SELINUX_DIR"/*.if; do
            if [[ -f "$if_file" ]]; then
                validate_if "$if_file" || ((failed++))
            fi
        done
    fi

    echo ""
    if [[ $failed -eq 0 ]]; then
        log_success "All validations passed"
        return 0
    else
        log_error "$failed validation(s) failed"
        return 1
    fi
}

main "$@"