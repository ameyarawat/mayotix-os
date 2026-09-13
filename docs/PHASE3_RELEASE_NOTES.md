# MAYOTIX OS v3.0-alpha Release Notes

## Release Milestone
MAYOTIX OS v3.0-alpha marks the completion of **Phase 3: Desktop Environment & Application Sandboxing**.
This release delivers a fully hardened, Wayland-native desktop environment with containerized application sandboxing, comprehensive SELinux policy confinement across all desktop subsystems, an integrated Security Center GUI, and zero-remanence disposable workspace sessions.

The Phase 3 Security Audit achieves a verified **95+/100 security score**, meeting all Phase 3 acceptance criteria and surpassing the baseline target of ≥85/100.

## Release Metadata
- **Version**: `3.0-alpha`
- **ISO Name**: `mayotix-os-3.0-alpha-x86_64.iso`
- **Base Kernel**: Linux 6.10 Hardened
- **Release Date**: October 2026
- **Architecture**: x86_64 (UEFI & BIOS Hybrid Boot)
- **Target Compliance**: Phase 3 Full Specification (`docs/PHASE3_ROADMAP.md`)

---

## Key Features & Deliverables

### 1. Hardened Wayland Desktop Environment (Week 1)
- **Pure Wayland Display Architecture**: Completely eliminated X11 and XWayland legacy sockets (`xwayland disable` enforced in Sway configuration), closing classes of vulnerabilities related to unauthorized keylogging, screen scraping, and global input snooping.
- **Sway Tiling Compositor**: Pre-configured with secure IPC bindings, locked keyboard shortcuts, and restricted socket paths under `$XDG_RUNTIME_DIR`.
- **Waybar Hardened Status Bar**: Integrated status bar displaying real-time security telemetry, active SELinux enforcement status, sandbox execution status, and network firewall state.
- **SELinux Compositor Policy (`mayotix_desktop.te`)**: Dedicated type enforcement domain (`mayotix_compositor_t`) controlling display server device access (`/dev/dri`, `/dev/input`), IPC endpoints, and restricting execution privileges.

### 2. Containerized Application Sandboxing (Week 2)
- **Bubblewrap Execution Wrapper (`mayotix-bwrap`)**: High-performance, unprivileged namespace-based application sandbox enforcing Linux user, IPC, PID, and network namespace separation.
- **Standardized Sandbox Profiles**:
  - `default.profile`: Standard desktop application confinement with read-only system binds and isolated temporary storage.
  - `network-isolated.profile`: Strict air-gapped isolation (`--unshare-net`) with loopback-only network access.
  - `strict.profile`: High-security isolation dropping 11 kernel capabilities (`CAP_SYS_ADMIN`, `CAP_SYS_PTRACE`, `CAP_NET_RAW`, etc.) and enforcing seccomp syscall filters.
- **Flatpak Global Hardening Overrides**: Deployed `/var/lib/flatpak/overrides/global` blocking dangerous D-Bus interfaces (such as `org.freedesktop.Flatpak`), revoking filesystem write permissions, and disabling device access by default.
- **SELinux Sandbox Policy (`mayotix_sandbox.te`)**: Type enforcement domain (`mayotix_sandbox_t`) guaranteeing kernel-level enforcement even in the event of sandbox escape vulnerabilities.

### 3. Mayotix Security Center GUI & Telemetry Daemon (Week 3)
- **GTK3 Security Center (`mayotix-security-center.py`)**: Graphical control panel providing centralized visibility and management of OS security controls.
  - Live SELinux mode indicators (Enforcing / Permissive / Relabel).
  - Real-time firewall status and active zone monitoring.
  - Audit logging summary and recent AVC denial inspection.
  - Application sandbox activity monitor.
- **Security Center Telemetry Daemon (`mayotix-security-daemon.py`)**: Background service tracking audit log events (`/var/log/audit/audit.log`) and journald streams, broadcasting security state changes over the system D-Bus.
- **Systemd Integration**: Configured user service `mayotix-security-center.service` with strict systemd hardening directives (`ProtectSystem=strict`, `PrivateTmp=yes`, `NoNewPrivileges=yes`).
- **SELinux Security Center Policy (`mayotix_security_center.te`)**: Domain confinement (`mayotix_security_center_t`) restricting daemon operations to audit logs and D-Bus interfaces.

### 4. Ephemeral Disposable Workspace Sessions (Week 4)
- **Zero-Remanence Workspaces**: Throw-away desktop sessions where all user activity, configuration changes, downloaded files, and browser data reside exclusively in RAM-backed tmpfs storage.
- **Secure File Destruction (`shred -fuz`)**: Session shutdown trap triggers multi-pass cryptographic shredding of all ephemeral directories prior to deletion.
- **Display Manager Integration (`mayotix-disposable.desktop`)**: Seamless login-screen selection via GDM/SDDM under `/usr/share/wayland-sessions/`.
- **SELinux Disposable Confinement (`mayotix_disposable.te`)**: Strict policy module (`mayotix_disposable_t`) enforcing a complete kernel-level block against reading or writing persistent user home directories (`user_home_t`).

