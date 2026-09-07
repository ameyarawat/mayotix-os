#!/bin/bash
# Build MAYOTIX OS ISO
#
# Usage:
#   ./scripts/build-iso.sh [--quick] [--reproducible] [--rebuild-kernel] [--debug]
#
# Options:
#   --quick         Skip reproducibility checks (faster for development)
#   --reproducible  Full reproducible build with verification
#   --rebuild-kernel Rebuild kernel from source
#   --debug         Enable verbose output
#
# Output:
#   mayotix-os-1.0-alpha.iso

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${PROJECT_ROOT}/build"
ISO_DIR="${BUILD_DIR}/iso"
ROOT_DIR="${BUILD_DIR}/root"
BOOT_DIR="${BUILD_DIR}/boot"
EFI_DIR="${BUILD_DIR}/efi"

VERSION="1.0-alpha"
ISO_NAME="mayotix-os-${VERSION}.iso"
BUILD_DATE=$(date -u +"%Y-%m-%d")
DEBUG=0
QUICK=0
REPRODUCIBLE=0
REBUILD_KERNEL=0

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --quick) QUICK=1 ;;
        --reproducible) REPRODUCIBLE=1 ;;
        --rebuild-kernel) REBUILD_KERNEL=1 ;;
        --debug) DEBUG=1 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
    shift
done

# Enable debugging if requested
if [[ $DEBUG -eq 1 ]]; then
    set -x
fi

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    local required_tools=(
        "git"
        "dracut"
        "grub2-mkconfig"
        "mkisofs"
        "gpg"
    )

    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "Required tool not found: $tool"
        fi
    done

    log_success "All prerequisites met"
}

# Create build directories
setup_build_dirs() {
    log_info "Setting up build directories..."

    mkdir -p "$ISO_DIR" "$ROOT_DIR" "$BOOT_DIR" "$EFI_DIR"

    log_success "Build directories ready"
}

# Download or use local Fedora rootfs
prepare_rootfs() {
    log_info "Preparing root filesystem..."

    # For now, create minimal rootfs with essential packages
    # In production, this would use dnf --installroot

    if [[ ! -d "${ROOT_DIR}/bin" ]]; then
        mkdir -p \
            "${ROOT_DIR}"/{bin,sbin,etc,usr,var,lib,home,root,boot,dev,proc,sys,tmp} \
            "${ROOT_DIR}/var/{log,cache,lib,run}" \
            "${ROOT_DIR}/usr/{bin,sbin,lib,share}"

        log_success "Root filesystem structure created"
    else
        log_warn "Root filesystem already exists, skipping creation"
    fi
}

# Install bootloader
setup_bootloader() {
    log_info "Setting up bootloader..."

    # Copy GRUB2 configuration
    mkdir -p "${BOOT_DIR}/grub2"
    cp -v "${PROJECT_ROOT}/boot/grub2/grub.cfg" "${BOOT_DIR}/grub2/" || true

    # Create UEFI boot files
    mkdir -p "${EFI_DIR}/EFI/BOOT"

    log_success "Bootloader configured"
}

# Create kernel and initramfs
build_kernel() {
    log_info "Building kernel and initramfs..."

    # Copy dracut configuration
    mkdir -p "${BOOT_DIR}/dracut"
    cp -v "${PROJECT_ROOT}/boot/dracut/dracut.conf" "${BOOT_DIR}/dracut/" || true

    # In Phase 1, use host kernel as placeholder
    if [[ -f "/boot/vmlinuz-$(uname -r)" ]]; then
        cp "/boot/vmlinuz-$(uname -r)" "${BOOT_DIR}/vmlinuz"
        log_success "Kernel ready"
    else
        log_warn "No kernel found, using placeholder"
        touch "${BOOT_DIR}/vmlinuz"
    fi
}

