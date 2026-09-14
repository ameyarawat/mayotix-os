#!/bin/bash
# MAYOTIX OS Phase 4: Container Vulnerability Scanning Script
# Scans container images for vulnerabilities using Trivy with strict severity thresholds.
# Blocks images with CRITICAL or HIGH vulnerabilities.

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

# Defaults
TRIVY="trivy"
IMAGE=""
SEVERITY="CRITICAL,HIGH"
IGNORE_UNFIXED=0
DRY_RUN=0
FORMAT="table"  # can be table, json, sarif, etc.
EXIT_CODE=0

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --image)
            IMAGE="$2"
            shift 2
            ;;
        --trivy)
            TRIVY="$2"
            shift 2
            ;;
        --severity)
            SEVERITY="$2"
            shift 2
            ;;
        --ignore-unfixed)
            IGNORE_UNFIXED=1
            shift
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --format)
            FORMAT="$2"
            shift 2
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
    if ! command -v ${TRIVY} &> /dev/null; then
        log_error "Trivy not found. Please install trivy (https://github.com/aquasecurity/trivy)"
    fi
}

scan_image() {
    local image=$1
    local severity=$2
    local ignore_unfixed=$3
    local format=$4

    log_info "Scanning image ${image} for vulnerabilities (severity: ${severity})..."

    local trivy_args=()
    trivy_args+=(image)
    trivy_args+=("--severity" "${severity}")
    if [[ ${ignore_unfixed} -eq 1 ]]; then
        trivy_args+=("--ignore-unfixed")
    fi
    trivy_args+=("--format" "${format}")
    trivy_args+=("${image}")

    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "[DRY-RUN] Would run: ${TRIVY} ${trivy_args[*]}"
        # Simulate a clean scan for dry-run
        log_success "[DRY-RUN] Scan completed. No CRITICAL/HIGH vulnerabilities found (simulated)."
        return 0
    fi

    # Run trivy and capture output
    local output
    output=$(${TRIVY} "${trivy_args[@]}" 2>&1) || {
        # Trivy exits with non-zero if vulnerabilities are found, but we want to capture the output
        # So we don't set -e here, we check the exit code after.
        EXIT_CODE=$?
    }

    # If we are in a mode where we want to see the output, we print it.
    echo "${output}"

    # Check if the scan found any vulnerabilities of the specified severity.
    # Trivy returns a non-zero exit code when it finds vulnerabilities matching the severity.
    if [[ $EXIT_CODE -ne 0 ]]; then
        log_error "Scan found CRITICAL or HIGH vulnerabilities in ${image}."
        return 1
    else
        log_success "Scan completed. No CRITICAL or HIGH vulnerabilities found in ${image}."
        return 0
    fi
}

main() {
    log_info "Starting MAYOTIX OS Container Vulnerability Scan"
    check_dependencies

    if scan_image "${IMAGE}" "${SEVERITY}" "${IGNORE_UNFIXED}" "${FORMAT}"; then
        log_success "Vulnerability scan passed for ${IMAGE}."
        exit 0
    else
        log_error "Vulnerability scan failed for ${IMAGE}."
        exit 1
    fi
}

main "$@"