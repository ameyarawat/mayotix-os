#!/bin/bash
# MAYOTIX OS: Reproducible Build Verification Script
#
# Verifies byte-for-byte reproducibility across multiple builds.
# Compares current build against previous builds to ensure determinism.
#
# Usage:
#   ./scripts/verify-reproducible-builds.sh
#   ./scripts/verify-reproducible-builds.sh --verbose
#   ./scripts/verify-reproducible-builds.sh --compare <previous_iso>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${PROJECT_ROOT}/build"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

VERBOSE=0
COMPARE_ISO=""

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[✗]${NC} $*"; exit 1; }

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose) VERBOSE=1 ;;
        --compare) COMPARE_ISO="$2"; shift ;;
        *) log_error "Unknown option: $1" ;;
    esac
    shift
done

# Find ISO files
find_iso_files() {
    log_info "Searching for Phase 2 ISOs..."

    local iso_files=()
    while IFS= read -r -d '' file; do
        iso_files+=("$file")
    done < <(find "$BUILD_DIR" -maxdepth 1 -name "mayotix-os-2.0-alpha-*.iso" -type f -print0 | sort -z -r)

    if [[ ${#iso_files[@]} -eq 0 ]]; then
        log_error "No Phase 2 ISOs found in $BUILD_DIR"
    fi

    echo "${iso_files[@]}"
}

# Check ISO integrity
check_iso_integrity() {
    local iso_file="$1"
    local checksum_file="${iso_file}.sha256"

    log_info "Checking ISO integrity: $(basename $iso_file)"

    if [[ ! -f "$checksum_file" ]]; then
        log_warn "Checksum file not found: $checksum_file"
        return 1
    fi

    # Verify checksum
    if sha256sum -c "$checksum_file" &>/dev/null; then
        log_success "ISO checksum verified"
        return 0
    else
        log_error "ISO checksum mismatch!"
    fi
}

# Compare two ISOs
compare_isos() {
    local iso1="$1"
    local iso2="$2"

    log_info "Comparing ISOs:"
    echo "  1: $(basename $iso1)"
    echo "  2: $(basename $iso2)"
    echo ""

    # Check if files exist
    if [[ ! -f "$iso1" ]]; then
        log_error "ISO not found: $iso1"
    fi
    if [[ ! -f "$iso2" ]]; then
        log_error "ISO not found: $iso2"
    fi

    # Compare file sizes
    local size1=$(stat -f%z "$iso1" 2>/dev/null || stat -c%s "$iso1")
    local size2=$(stat -f%z "$iso2" 2>/dev/null || stat -c%s "$iso2")

    log_info "File sizes:"
    echo "  ISO 1: $(numfmt --to=iec-i --suffix=B $size1 2>/dev/null || echo "$size1 bytes")"
    echo "  ISO 2: $(numfmt --to=iec-i --suffix=B $size2 2>/dev/null || echo "$size2 bytes")"

    if [[ "$size1" -ne "$size2" ]]; then
        log_warn "File sizes differ!"
        return 1
    else
        log_success "File sizes match"
    fi

    # Compare checksums
    log_info "Computing checksums..."
    local hash1=$(sha256sum "$iso1" | cut -d' ' -f1)
    local hash2=$(sha256sum "$iso2" | cut -d' ' -f1)

    echo "  SHA256(ISO 1): $hash1"
    echo "  SHA256(ISO 2): $hash2"
    echo ""

    if [[ "$hash1" == "$hash2" ]]; then
        log_success "ISOs are byte-for-byte identical (reproducible!)"
        return 0
    else
        log_warn "ISOs differ (not reproducible)"

        # Detailed comparison
        if [[ $VERBOSE -eq 1 ]]; then
            log_info "Performing binary diff..."
            local diff_size=$(cmp -l "$iso1" "$iso2" 2>/dev/null | wc -l || echo "unknown")
            log_warn "Differences found at $diff_size byte locations"
        fi
        return 1
    fi
}

# Get ISO metadata
get_iso_metadata() {
    local iso_file="$1"

    log_info "ISO Metadata: $(basename $iso_file)"
    echo ""

    # File info
    echo "  File size: $(stat -f%z "$iso_file" 2>/dev/null || stat -c%s "$iso_file") bytes"
    echo "  Modified: $(stat -f%Sm -t '%Y-%m-%d %H:%M:%S %Z' "$iso_file" 2>/dev/null || date -r "$iso_file")"

    # ISO 9660 info
    if command -v isoinfo &>/dev/null; then
        echo ""
        echo "  ISO 9660 Information:"
        isoinfo -d -i "$iso_file" 2>/dev/null | head -5 | sed 's/^/    /' || true
    fi

    # Check for build manifest
    if [[ -f "${iso_file%.iso}.manifest.json" ]]; then
        echo ""
        echo "  Build manifest found"
    fi
}

# Generate reproducibility report
generate_report() {
    local iso_file="$1"
    local report_file="${BUILD_DIR}/REPRODUCIBILITY_REPORT.txt"

    log_info "Generating reproducibility report..."

    {
        echo "MAYOTIX OS Phase 2: Reproducible Build Report"
        echo "=============================================="
        echo ""
        echo "Generated: $(date)"
        echo ""
        echo "ISO Information:"
        echo "  File: $(basename $iso_file)"
        echo "  Size: $(stat -f%z "$iso_file" 2>/dev/null || stat -c%s "$iso_file") bytes"
        echo "  SHA256: $(sha256sum "$iso_file" | cut -d' ' -f1)"
        echo ""
        echo "Build Environment:"
        echo "  SOURCE_DATE_EPOCH: ${SOURCE_DATE_EPOCH:-not set}"
        echo "  Build host: $(hostname)"
        echo "  Build date: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "  Timezone: $TZ"
        echo ""
        echo "Reproducibility Status:"
        if [[ -f "$report_file" ]] && grep -q "reproducible: true" "$report_file"; then
            echo "  ✓ REPRODUCIBLE (byte-for-byte identical to previous builds)"
        else
            echo "  ? UNKNOWN (first build or comparison pending)"
        fi
        echo ""
        echo "Testing:"
        echo "  To test reproducibility:"
        echo "    1. Run: sudo ./scripts/build-iso-phase2.sh --reproducible"
        echo "    2. Compare: ./scripts/verify-reproducible-builds.sh"
        echo ""
        echo "Reference:"
        echo "  Reproducible Builds: https://reproducible-builds.org/"
        echo "  SOURCE_DATE_EPOCH: https://reproducible-builds.org/docs/source-date-epoch/"
    } > "$report_file"

    log_success "Report: $report_file"
    cat "$report_file"
}

# Main execution
main() {
    log_info "MAYOTIX OS Phase 2: Reproducible Build Verification"
    echo ""

    # Check if ISOs exist
    local iso_files=($(find_iso_files))

    if [[ ${#iso_files[@]} -eq 0 ]]; then
        log_error "No Phase 2 ISOs found. Run: sudo ./scripts/build-iso-phase2.sh --reproducible"
    fi

    # Verify latest ISO
    local latest_iso="${iso_files[0]}"
    log_info "Latest ISO: $(basename $latest_iso)"
    echo ""

    check_iso_integrity "$latest_iso"

    echo ""

    # Compare with previous build if requested
    if [[ -n "$COMPARE_ISO" ]]; then
        compare_isos "$latest_iso" "$COMPARE_ISO"
    elif [[ ${#iso_files[@]} -gt 1 ]]; then
        log_info "Found ${#iso_files[@]} ISOs. Comparing with previous build..."
        echo ""
        compare_isos "$latest_iso" "${iso_files[1]}"
    else
        log_info "Only one ISO found. Cannot compare (first build?)"
        log_info "Next: Run build again and compare:"
        echo "  sudo ./scripts/build-iso-phase2.sh --reproducible"
        echo "  ./scripts/verify-reproducible-builds.sh"
    fi

    echo ""
    get_iso_metadata "$latest_iso"

    echo ""
    generate_report "$latest_iso"
}

main "$@"
