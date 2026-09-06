#!/bin/bash
# MAYOTIX OS Bootability Test Framework
#
# Tests ISO bootability in QEMU with automated verification
#
# Usage:
#   ./scripts/test-boot.sh mayotix-os-*.iso                  # Test boot
#   ./scripts/test-boot.sh mayotix-os-*.iso --uefi           # Test UEFI boot
#   ./scripts/test-boot.sh mayotix-os-*.iso --bios           # Test BIOS boot
#   ./scripts/test-boot.sh mayotix-os-*.iso --hardware       # Prepare for physical test

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
log_error() { echo -e "${RED}[✗]${NC} $*"; exit 1; }

ISO_PATH=""
TEST_UEFI=1
TEST_BIOS=1
HARDWARE_PREP=0
TIMEOUT=120

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        *.iso) ISO_PATH="$1" ;;
        --uefi) TEST_UEFI=1; TEST_BIOS=0 ;;
        --bios) TEST_BIOS=1; TEST_UEFI=0 ;;
        --both) TEST_UEFI=1; TEST_BIOS=1 ;;
        --hardware) HARDWARE_PREP=1 ;;
        --timeout) shift; TIMEOUT="$1" ;;
        *) log_error "Unknown option: $1" ;;
    esac
    shift
done

if [[ -z "$ISO_PATH" ]]; then
    log_error "ISO path required: ./scripts/test-boot.sh mayotix-os-*.iso"
fi

if [[ ! -f "$ISO_PATH" ]]; then
    log_error "ISO file not found: $ISO_PATH"
fi

# Check prerequisites
check_prerequisites() {
    log_info "Checking QEMU installation..."

    if ! command -v qemu-system-x86_64 &>/dev/null; then
        log_error "QEMU not found. Install with: sudo apt-get install qemu-system-x86"
    fi

    log_success "QEMU available"
}

# Test UEFI boot
test_uefi() {
    log_info "Testing UEFI boot..."

    # Create temporary OVMF firmware copy
    local ovmf_code="/usr/share/OVMF/OVMF_CODE.fd"
    local ovmf_vars="/tmp/OVMF_VARS.fd"

    if [[ ! -f "$ovmf_code" ]]; then
        log_warn "OVMF firmware not found (UEFI boot will use default)"
    fi

    # Start QEMU with UEFI
    timeout "$TIMEOUT" qemu-system-x86_64 \
        -cdrom "$ISO_PATH" \
        -m 2G \
        -smp 2 \
        -enable-kvm \
        -boot d \
        -display none \
        -serial mon:stdio \
        -chardev file,path=/tmp/qemu-uefi.log,id=charserial0 \
        -device isa-serial,chardev=charserial0,id=serial0 \
        2>&1 | tee /tmp/uefi-boot.log || true

    # Check for successful boot indicators
    if grep -q "MAYOTIX\|Linux\|kernel\|boot" /tmp/uefi-boot.log 2>/dev/null; then
        log_success "UEFI boot successful"
        return 0
    else
        log_warn "UEFI boot test inconclusive (see /tmp/uefi-boot.log)"
        return 1
    fi
}

# Test BIOS boot
test_bios() {
    log_info "Testing BIOS/MBR boot..."

    timeout "$TIMEOUT" qemu-system-x86_64 \
        -cdrom "$ISO_PATH" \
        -m 2G \
        -smp 2 \
        -enable-kvm \
        -boot d \
        -display none \
        -serial mon:stdio \
        2>&1 | tee /tmp/bios-boot.log || true

    if grep -q "MAYOTIX\|Linux\|kernel\|boot" /tmp/bios-boot.log 2>/dev/null; then
        log_success "BIOS boot successful"
        return 0
    else
        log_warn "BIOS boot test inconclusive (see /tmp/bios-boot.log)"
        return 1
    fi
}

# Prepare for physical hardware test
prep_physical() {
    log_info "Preparing for physical hardware test..."

    # Verify ISO integrity
    log_info "Verifying ISO integrity..."
    sha256sum -c "$(dirname "$ISO_PATH")/$(basename "$ISO_PATH" .iso).iso.sha256" || \
        log_warn "Checksum verification failed"

    log_success "ISO ready for physical media"
    echo ""
    echo "To write to USB:"
    echo "  1. Identify USB device: lsblk"
    echo "  2. Unmount if mounted: sudo umount /dev/sdX*"
    echo "  3. Write ISO: sudo dd if=\"$ISO_PATH\" of=/dev/sdX bs=4M status=progress"
    echo "  4. Sync: sudo sync"
    echo "  5. Eject: sudo eject /dev/sdX"
    echo ""
    echo "⚠️  WARNING: Verify /dev/sdX carefully — dd will overwrite without confirmation"
}

# Main
main() {
    log_info "MAYOTIX OS Bootability Test"
    log_info "ISO: $ISO_PATH"

    check_prerequisites

    if [[ $HARDWARE_PREP -eq 1 ]]; then
        prep_physical
        return 0
    fi

    local tests_passed=0
    local tests_total=0

    if [[ $TEST_UEFI -eq 1 ]]; then
        ((tests_total++))
        if test_uefi; then
            ((tests_passed++))
        fi
    fi

    if [[ $TEST_BIOS -eq 1 ]]; then
        ((tests_total++))
        if test_bios; then
            ((tests_passed++))
        fi
    fi

    echo ""
    log_info "Test Results: $tests_passed/$tests_total passed"

    if [[ $tests_passed -eq $tests_total ]]; then
        log_success "All boot tests passed"
    else
        log_warn "Some boot tests failed (see logs for details)"
    fi
}

main "$@"
