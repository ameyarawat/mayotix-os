#!/bin/bash
# MAYOTIX OS: Install Git Pre-commit Security Hooks
#
# This script sets up the local Git hooks to use the .githooks directory
# and installs the pre-commit hook for security checks.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
GIT_HOOKS_DIR="${PROJECT_ROOT}/.githooks"
PRE_COMMIT_HOOK="${GIT_HOOKS_DIR}/pre-commit"

log_info() { echo -e "\033[0;34m[INFO]\033[0m $*"; }
log_success() { echo -e "\033[0;32m[✓]\033[0m $*"; }
log_error() { echo -e "\033[0;31m[ERROR]\033[0m $*"; exit 1; }

main() {
    # Check if we are in a git repository
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        log_error "Not a git repository. Please run this script from the root of a git repository."
    fi

    # Ensure the .githooks directory exists
    if [[ ! -d "${GIT_HOOKS_DIR}" ]]; then
        log_info "Creating .githooks directory at ${GIT_HOOKS_DIR}"
        mkdir -p "${GIT_HOOKS_DIR}"
    fi

    # Ensure the pre-commit hook exists and is executable
    if [[ ! -f "${PRE_COMMIT_HOOK}" ]]; then
        log_error "Pre-commit hook not found at ${PRE_COMMIT_HOOK}. Please create it first."
    fi

    if [[ ! -x "${PRE_COMMIT_HOOK}" ]]; then
        log_info "Making pre-commit hook executable"
        chmod +x "${PRE_COMMIT_HOOK}"
    fi

    # Set the git hooks path to .githooks
    log_info "Setting git hooks path to .githooks"
    git config core.hooksPath "${GIT_HOOKS_DIR}"

    log_success "Git hooks installed successfully. Pre-commit hook is active."
}

main "$@"