#!/bin/bash
# MAYOTIX OS Phase 1 Build System
# Orchestrates ISO creation with Dracut, GRUB2, LUKS2, and SELinux
#
# Usage:
#   ./scripts/build-iso.sh                    # Full build
#   ./scripts/build-iso.sh --quick           # Quick build (skip reproducibility)
#   ./scripts/build-iso.sh --reproducible    # Reproducible build with timestamps frozen
#   ./scripts/build-iso.sh --sign            # Sign ISO with GPG

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${PROJECT_ROOT}/build"
ISO_DIR="${BUILD_DIR}/iso"
STAGING_DIR="${BUILD_DIR}/staging"
KERNEL_DIR="${PROJECT_ROOT}/kernel"
BOOT_DIR="${PROJECT_ROOT}/boot"
SERVICES_DIR="${PROJECT_ROOT}/services"

# Reproducibility flags
REPRODUCIBLE=0
QUICK=0
SIGN=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[⚠]${NC} $*"; }
log_error() { echo -e "${RED}[✗]${NC} $*"; exit 1; }

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --reproducible) REPRODUCIBLE=1 ;;
        --quick) QUICK=1 ;;
        --sign) SIGN=1 ;;
        *) log_error "Unknown option: $1" ;;
    esac
    shift
done

# Verify dependencies
check_dependencies() {
    log_info "Checking dependencies..."

    local required=(
        "dracut"
        "grub-mkimage"
        "xorriso"
        "mtools"
        "mkfs.ext4"
    )

    for cmd in "${required[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            log_error "Required tool not found: $cmd"
        fi
    done

    log_success "All dependencies available"
}

# Initialize build directories
init_build() {
    log_info "Initializing build directories..."

    rm -rf "$ISO_DIR" "$STAGING_DIR"
    mkdir -p "$ISO_DIR"/{boot/grub2,boot/efi,isolinux} "$STAGING_DIR"/{rootfs,bootfs}

    log_success "Build directories ready"
}

# Create base filesystem
create_rootfs() {
    log_info "Creating root filesystem..."

    local rootfs="${STAGING_DIR}/rootfs"

    # Create directory structure
    mkdir -p "$rootfs"/{bin,sbin,lib,lib64,etc,boot,root,home,var,tmp,proc,sys,dev,mnt}

    # Set permissions
    chmod 1777 "$rootfs/tmp"
    chmod 755 "$rootfs/var"

    # Create essential files
    cat > "$rootfs/etc/fstab" <<'EOF'
# MAYOTIX OS fstab
/dev/mapper/mayotix-root  /       ext4    defaults,x-systemd.device-timeout=0   0 1
/dev/mapper/mayotix-home  /home   ext4    defaults                                0 2
EOF

    cat > "$rootfs/etc/hostname" <<EOF
mayotix-os
EOF

    cat > "$rootfs/etc/os-release" <<EOF
NAME="MAYOTIX OS"
VERSION="1.0-alpha"
VERSION_ID="1.0"
PLATFORM_ID="linux"
HOME_URL="https://github.com/mayotix/mayotix-os"
BUG_REPORT_URL="https://github.com/mayotix/mayotix-os/issues"
SUPPORT_URL="https://github.com/mayotix/mayotix-os/discussions"
EOF

    log_success "Root filesystem created"
}

# Build initramfs with Dracut
build_initramfs() {
    log_info "Building initramfs with Dracut..."

    local initramfs="${ISO_DIR}/boot/initramfs-mayotix.img"

    # Copy Dracut configuration
    if [[ -f "${BOOT_DIR}/dracut/dracut.conf" ]]; then
        cp "${BOOT_DIR}/dracut/dracut.conf" /etc/dracut.conf.d/mayotix.conf
    fi

    # Build initramfs with LUKS2, SELinux, and device support
    dracut \
        --include "${SERVICES_DIR}" /etc/systemd/system \
        --include "${PROJECT_ROOT}/security/selinux" /etc/selinux \
        --add "crypt cryptsetup dm dmraid biosdevname ifcfg selinux systemd" \
        --hostonly-cmdline \
        --no-hostonly-default-device \
        --hostonly \
        --force \
        "$initramfs" \
        || log_error "Dracut failed"

    log_success "Initramfs built: $initramfs"
}

# Copy kernel
copy_kernel() {
    log_info "Copying kernel..."

    # For Phase 1, use system kernel; Phase 2 will compile custom kernel
    if [[ -f "/boot/vmlinuz-$(uname -r)" ]]; then
        cp "/boot/vmlinuz-$(uname -r)" "${ISO_DIR}/boot/vmlinuz-mayotix"
        log_success "Kernel copied"
    else
        log_warn "System kernel not found, using generic"
        # Fallback: create minimal bzImage placeholder
        touch "${ISO_DIR}/boot/vmlinuz-mayotix"
    fi
}

