#!/bin/bash
# MAYOTIX OS SELinux Policy Compiler
#
# Compiles SELinux policies from .te (type enforcement) source files
# Generates .mod (module) and .pp (policy package) files
# Also handles .fc (file context) and .if (interface) files
#
# Usage:
#   ./scripts/compile-selinux.sh                    # Compile all policies
#   ./scripts/compile-selinux.sh mayotix            # Compile specific policy (by base name)
#   ./scripts/compile-selinux.sh --install          # Compile and load
#   ./scripts/compile-selinux.sh mayotix --install  # Compile specific and install

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

INSTALL=0
SPECIFIC_POLICY=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --install) INSTALL=1 ;;
        *.te) SPECIFIC_POLICY="$1" ;; # Allow full path or just name with .te
        *)
            # If it doesn't contain ., treat as base name and add .te later
            if [[ ! "$1" =~ \. ]]; then
                SPECIFIC_POLICY="${1}.te"
            else
                log_error "Unknown option: $1"
            fi
            ;;
    esac
    shift
done

# Check prerequisites
check_prerequisites() {
    log_info "Checking SELinux tools..."

    local required_tools=(
        "checkmodule"
        "semodule_package"
        "semanage"
        "semodule"
    )

    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            log_error "Required tool not found: $tool"
        fi
    done

    log_success "All SELinux tools available"
}

# Create build directory
setup_build_dir() {
    mkdir -p "$BUILD_DIR"
    log_success "Build directory ready: $BUILD_DIR"
}

# Compile individual policy
compile_policy() {
    local te_file=$1
    local base_name
    base_name=$(basename "$te_file" .te)

    log_info "Compiling: $base_name"

    # Compile .te to .mod
    local compile_out
    if compile_out=$(checkmodule -M -m "$te_file" -o "${BUILD_DIR}/${base_name}.mod" 2>&1); then
        log_success "$base_name compiled to .mod"
    else
        echo -e "${RED}${compile_out}${NC}"
        log_error "Failed to compile $base_name"
    fi

    # Package .mod to .pp
    local pkg_out
    if pkg_out=$(semodule_package -o "${BUILD_DIR}/${base_name}.pp" \
        -m "${BUILD_DIR}/${base_name}.mod" 2>&1); then
        log_success "$base_name packaged to .pp"
    else
        echo -e "${RED}${pkg_out}${NC}"
        log_error "Failed to package $base_name"
    fi

    # Copy associated .fc and .if files to build directory for reference
    if [[ -f "${SELINUX_DIR}/${base_name}.fc" ]]; then
        cp "${SELINUX_DIR}/${base_name}.fc" "${BUILD_DIR}/"
        log_success "Copied ${base_name}.fc to build directory"
    fi
    if [[ -f "${SELINUX_DIR}/${base_name}.if" ]]; then
        cp "${SELINUX_DIR}/${base_name}.if" "${BUILD_DIR}/"
        log_success "Copied ${base_name}.if to build directory"
    fi
}

# Compile all policies
compile_all() {
    log_info "Compiling all SELinux policies..."

    if [[ ! -d "$SELINUX_DIR" ]]; then
        log_error "SELinux directory not found: $SELINUX_DIR"
    fi

    for te_file in "$SELINUX_DIR"/*.te; do
        if [[ -f "$te_file" ]]; then
            compile_policy "$te_file"
        fi
    done

    log_success "All policies compiled"
}

# Install policies (requires root)
install_policies() {
    log_info "Installing SELinux policies (requires root)..."

    if [[ $EUID -ne 0 ]]; then
        log_error "Root privileges required to install policies"
    fi

    for pp_file in "${BUILD_DIR}"/*.pp; do
        if [[ -f "$pp_file" ]]; then
            base_name=$(basename "$pp_file" .pp)
            log_info "Installing: $base_name"

            if semodule -i "$pp_file"; then
                log_success "$base_name installed"
            else
                log_error "Failed to install $base_name"
            fi
        fi
    done

    log_success "All policies installed"
}

# Verify policies
verify_policies() {
    log_info "Verifying installed policies..."

    semodule -l | grep mayotix || log_warn "No MAYOTIX policies installed yet"

    log_success "Policy verification complete"
}

# Main
main() {
    log_info "MAYOTIX OS SELinux Policy Compiler"

    check_prerequisites
    setup_build_dir

    if [[ -n "$SPECIFIC_POLICY" ]]; then
        # If the user gave a base name without .te, we already added .te above
        local te_path="${SELINUX_DIR}/${SPECIFIC_POLICY}"
        if [[ -f "$te_path" ]]; then
            compile_policy "$te_path"
        else
            log_error "Policy file not found: $SPECIFIC_POLICY"
        fi
    else
        compile_all
    fi

    verify_policies

    if [[ $INSTALL -eq 1 ]]; then
        install_policies
    fi

    log_success "SELinux compilation complete"
    echo ""
    echo "Compiled policies in: $BUILD_DIR"
    echo "To install: sudo ./scripts/compile-selinux.sh --install"
    echo "To compile and install a specific policy: sudo ./scripts/compile-selinux.sh <policy_name> --install"
}

main "$@"