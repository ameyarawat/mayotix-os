#!/bin/bash
# MAYOTIX OS Phase 4: Container Image Signature Verification Script
# Verifies container image signatures using Cosign before allowing pull/run.
# Integrates with Podman/BUILDah and enforces signature policy.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="${PROJECT_ROOT}/config/containers"
KEY_DIR="${CONFIG_DIR}/keys/sigstore"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# Defaults
COSIGN="cosign"
PODMAN="podman"
DRY_RUN=0
VERIFY_ONLY=0
IMAGE=""
KEY_FILE="${KEY_DIR}/public.key"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --image)
            IMAGE="$2"
            shift 2
            ;;
        --cosign)
            COSIGN="$2"
            shift 2
            ;;
        --podman)
            PODMAN="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --verify-only)
            VERIFY_ONLY=1
            shift
            ;;
        --key)
            KEY_FILE="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 --image <image> [--key <key_path>] [--verify-only] [--dry-run]"
            echo "Options:"
            echo "  --image <image>       Target container image reference"
            echo "  --key <key_path>      Path to Cosign public key"
            echo "  --verify-only         Run verification without executing/pulling"
            echo "  --dry-run             Simulate verification step"
            echo "  -h, --help            Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            ;;
    esac
done

# Validate required arguments
if [[ -z "${IMAGE}" ]]; then
    log_error "Image name is required (use --image <image>)"
fi

# Check dependencies
check_dependencies() {
    log_info "Checking dependencies..."
    if ! command -v ${COSIGN} &> /dev/null; then
        if [[ $DRY_RUN -eq 1 ]]; then
            log_warn "Cosign not installed. [Dry-Run] Simulating signature verification check."
        else
            log_error "Cosign not found. Please install cosign (https://github.com/sigstore/cosign)"
        fi
    fi
    if ! command -v ${PODMAN} &> /dev/null; then
        if [[ $DRY_RUN -eq 1 ]]; then
            log_warn "Podman not installed. [Dry-Run] Simulating container runtime presence."
        else
            log_error "Podman not found. Please install podman."
        fi
    fi
    if [[ ! -f "${KEY_FILE}" ]] && [[ $DRY_RUN -eq 0 ]] && command -v ${COSIGN} &> /dev/null; then
        log_warn "Public key not found at ${KEY_FILE}. Generating a temporary key for demonstration."
        mkdir -p "${KEY_DIR}"
        ${COSIGN} generate-key-pair --output-key-prefix "${KEY_DIR}/cosign" >/dev/null 2>&1 || true
        KEY_FILE="${KEY_DIR}/cosign.pub"
        log_info "Generated temporary key pair at ${KEY_DIR}/cosign (for testing only)."
    fi
}

verify_image_signature() {
    local image=$1
    log_info "Verifying signature for image: ${image}"

    # Use cosign to verify the image signature
    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "[DRY-RUN] Would run: ${COSIGN} verify --key ${KEY_FILE} ${image}"
        return 0
    fi

    # Attempt verification
    if ${COSIGN} verify --key "${KEY_FILE}" "${image}" &> /dev/null; then
        log_success "Signature verification passed for ${image}"
        return 0
    else
        log_error "Signature verification failed for ${image}"
        return 1
    fi
}

main() {
    log_info "Starting MAYOTIX OS Container Image Signature Verification"
    check_dependencies

    if verify_image_signature "${IMAGE}"; then
        if [[ $VERIFY_ONLY -eq 1 ]]; then
            log_success "Verification complete. Image ${IMAGE} is signed and trusted."
            exit 0
        fi

        # If not verify-only, we can proceed to pull/run (but we leave that to the caller)
        log_info "Image ${IMAGE} is verified. Proceeding with podman/pull/run as per caller's intent."
        exit 0
    else
        log_error "Image ${IMAGE} failed verification. Aborting."
        exit 1
    fi
}

main "$@"