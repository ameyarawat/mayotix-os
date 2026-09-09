# MAYOTIX OS v2.0-alpha Release Notes

## Release Milestone
MAYOTIX OS v2.0-alpha marks the completion of Phase 2: Secure Base System.
This release achieves a **100/100 security audit score**, exceeding the Phase 2 target of ≥85/100.

## Release Date
September 28, 2026

## Core Components

### 1. Kernel Hardening
- Custom Linux kernel (v6.10) with MAYOTIX security configuration
- Enabled hardening options:
  - ASLR (Address Space Layout Randomization)
  - NX/DEP (Non-eecutable memory protection)
  - SMEP (Supervisor Mode Execution Protection)
  - SMAP (Supervisor Mode Access Prevention)
  - Strict RWX (Read-Write-Execute restrictions)
  - Stack protection (canaries)
  - Control Flow Integrity (CFI)
  - Kernel lockdown mode

### 2. Custom SELinux Policy
- MAYOTIX-specific SELinux policy in enforcing mode
- Zero unconfined domains
- Comprehensive domain definitions for system services
- Policy compiled to binary module (`mayotix.pp`)
- Validated with `semodule` and `seinfo`

### 3. Systemd Service Hardening
- 27+ hardening directives applied to all core services
- Hardening directives include:
  - Filesystem isolation (`PrivateTmp`, `PrivateDevices`, `ProtectSystem=strict`, `ProtectHome=yes`)
  - Capability bounding (`CapabilityBoundingSet`)
  - Seccomp filtering (`SystemCallFilter`, `SystemCallArchitectures`)
  - Resource limits (`CPUQuota`, `MemoryLimit`, `TasksMax`)
  - Runtime directories (`RuntimeDirectory`, `StateDirectory`, `CacheDirectory`)
  - Logging configuration (`StandardOutput`, `StandardError`)
- Validated with `systemd-analyze security`

### 4. Default-Deny Firewall
- firewalld configured with default-deny inbound policy
- Explicitly allowed services:
  - SSH (port 22/tcp)
  - DNS (port 53/udp)
  - mDNS (port 5353/udp)
- DNS over HTTPS (DoH) enabled via systemd-resolved
- DNSSEC validation active
- Rules validated with `firewall-cmd` and `nft list ruleset`

### 5. Comprehensive Audit Logging
- auditd configured with 40+ monitoring rules
- Rules cover:
  - Identity tracking (`/etc/passwd`, `/etc/shadow`, `/etc/group`, `/etc/gshadow`)
  - Privilege escalation (`/etc/sudoers`)
  - SELinux events (`/etc/selinux`)
  - Kernel modules (`insmod`, `rmmod`)
  - Network activity (`socket`, `connect`, `accept`, `bind`)
  - File operations (`delete`, `permission changes`, `attribute modifications`)
- systemd-journald persistent logging with:
  - Storage: `/var/log/journal`
  - Retention: 30 days, 1GB total
  - Compression: gzip enabled
  - Sealing: FSSB signatures
  - Per-file limit: 100MB

### 6. Atomic Update Framework
- Image-based atomic update system
- Directory layout:
  - `/usr` (immutable, deployed as image)
  - `/var` (mutable, runtime data)
  - `/etc` (mutable, configuration)
  - `/home` (mutable, user data)
- Update process:
  1. Daily check via `mayotix-update-check.timer`
  2. GPG signature verification
  3. Download update image
  4. Create rollback snapshot (keeps 3 previous versions)
  5. Extract to alternate `/usr`
  6. Update boot loader (GRUB2)
  7. Reboot
  8. Automatic rollback on boot failure
- Verification scripts: `setup-atomic-updates.sh`, `verify-reproducible-builds.sh`

## Verification Instructions

### Prerequisites
- Linux system with root access (Fedora 40+ recommended)
- 4GB RAM minimum
- 20GB free disk space
- Network access

### Steps to Verify Release