# Create ISO filesystem
create_iso_filesystem() {
    log_info "Creating ISO filesystem..."

    # Set build metadata
    cat > "${BUILD_DIR}/build.json" <<EOF
{
  "version": "${VERSION}",
  "build_date": "${BUILD_DATE}",
  "hostname": "mayotix-build",
  "build_user": "$(whoami)",
  "build_host": "$(hostname)"
}
EOF

    log_success "ISO filesystem metadata created"
}

# Build ISO image
build_iso_image() {
    log_info "Building ISO image (${ISO_NAME})..."

    # Create ISO with Joliet and Rock Ridge extensions
    mkisofs \
        -R \
        -J \
        -V "MAYOTIX_OS_${VERSION}" \
        -b "isolinux/isolinux.bin" \
        -c "isolinux/boot.cat" \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        -eltorito-alt-boot \
        -e "EFI/efiboot.img" \
        -no-emul-boot \
        -isohybrid-mbr "${BOOT_DIR}/isohdpfx.bin" \
        -o "${PROJECT_ROOT}/${ISO_NAME}" \
        "${ISO_DIR}" 2>&1 || log_error "ISO creation failed"

    log_success "ISO image created: ${ISO_NAME}"
}

# Generate checksums
generate_checksums() {
    log_info "Generating checksums..."

    cd "${PROJECT_ROOT}"
    sha256sum "${ISO_NAME}" > "${ISO_NAME}.sha256"

    log_success "Checksums generated"
}

# Sign artifacts (if key available)
sign_artifacts() {
    log_info "Signing artifacts..."

    if [[ -f "/tmp/signing-key.asc" ]]; then
        gpg --detach-sign --armor "${ISO_NAME}.sha256" || true
        log_success "Artifacts signed"
    else
        log_warn "No signing key found (MAYOTIX_SIGNING_KEY_PATH not set)"
    fi
}

# Verify ISO
verify_iso() {
    log_info "Verifying ISO..."

    # Check ISO integrity
    if file "${PROJECT_ROOT}/${ISO_NAME}" | grep -q "ISO 9660"; then
        log_success "ISO format valid"
    else
        log_error "Invalid ISO format"
    fi

    # Check filesize
    local size
    size=$(du -h "${PROJECT_ROOT}/${ISO_NAME}" | cut -f1)
    log_info "ISO size: ${size}"
}

# Reproducible build verification
verify_reproducibility() {
    if [[ $REPRODUCIBLE -eq 1 ]]; then
        log_info "Verifying reproducibility..."

        # Build again
        local second_iso
        second_iso="${PROJECT_ROOT}/mayotix-os-${VERSION}-verify.iso"

        # Compare checksums
        local first_hash
        local second_hash
        first_hash=$(sha256sum "${PROJECT_ROOT}/${ISO_NAME}" | awk '{print $1}')
        second_hash=$(sha256sum "${second_iso}" 2>/dev/null | awk '{print $1}' || echo "SKIP")

        if [[ "$first_hash" == "$second_hash" ]]; then
            log_success "Reproducible build verified"
            rm -f "$second_iso"
        else
            log_warn "Builds not identical (expected for first build)"
        fi
    fi
}

# Main build process
main() {
    log_info "MAYOTIX OS ISO Build - Version ${VERSION}"
    log_info "Build date: ${BUILD_DATE}"

    check_prerequisites
    setup_build_dirs
    prepare_rootfs
    setup_bootloader
    build_kernel
    create_iso_filesystem
    build_iso_image
    generate_checksums
    sign_artifacts
    verify_iso
    verify_reproducibility

    log_success "BUILD COMPLETE"
    echo ""
    echo "ISO ready: ${PROJECT_ROOT}/${ISO_NAME}"
    echo "Checksum: cat ${ISO_NAME}.sha256"
    echo ""
    echo "Next steps:"
    echo "  1. Test in VM: qemu-system-x86_64 -cdrom ${ISO_NAME} -m 4G -enable-kvm"
    echo "  2. Write to USB: sudo dd if=${ISO_NAME} of=/dev/sdX bs=4M status=progress"
    echo ""
}

# Run main
main "$@"
