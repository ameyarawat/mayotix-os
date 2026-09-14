#!/bin/bash
# MAYOTIX OS Phase 4: CI/CD & Build Pipeline Gating Script
# Enforces signature verification and CVE compliance before deployment.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

IMAGE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --image)
            IMAGE="$2"
            shift 2
            ;;
        *)
            log_error "Unknown option: $1"
            ;;
    esac
done

if [[ -z "${IMAGE}" ]]; then
    log_error "Image name is required (use --image <image>)"
fi

main() {
    log_info "Running pre-deployment security gate for: ${IMAGE}"

    # 1. Signature Verification
    if ! "${SCRIPT_DIR}/verify-container-image.sh" --image "${IMAGE}" --verify-only; then
        log_error "Deployment blocked: Image signature verification failed."
    fi

    # 2. Vulnerability Scanning
    if ! "${SCRIPT_DIR}/scan-container-vulnerabilities.sh" --image "${IMAGE}"; then
        log_error "Deployment blocked: Vulnerability scan failed."
    fi

    log_success "Security checks passed. Image ${IMAGE} is authorized for deployment."
}

main "$@"