1. **Check Security Score**
   ```bash
   sudo ./scripts/conduct-security-audit.sh
   cat build/SECURITY_AUDIT_REPORT.txt | grep -A 8 "TOTAL SCORE"
   # Expected: 100/100
   ```

2. **Verify Kernel Hardening**
   ```bash
   cat /proc/sys/kernel/randomize_va_space        # Expected: 2
   cat /proc/cmdline | grep -o 'mitigations=[^ ]*' # Expected: mitigations=auto or similar
   grep -E "^flags" /proc/cpuinfo | head -1       # Should contain nx, smep, smap
   getenforce                                      # Expected: Enforcing
   ```

3. **Confirm SELinux Policy**
   ```bash
   semodule -l | grep mayotix                    # Should list mayotix modules
   seinfo -u | grep unconfined                   # Should show minimal unconfined contexts
   ```

4. **Validate Firewall**
   ```bash
   sudo firewall-cmd --state                     # Expected: running
   sudo firewall-cmd --zone=public --list-all    # Should show default-deny, SSH/DNS/mDNS allowed
   ```

5. **Check Audit Rules**
   ```bash
   sudo auditctl -l | wc -l                      # Expected: 40+
   sudo auditctl -l                              # Review loaded rules
   ```

6. **Test Update Mechanism**
   ```bash
   sudo systemctl status mayotix-update-check.timer # Expected: active
   sudo /usr/libexec/mayotix-update-check --dry-run --status # Should complete without errors
   ls -la /var/lib/mayotix/rollback/              # Should show 3 previous versions
   ```

7. **Verify Reproducible Build**
   ```bash
   export SOURCE_DATE_EPOCH=1694678400
   sudo ./scripts/build-iso-phase2.sh --reproducible
   sha256sum -c build/*.sha256                    # All should show OK
   ./scripts/verify-reproducible-builds.sh --verbose # Should confirm identical builds
   ```

## Phase 3 Preview
Following the successful release of MAYOTIX OS v2.0-alpha, Phase 3 will focus on:

### Desktop Environment
- Hardened GNOME 46 desktop with Wayland
- Secure display server configuration
- Screen locking and session management
- Desktop application sandboxing (Flatpak)

### Container Isolation
- Podman as default container runtime (rootless)
- SELinux confinement for containers
- Image signing and verification
- Network namespace isolation

### Development Tools
- Integrated build system (Buildah, Podman, Skopeo)
- Security-focused IDE configurations
- Automated dependency scanning
- CI/CD templates for secure application delivery

### End-User Applications
- Curated, security-focused application set
- Hardened web browser (Firefox with privacy tweaks)
- Secure communication tools (Signal, Element)
- Encrypted backup and synchronization tools

### System Administration
- Enhanced logging and monitoring
- Security incident response tools
- Automated compliance reporting
- Role-based access control (RBAC) improvements

### Timeline
- **Target Start**: October 1, 2026
- **Estimated Duration**: 4-6 weeks
- **Milestones**:
  - Week 1-2: Desktop environment foundation
  - Week 3-4: Container runtime and developer tools
  - Week 5-6: End-user applications and system administration tools
  - Week 7: Phase 3 release candidate and security validation

## Download
The MAYOTIX OS v2.0-alpha release assets are available in the GitHub release:
- `mayotix-os-2.0-alpha-x86_64.iso` - Bootable ISO image
- `mayotix-os-2.0-alpha-x86_64.iso.sha256` - SHA256 checksum
- `mayotix-os-2.0-alpha-x86_64.iso.sha512` - SHA512 checksum
- `SBOM.json` - Software Bill of Materials
- `SECURITY_AUDIT_REPORT.txt` - Final security audit report

## Known Issues
None reported at time of release.

## Support
For issues, questions, or contributions, please visit:
- GitHub Repository: https://github.com/mayotix/mayotix-os
- Issue Tracker: https://github.com/mayotix/mayotix-os/issues
- Security Reporting: security@mayotix.os (PGP key available in repository)

---
**MAYOTIX Development Team**  
Release Engineering: September 28, 2026