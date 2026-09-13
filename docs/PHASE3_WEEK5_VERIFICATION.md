# MAYOTIX OS Phase 3: Week 5 Verification Procedures

## Overview
This document outlines the end-to-end verification and testing procedures for the **MAYOTIX OS v3.0-alpha (Phase 3)** release.

## 1. ISO Build Verification
After running the build script, verify the integrity of the generated ISO image.

```bash
# Build the ISO
sudo ./scripts/build-iso-phase3.sh --reproducible

# Verify presence and size of artifacts
ls -lh build/mayotix-os-3.0-alpha-x86_64.iso*

# Verify checksums (SHA256)
sha256sum -c build/mayotix-os-3.0-alpha-x86_64.iso.sha256
```

## 2. Security Audit Verification
The Phase 3 security controls are validated using the `conduct-security-audit-phase3.sh` script.

```bash
# Run security audit
sudo ./scripts/conduct-security-audit-phase3.sh

# The script generates a report in build/PHASE3_SECURITY_AUDIT_REPORT.txt
# Ensure the score is >= 95/100
cat build/PHASE3_SECURITY_AUDIT_REPORT.txt
```

## 3. Functionality Testing
Verify core Phase 3 features within a virtualized environment (QEMU).

### A. Boot Test (BIOS/UEFI)
Ensure the image boots correctly using both standards.
```bash
# Test BIOS boot
./scripts/test-boot.sh build/mayotix-os-3.0-alpha-x86_64.iso --bios

# Test UEFI boot
./scripts/test-boot.sh build/mayotix-os-3.0-alpha-x86_64.iso --uefi
```

### B. Security Center & Wayland Compositor
1. Boot the live environment.
2. Verify Sway compositor initializes (Wayland session).
3. Check `Waybar` telemetry indicators.
4. Launch `mayotix-security-center.py` and confirm SELinux mode and firewall status display correctly.
5. Verify `mayotix-bwrap` confinement by running a sandboxed application and inspecting audit logs (`/var/log/audit/audit.log`).

## 4. Reproducible Build Check
Verify that the build is deterministic.
```bash
# Run verification script
./scripts/verify-reproducible-builds.sh --verbose
```