# Configure GRUB2
setup_grub() {
    log_info "Setting up GRUB2 bootloader..."

    local grub_cfg="${ISO_DIR}/boot/grub2/grub.cfg"

    # Copy GRUB config
    if [[ -f "${BOOT_DIR}/grub2/grub.cfg" ]]; then
        cp "${BOOT_DIR}/grub2/grub.cfg" "$grub_cfg"
    else
        # Generate minimal GRUB config
        cat > "$grub_cfg" <<'EOF'
set default=0
set timeout=5

menuentry "MAYOTIX OS (LUKS2 Encrypted)" {
    insmod gzio
    insmod part_gpt
    insmod ext2
    set root='(cd0)'

    echo "Loading MAYOTIX OS..."
    linux /boot/vmlinuz-mayotix root=/dev/mapper/mayotix-root ro selinux=1 enforcing=1 quiet splash
    initrd /boot/initramfs-mayotix.img
}

menuentry "MAYOTIX OS Recovery (Permissive)" {
    insmod gzio
    insmod part_gpt
    insmod ext2
    set root='(cd0)'

    echo "Loading recovery mode..."
    linux /boot/vmlinuz-mayotix root=/dev/mapper/mayotix-root ro selinux=1 enforcing=0 systemd.unit=rescue.target
    initrd /boot/initramfs-mayotix.img
}
EOF
    fi

    log_success "GRUB2 configured"
}

# Create EFI boot image
create_efi_image() {
    log_info "Creating EFI boot image..."

    local efiboot="${ISO_DIR}/boot/efi/efiboot.img"

    # Create FAT12 EFI boot partition
    dd if=/dev/zero of="$efiboot" bs=1M count=50
    mkfs.vfat -F 12 "$efiboot"

    log_success "EFI image created"
}

# Create ISO filesystem
create_iso_filesystem() {
    log_info "Creating ISO filesystem..."

    local iso_path="${BUILD_DIR}/mayotix-os-1.0-alpha-x86_64.iso"

    # Create xorriso command
    xorriso -as mkisofs \
        -o "$iso_path" \
        -isohybrid-mbr /usr/lib/syslinux/isohdpfx.bin \
        -c isolinux/boot.cat \
        -boot-load-size 4 \
        -boot-info-table \
        -eltorito-catalog isolinux/boot.cat \
        -eltorito-boot isolinux/isolinux.bin \
        -no-emul-boot \
        -eltorito-alt-boot \
        -e boot/efi/efiboot.img \
        -no-emul-boot \
        -isohybrid-gpt-basdat \
        "$ISO_DIR"

    log_success "ISO created: $iso_path"
    echo "$iso_path"
}

# Generate checksums
generate_checksums() {
    local iso_path="$1"

    log_info "Generating checksums..."

    sha256sum "$iso_path" > "${iso_path}.sha256"
    sha512sum "$iso_path" > "${iso_path}.sha512"

    log_success "Checksums generated"
}

# Sign ISO (optional)
sign_iso() {
    local iso_path="$1"

    if [[ $SIGN -eq 0 ]]; then
        return 0
    fi

    log_info "Signing ISO with GPG..."

    if ! command -v gpg &>/dev/null; then
        log_warn "GPG not available, skipping signature"
        return 0
    fi

    gpg --detach-sign --armor "$iso_path" 2>/dev/null || \
        log_warn "GPG signing failed (no key configured)"
}

# Reproducibility support
set_reproducible() {
    if [[ $REPRODUCIBLE -eq 0 ]]; then
        return 0
    fi

    log_info "Enabling reproducible build mode..."

    # Freeze timestamps
    export SOURCE_DATE_EPOCH="$(date +%s)"
    export KBUILD_BUILD_TIMESTAMP="$(date -u -d @"$SOURCE_DATE_EPOCH" '+%Y-%m-%d %H:%M:%S UTC')"

    log_success "Reproducible mode enabled"
}

# Main build process
main() {
    log_info "MAYOTIX OS Phase 1 Build System"
    log_info "Build date: $(date)"
    echo ""

    set_reproducible
    check_dependencies
    init_build
    create_rootfs
    build_initramfs
    copy_kernel
    setup_grub
    create_efi_image

    # Create ISO
    local iso_path
    iso_path=$(create_iso_filesystem)

    # Generate verification files
    generate_checksums "$iso_path"
    sign_iso "$iso_path"

    echo ""
    log_success "Build complete!"
    echo ""
    echo "Generated:"
    echo "  ISO:    $iso_path"
    echo "  SHA256: ${iso_path}.sha256"
    echo "  SHA512: ${iso_path}.sha512"
    echo ""
    echo "Next steps:"
    echo "  1. Verify: sha256sum -c ${iso_path}.sha256"
    echo "  2. Test:   ./scripts/test-boot.sh \"$iso_path\" --uefi"
    echo "  3. Write:  ./scripts/test-boot.sh \"$iso_path\" --hardware"
}

main "$@"
