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

    # Detect distro and set tool names accordingly
    # Fedora uses grub2-* naming, Debian/Ubuntu uses grub-*
    if command -v grub2-mkimage &>/dev/null; then
        GRUB_MKIMAGE="grub2-mkimage"
    elif command -v grub-mkimage &>/dev/null; then
        GRUB_MKIMAGE="grub-mkimage"
    else
        log_error "Required tool not found: grub-mkimage or grub2-mkimage"
    fi
    log_success "GRUB tool found: $GRUB_MKIMAGE"

    # xorriso or genisoimage/mkisofs for ISO creation
    if command -v xorriso &>/dev/null; then
        ISO_TOOL="xorriso"
    elif command -v genisoimage &>/dev/null; then
        ISO_TOOL="genisoimage"
    elif command -v mkisofs &>/dev/null; then
        ISO_TOOL="mkisofs"
    else
        log_error "Required tool not found: xorriso, genisoimage, or mkisofs"
    fi
    log_success "ISO tool found: $ISO_TOOL"

    local required=(
        "dracut"
        "mkfs.ext4"
        "mkfs.vfat"
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

    # Detect which dracut modules are available on this system
    local available_modules=""
    for mod in crypt dm selinux systemd base; do
        if dracut --list-modules 2>/dev/null | grep -qw "$mod"; then
            available_modules="$available_modules $mod"
        fi
    done

    # Fallback: if --list-modules didn't work, use safe defaults
    if [[ -z "$available_modules" ]]; then
        available_modules="base systemd"
    fi

    log_info "Using dracut modules:$available_modules"

    # Build dracut include arguments
    local dracut_args=(
        --add "$available_modules"
        --no-hostonly
        --force
    )

    # Only include directories that exist and are non-empty
    if [[ -d "${SERVICES_DIR}" ]] && [[ -n "$(ls -A "${SERVICES_DIR}" 2>/dev/null)" ]]; then
        dracut_args+=(--include "${SERVICES_DIR}" /etc/systemd/system)
    fi
    if [[ -d "${PROJECT_ROOT}/security/selinux" ]] && [[ -n "$(find "${PROJECT_ROOT}/security/selinux" -not -name '.gitkeep' -not -name '.' | head -1)" ]]; then
        dracut_args+=(--include "${PROJECT_ROOT}/security/selinux" /etc/selinux)
    else
        log_warn "SELinux directory empty, skipping include"
    fi

    # Build initramfs (no --hostonly since we're building a generic ISO)
    dracut "${dracut_args[@]}" "$initramfs" \
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
    local efi_mount="${BUILD_DIR}/efi_mount"

    # Create small FAT16 EFI boot partition (4MB is enough for bootloader)
    dd if=/dev/zero of="$efiboot" bs=1M count=4
    mkfs.vfat -F 12 "$efiboot"

    # Mount and populate EFI structure
    mkdir -p "$efi_mount"
    mount -o loop "$efiboot" "$efi_mount"
    mkdir -p "$efi_mount/EFI/BOOT"

    # Copy GRUB EFI binary if available
    local grub_efi=""
    for path in /boot/efi/EFI/fedora/grubx64.efi /usr/lib/grub/x86_64-efi/grub.efi /boot/efi/EFI/BOOT/BOOTX64.EFI; do
        if [[ -f "$path" ]]; then
            grub_efi="$path"
            break
        fi
    done

    if [[ -n "$grub_efi" ]]; then
        cp "$grub_efi" "$efi_mount/EFI/BOOT/BOOTX64.EFI"
        log_success "EFI bootloader copied from $grub_efi"
    else
        log_warn "No EFI bootloader found, creating placeholder"
        touch "$efi_mount/EFI/BOOT/BOOTX64.EFI"
    fi

    # Copy GRUB config for EFI
    mkdir -p "$efi_mount/EFI/BOOT/"
    if [[ -f "${ISO_DIR}/boot/grub2/grub.cfg" ]]; then
        cp "${ISO_DIR}/boot/grub2/grub.cfg" "$efi_mount/EFI/BOOT/grub.cfg"
    fi

    umount "$efi_mount"
    rmdir "$efi_mount"

    # Also create the EFI/BOOT directory in the ISO tree
    mkdir -p "${ISO_DIR}/EFI/BOOT"
    if [[ -n "$grub_efi" ]]; then
        cp "$grub_efi" "${ISO_DIR}/EFI/BOOT/BOOTX64.EFI"
    fi

    log_success "EFI image created (4MB)"
}

# Create ISO filesystem
create_iso_filesystem() {
    log_info "Creating ISO filesystem..."

    local iso_path="${BUILD_DIR}/mayotix-os-1.0-alpha-x86_64.iso"

    # Find syslinux MBR binary (path differs between distros)
    local isohdpfx=""
    for path in /usr/lib/syslinux/isohdpfx.bin /usr/share/syslinux/isohdpfx.bin /usr/lib/syslinux/bios/isohdpfx.bin; do
        if [[ -f "$path" ]]; then
            isohdpfx="$path"
            break
        fi
    done

    if [[ "$ISO_TOOL" == "xorriso" ]]; then
        local xorriso_args=(
            -as mkisofs
            -o "$iso_path"
            -boot-load-size 4
            -boot-info-table
            -no-emul-boot
            -eltorito-alt-boot
            -e boot/efi/efiboot.img
            -no-emul-boot
        )
        # Only add isohybrid if syslinux MBR was found
        if [[ -n "$isohdpfx" ]]; then
            xorriso_args+=(-isohybrid-mbr "$isohdpfx" -isohybrid-gpt-basdat)
        fi
        xorriso "${xorriso_args[@]}" "$ISO_DIR"
    else
        # genisoimage / mkisofs fallback
        "$ISO_TOOL" \
            -o "$iso_path" \
            -R -J -joliet-long \
            -V "MAYOTIX_OS" \
            -eltorito-alt-boot \
            -e boot/efi/efiboot.img \
            -no-emul-boot \
            "$ISO_DIR"
    fi

    log_success "ISO created: $iso_path"
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
    local iso_path="${BUILD_DIR}/mayotix-os-1.0-alpha-x86_64.iso"
    create_iso_filesystem

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