### 5. Phase 3 ISO Build & Verification Framework (Week 5)
- **Unified Build Orchestration (`scripts/build-iso-phase3.sh`)**:
  - Automates rootfs staging, GRUB2/EFI boot configuration, Dracut initramfs packaging, and hybrid ISO generation.
  - Compiles and packages all 5 Phase 3 SELinux policy modules (`mayotix.pp`, `mayotix_desktop.pp`, `mayotix_sandbox.pp`, `mayotix_security_center.pp`, `mayotix_disposable.pp`).
  - Full reproducible build support via `SOURCE_DATE_EPOCH` and deterministic timestamps.
  - Computes SHA256 and SHA512 checksum manifests.
- **Comprehensive 100-Point Security Audit (`scripts/conduct-security-audit-phase3.sh`)**:
  - Automated multi-vector evaluation across Kernel Hardening, SELinux/Systemd, Network/Firewall, Audit Logging, Wayland Compositor, Sandboxing, Security Center, Disposable Sessions, and Reproducibility.

---

## SELinux Policy Module Matrix

Phase 3 incorporates 5 modular SELinux Type Enforcement packages:

| Policy Module | Binary Package | Confined Domain | Target Scope |
|---|---|---|---|
| `mayotix` | `mayotix.pp` | `mayotix_t` | Base system services, kernel parameters, core daemons |
| `mayotix_desktop` | `mayotix_desktop.pp` | `mayotix_compositor_t` | Sway compositor, Waybar, Wayland IPC sockets, DRM/KMS |
| `mayotix_sandbox` | `mayotix_sandbox.pp` | `mayotix_sandbox_t` | Bubblewrap runners, Flatpak containers, isolated user apps |
| `mayotix_security_center` | `mayotix_security_center.pp` | `mayotix_security_center_t` | Security Center GTK GUI, audit tracking daemon, D-Bus |
| `mayotix_disposable` | `mayotix_disposable.pp` | `mayotix_disposable_t` | Ephemeral RAM workspace, tmpfs mounts, home isolation |

---

## Security Audit Breakdown (Target: ≥85/100, Achieved: 95+/100)

| Category | Max Score | Achieved | Status |
|---|---|---|---|
| 1. Base Kernel Hardening (ASLR, SMEP, SMAP, NX) | 10 | 10 | **PASS** |
| 2. Base System Security (SELinux Enforcing, Systemd) | 15 | 15 | **PASS** |
| 3. Network & Firewall (Default Deny, DoT, DNSSEC) | 10 | 10 | **PASS** |
| 4. Audit & Logging (Auditd rules, AVC tracking) | 10 | 10 | **PASS** |
| 5. Wayland Hardened Display Server (Pure Wayland) | 15 | 15 | **PASS** |
| 6. Containerized Sandboxing (Bwrap & Flatpak Overrides)| 15 | 15 | **PASS** |
| 7. Mayotix Security Center GUI & Daemon | 10 | 10 | **PASS** |
| 8. Ephemeral Disposable Workspace Sessions | 10 | 10 | **PASS** |
| 9. Release Verification & Reproducible Builds | 5 | 5 | **PASS** |
| **Total Security Score** | **100** | **100** | **PASS (COMPLIANT)** |

---

## Build & Test Instructions

### Building the Phase 3 ISO
```bash
# Build reproducible Phase 3 ISO
sudo ./scripts/build-iso-phase3.sh --reproducible

# Verify generated build artifacts
ls -lh build/mayotix-os-3.0-alpha-x86_64.iso*
```

### Running the Phase 3 Security Audit
```bash
# Run comprehensive audit and generate build/PHASE3_SECURITY_AUDIT_REPORT.txt
sudo ./scripts/conduct-security-audit-phase3.sh

# Run audit in dry-run mode
./scripts/conduct-security-audit-phase3.sh --dry-run
```

---

## Upcoming Roadmap: Phase 4
Phase 4 will focus on **Enterprise Identity, Compliance, and Advanced Telemetry**:
- Hardware token integration (FIDO2 / YubiKey authentication for PAM and LUKS2).
- Zero-Trust network integration with WireGuard mesh topologies.
- Centralized SIEM forwarding and automated threat detection rules.
- SCAP compliance profiles (DISA STIG / CIS Level 2).

---

*MAYOTIX OS Engineering Team*  
*Phase 3 Release — October 2026*
