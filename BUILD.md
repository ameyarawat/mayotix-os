# Build Instructions

## Prerequisites

### System Requirements

- **Host OS:** Linux (Fedora 40+, Debian, or Ubuntu 22.04+)
- **RAM:** 4GB minimum (8GB recommended)
- **Disk Space:** 20GB free (ISO creation + build artifacts)
- **CPU:** x86-64 processor
- **Internet:** Required for downloading packages

### Required Tools

```bash
# Fedora
sudo dnf install -y \
  git \
  mock \
  rpm-build \
  dracut \
  grub2-tools \
  grub2-tools-efi \
  genisoimage \
  mkisofs \
  syslinux \
  efibootmgr \
  dosfstools \
  e2fsprogs \
  parted \
  gnupg \
  jq

# Debian/Ubuntu
sudo apt-get install -y \
  git \
  build-essential \
  dracut \
  grub-common \
  grub-efi-amd64 \
  grub-pc \
  xorriso \
  mtools \
  dosfstools \
  e2fsprogs \
  parted \
  gnupg \
  jq
```

### Optional (for VM testing)

```bash
# QEMU/KVM
sudo dnf install qemu-kvm qemu-system-x86 virt-manager  # Fedora
sudo apt-get install qemu-kvm qemu-system-x86          # Debian/Ubuntu

# VirtualBox
# Download from https://www.virtualbox.org
```

## Building the ISO

### Step 1: Clone Repository

```bash
git clone https://github.com/mayotix/mayotix-os.git
cd mayotix-os
```

### Step 2: Set Up Build Environment

```bash
# Create build directories
mkdir -p build/{iso,root,boot,efi}

# Copy kernel and bootloader configs
cp -r boot/grub2 build/boot/
cp -r boot/dracut build/boot/

# Initialize SELinux policies
cp -r security/selinux build/selinux
```

### Step 3: Build Minimal ISO

```bash
./scripts/build-iso.sh
```

**Output:**
- `mayotix-os-1.0-alpha.iso` (bootable ISO)
- `mayotix-os-1.0-alpha.iso.sha256` (checksums)

### Step 4: Verify Build

```bash
# Verify ISO integrity
sha256sum -c mayotix-os-1.0-alpha.iso.sha256

# Expected output:
# mayotix-os-1.0-alpha.iso: OK
```

## Testing the Build

### QEMU/KVM (Recommended for Development)

```bash
# Boot ISO in QEMU
qemu-system-x86_64 \
  -cdrom mayotix-os-1.0-alpha.iso \
  -m 4G \
  -smp 2 \
  -enable-kvm \
  -boot d \
  -display gtk

# Boot with debugging (verbose output)
KERNEL_DEBUG=1 qemu-system-x86_64 \
  -cdrom mayotix-os-1.0-alpha.iso \
  -m 4G \
  -enable-kvm \
  -boot d \
  -nographic
```

### VirtualBox

```bash
# Create VM
vboxmanage createvm --name "MAYOTIX Test" --ostype Linux_64 --register

# Attach ISO
vboxmanage storageattach "MAYOTIX Test" \
  --storagectl "IDE Controller" \
  --port 0 --device 0 --type dvddrive \
  --medium mayotix-os-1.0-alpha.iso

# Start VM
vboxmanage startvm "MAYOTIX Test"
```

### Physical USB Boot (Safety Warning)

```bash
# DANGER: This will overwrite the target drive

# Identify USB device
lsblk

# Write to USB (/dev/sdX is example - VERIFY CAREFULLY)
sudo dd if=mayotix-os-1.0-alpha.iso of=/dev/sdX bs=4M status=progress
sudo sync

# Eject
sudo eject /dev/sdX
```

## Reproducible Builds

### Goal

Independent builders can reproduce identical ISOs:

```bash
# Build with deterministic flags
./scripts/build-iso.sh --reproducible

# Verify
sha256sum mayotix-os-1.0-alpha.iso
# Compare with published checksum
```

### Build Container (Docker)

```bash
# Use container for guaranteed reproducibility
docker build -f Dockerfile.build -t mayotix-build:latest .

# Build inside container
docker run --rm -v $(pwd):/build mayotix-build:latest \
  /build/scripts/build-iso.sh --reproducible
```

## Customization

### Modify Kernel Configuration

```bash
# Edit kernel config
nano kernel/config

# Rebuild
./scripts/build-iso.sh --rebuild-kernel
```

### Add Custom Packages

Edit `packages/base.txt`:

```
systemd
grub2
kernel
# Add your packages here
```

Then rebuild:

```bash
./scripts/build-iso.sh
```

### Customize Desktop Theme

Edit `desktop/theme/mayotix.gschema.override`:

```ini
[org.gnome.desktop.interface]
gtk-theme='mayotix-dark'
icon-theme='mayotix-icons'
```

## Troubleshooting

### Build Fails with "Dracut not found"

```bash
# Make sure dracut is installed
sudo dnf install -y dracut  # Fedora
sudo apt-get install -y dracut  # Debian/Ubuntu

# Verify
dracut --version
```

### QEMU: "KVM acceleration not available"

```bash
# Check if KVM is available
kvm-ok  # Intel CPU
lscpu | grep svm  # AMD CPU

# If not available, remove -enable-kvm flag
qemu-system-x86_64 -cdrom mayotix-os-1.0-alpha.iso -m 4G
```

### ISO Too Large

```bash
# Reduce ISO size by removing unnecessary packages
rm -rf build/root/usr/share/doc
rm -rf build/root/usr/share/man

# Rebuild
./scripts/build-iso.sh
```

### Boot Hangs at GRUB

1. Check GRUB configuration: `cat boot/grub2/grub.cfg`
2. Enable debugging: `GRUB_TERMINAL=serial GRUB_CMDLINE_LINUX="debug"`
3. Check kernel boot parameters in `boot/dracut/dracut.conf`

## Security Checks

Before releasing:

```bash
# Scan ISO for secrets
./scripts/security-check.sh --scan-iso mayotix-os-1.0-alpha.iso

# Verify signatures
gpg --verify mayotix-os-1.0-alpha.iso.gpg

# Check SELinux policies
semodule -l | grep mayotix

# Audit systemd services
systemd-analyze security
```

## Release Process

### Sign ISO

```bash
# Import private key (kept secure, not in Git)
gpg --import private-key.asc

# Sign checksum file
gpg --detach-sign --armor mayotix-os-1.0-alpha.iso.sha256

# Verify signature
gpg --verify mayotix-os-1.0-alpha.iso.sha256.asc
```

### Generate SBOM

```bash
./scripts/generate-sbom.sh mayotix-os-1.0-alpha.iso > sbom.json
```

### Publish Release

```bash
# Upload to S3
aws s3 cp mayotix-os-1.0-alpha.iso \
  s3://mayotix-releases/mayotix-os-1.0-alpha.iso

aws s3 cp mayotix-os-1.0-alpha.iso.sha256 \
  s3://mayotix-releases/mayotix-os-1.0-alpha.iso.sha256

aws s3 cp mayotix-os-1.0-alpha.iso.sha256.asc \
  s3://mayotix-releases/mayotix-os-1.0-alpha.iso.sha256.asc
```

---

**Last Updated:** 2026-09-06  
**MAYOTIX OS Build Team**
