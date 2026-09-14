# MAYOTIX OS Phase 4 Week 5: Verification Procedures

This document outlines the procedures to build and verify the MAYOTIX OS Phase 4 ISO image and security controls.

## Building the Phase 4 ISO

The unified build script integrates all Phase 4 components into a bootable ISO image.

### Prerequisites

The build process requires the following tools (available in most Linux distributions):
- `dracut` (for initramfs generation)
- `xorriso` (for ISO image creation)
- `checkmodule` and `semodule_package` (for SELinux policy compilation)
- `sha256sum` and `sha512sum` (for checksums)
- `podman`, `buildah`, `skopeo` (container engine tools)
- `cosign` and `trivy` (supply chain security)
- `shellcheck` and `hadolint` (linting tools)

> **Note**: If any of these tools are missing, the build will warn but continue with placeholders for validation purposes.

### Usage

```bash
# Standard build (non-reproducible)
sudo ./scripts/build-iso-phase4.sh

# Reproducible build (sets SOURCE_DATE_EPOCH for deterministic output)
sudo ./scripts/build-iso-phase4.sh --reproducible

# Quick build (skips some validations for faster iteration)
sudo ./scripts/build-iso-phase4.sh --quick

# Test-only mode (validates staging without building ISO)
sudo ./scripts/build-iso-phase4.sh --test-only
```

### Output

Upon successful completion, the build script will generate:
- `build/mayotix-os-4.0-alpha-x86_64.iso` - The bootable ISO image
- `build/mayotix-os-4.0-alpha-x86_64.iso.sha256` - SHA256 checksum
- `build/mayotix-os-4.0-alpha-x86_64.iso.sha512` - SHA512 checksum
- `build/PHASE4_BUILD_REPORT.txt` - Human-readable build report
- `build/PHASE4_BUILD_MANIFEST.json` - Machine-readable build manifest

## Running the Phase 4 Security Audit

The comprehensive audit script evaluates the system against the Phase 4 security specification.

### Usage

```bash
# Full audit (requires root for some checks)
sudo ./scripts/conduct-security-audit-phase4.sh

# Dry run (shows what would be checked without making changes)
sudo ./scripts/conduct-security-audit-phase4.sh --dry-run

# Report-only mode (outputs just the score)
sudo ./scripts/conduct-security-audit-phase4.sh --report-only
```

### Scoring

The audit evaluates 8 categories for a maximum of 100 points:
1. Base Kernel & System Hardening (10 pts)
2. SELinux 6-Module Policy Confinement (15 pts)
3. Wayland Compositor & Application Sandboxing (15 pts)
4. Security Center GUI & Ephemeral Sessions (15 pts)
5. Rootless Container Engine Hardening (15 pts)
6. Supply Chain Image Integrity & Signature Gating (15 pts)
7. Devbox Ephemeral Isolation & Pre-commit Linters (10 pts)
8. Reproducible Build Verification (5 pts)

**Target Score**: ≥95/100  
**Stretch Goal**: 100/100

### Output

The audit script generates:
- `build/PHASE4_SECURITY_AUDIT_REPORT.txt` - Detailed report with scores per category
- Console output with summary and pass/fail determination

## Verifying the Build

To verify the integrity of the built ISO:

```bash
# Verify SHA256 checksum
sha256sum -c build/mayotix-os-4.0-alpha-x86_64.iso.sha256

# Verify SHA512 checksum
sha512sum -c build/mayotix-os-4.0-alpha-x86_64.iso.sha512
```

Both commands should return `OK` if the files are intact.

## Testing the ISO

The resulting ISO can be tested in a virtual machine (e.g., QEMU, VirtualBox, VMware) or burned to USB hardware.

### Quick Test with QEMU

```bash
qemu-system-x86_64 -enable-kvm -m 4096 -cdrom build/mayotix-os-4.0-alpha-x86_64.iso -boot d
```

This will boot the ISO in a KVM-accelerated virtual machine with 4GB RAM.

### Expected Boot Menu

Upon boot, you should see a GRUB menu with the following entries:
1. MAYOTIX OS 4.0 (Hardened Developer Workstation - Phase 4)
2. MAYOTIX OS 4.0 (Development Container - Ephemeral Devbox)
3. MAYOTIX OS 4.0 Recovery (Permissive Mode)

Selecting the first entry will boot the hardened workstation with all Phase 4 security features enabled.

## Post-Installation Verification

After booting the ISO (or running in a VM), you can verify specific Phase 4 features:

### 1. Check Container Engine Hardening
```bash
# Inside the live system, check registries.conf
cat /etc/containers/registries.conf
# Should show restrictions to signed registries only

# Check storage.conf
cat /etc/containers/storage.conf
# Should show overlay storage with size limits

# Verify the hardening script exists and is executable
ls -l /usr/local/sbin/configure-container-hardening
```

### 2. Verify Supply Chain Security
```bash
# Check the signature policy
cat /etc/containers/policy.json
# Should require signatures

# Test the Cosign verification script
/usr/local/sbin/verify-container-image.sh --help

# Test the Trivy scanning script
/usr/local/sbin/scan-container-vulnerabilities.sh --help
```

### 3. Test Devbox Ephemeral Environment
```bash
# Launch an ephemeral devbox
mayotix-devbox.sh --ephemeral --network none

# Inside the container, verify:
#   - Non-root user (id -u should return 1000)
#   - ~/Projects mounted read-write
#   - $HOME mounted read-only
#   - /tmp is a tmpfs (mount | grep tmp)
#   - No access to host system directories (e.g., ls /host-system-test should fail)
```

### 4. Check Pre-commit Hooks
```bash
# In a git repository, verify the hooks are installed
git config core.hooksPath
# Should point to .githooks

# Check that the pre-commit hook exists and is executable
ls -l .githooks/pre-commit
```

### 5. Run the Compliance Suite
```bash
# Verify the system meets Phase 4 baseline requirements
/usr/local/sbin/test-phase4-compliance.sh
```

### 6. Check SELinux Policies
```bash
# List loaded SELinux modules
semodule -l | grep mayotix
# Should show all 6 modules: mayotix, mayotix_desktop, mayotix_sandbox, mayotix_security_center, mayotix_disposable, mayotix_container
```

## Continuous Integration

The GitHub Actions workflow (`.github/workflows/build.yml`) has been updated to include Phase 4 validation:
- Builds the ISO using `scripts/build-iso-phase4.sh`
- Runs the security audit using `scripts/conduct-security-audit-phase4.sh`
- Uploads the ISO and audit report as artifacts
- Fails the build if the audit score is below the target (≥95/100)

## Troubleshooting

### Missing Build Dependencies
If the build warns about missing tools, install them via your distribution's package manager:
- On Fedora/RHEL: `sudo dnf install dracut xorriso libselinux-utils podman buildah skopeo cosign trivy ShellCheck hadolint`
- On Ubuntu/Debian: `sudo apt-get install dracut xorriso libselinux1-utils podman buildah skopeo cosign trivy shellcheck hadolint`

### SELinux Policy Compilation Errors
If SELinux policies fail to compile:
1. Check the syntax of the `.te` files in `security/selinux/`
2. Ensure you have the SELinux development packages installed
3. Run `./scripts/lint-selinux-policies.sh` for static analysis

### Audit Score Below Target
If the security audit score is below 95/100:
1. Review the audit report (`build/PHASE4_SECURITY_AUDIT_REPORT.txt`)
2. Address deficiencies in the categories marked as PARTIAL or FAIL
3. Re-run the audit after making corrections

---
*MAYOTIX OS Engineering Team*
*Phase 4 Week 5 — September 2026*