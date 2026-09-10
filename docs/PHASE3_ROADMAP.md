# MAYOTIX OS Phase 3: Desktop Environment & Application Sandboxing

## Overview
Phase 3 transforms the secure base system (Phase 2) into a user‑focused, hardened desktop experience with application sandboxing and a centralized security dashboard.

## Target Timeline
- **Start**: October 1, 2026
- **Duration**: 5 weeks (Oct 1 – Nov 4, 2026)
- **Goal**: Produce a bootable ISO (`mayotix-os-3.0-alpha-x86_64.iso`) with a hardened Wayland compositor, Flatpak/Bubblewrap sandboxed applications, a live Security Center GUI, and disposable workspace sessions.

## Weekly Milestones

### Week 1: Wayland Compositor & Hardened Display Server
- **Objective**: Replace X11 with a secure Wayland compositor (sway or labwc) locked down via IPC restrictions.
- **Deliverables**:
  - Custom Wayland compositor build with SELinux confinement.
  - IPC lockdown rules (Unix socket permissions, SELinux types).
  - Secure session launch scripts (`desktop/compositor/session-start.sh`).
  - Input device handling (libinput) with udev rules.
  - Basic status bar (waybar) with system tray.
  - Documentation: `docs/PHASE3_WEEK1_WAYLAND.md`.

### Week 2: Containerized Application Sandbox
- **Objective**: Integrate Flatpak and Bubblewrap for application isolation.
- **Deliverables**:
  - Flatpak repository setup with MAYOTIX curated runtimes.
  - Bubblewrap profiles for sandboxed CLI tools.
  - SELinux policies allowing Flatpak domains only.
  - Desktop file integration (`.desktop` files) with sandbox launch.
  - Test applications: hardened Firefox, LibreOffice, terminal.
  - Documentation: `docs/PHASE3_WEEK2_SANDBOX.md`.

### Week 3: Mayotix Security Center GUI
- **Objective**: Provide a live dashboard for SELinux, firewall, audit logs, and update status.
- **Deliverables**:
  - GTK/QML application (`mayotix-security-center`).
  - Live widgets:
    - SELinux mode and denials (via `ausearch`/`sealert`).
    - Firewall status (`firewall-cmd --list-all`).
    - Audit log summary (recent AVCs, integrity events).
    - Update timer status and last check.
  - D‑Bus service for real‑time updates.
  - Secure execution: runs confined in its own SELinux domain.
  - Documentation: `docs/PHASE3_WEEK3_SECURITY_CENTER.md`.

### Week 4: Ephemeral / Disposable Workspace Sessions
- **Objective**: Offer one‑time, throw‑away workspaces that leave no persistent data.
- **Deliverants**:
  - Script `mayotix-disposable-session` that spawns a new user namespace with temporary `/home` and `/tmp`.
  - Automatic cleanup on session exit (rm -rf temporary directories).
  - SELinux confinement ensuring no access to persistent home.
  - Integration with the display manager (GDM/sddm) to offer a “Disposable Session” entry.
  - Documentation: `docs/PHASE3_WEEK4_DISPOSABLE.md`.

### Week 5: End‑to‑End Verification & Phase 3 ISO Build
- **Objective**: Validate all Phase 3 features, run security audit, and produce the release ISO.
- **Deliverables**:
  - Full system boot tests (BIOS/UEFI) in QEMU.
  - Security audit script updated for Phase 3 controls (target ≥85/100).
  - proliferation of reproducibility (`SOURCE_DATE_EPOCH`).
  - GPG signing of the ISO and checksum generation.
  - Release notes (`docs/PHASE3_RELEASE_NOTES.md`).
  - Final ISO: `mayotix-os-3.0-alpha-x86_64.iso`.
  - Documentation: `docs/PHASE3_WEEK5_VERIFICATION.md`.

## Architecture Overview
```
+---------------------------------------------------------------+
|                    MAYOTIX OS Phase 3                       |
|                                                               |
|  +-------------------+   +------------------+   +-----------+ |
|  | Wayland Compositor|   | Security Center  |   | Flatpak   | |
|  | (sway/labwc)      |   | (GUI Dashboard)  |   | Apps      | |
|  +-------------------+   +------------------+   +-----------+ |
|          ^                         ^          ^           |
|          | IPC Lockdown (SELinux)  | D‑Bus    | Bubblewrap  |
|          v                         v          v           |
|  +-------------------+   +------------------+   +-----------+ |
|  | Input (libinput)  |   | Auditd / SELinux |   | Sandbox   | |
|  | + udev rules      |   | (live widgets)   |   | Profiles  | |
|  +-------------------+   +------------------+   +-----------+ |
|                                                               |
|  +-------------------+   +------------------+   +-----------+ |
|  | Update Mechanism |   | Disposable       |   | Kernel    | |
|  | (atomic/rollback)|   | Workspaces       |   | Hardening | |
|  +-------------------+   +------------------+   +-----------+ |
|                                                               |
+---------------------------------------------------------------+
```
All components run under SELinux enforcing with dedicated domains, and the base system inherits the Phase 2 hardening (kernel, firewall, audit, updates).

## Success Criteria (End of Week 5)
- ISO builds reproducibly and boots in both BIOS and UEFI modes.
- Wayland compositor starts without fallback to X11.
- Security Center GUI displays live SELinux, firewall, audit, and update data.
- Flatpak applications launch confined; Bubblewrap profiles enforce syscall filters.
- Disposable session option appears in the display manager and leaves no trace after logout.
- Security audit score ≥85/100 (goal: 95/100).
- All artifacts (ISO, checksums, SBOM, release notes) published via GitHub Release.

## Next Steps After Phase 3
- Phase 4: Developer Tooling & CI/CD Integration (containers, Buildah, Skopeo, automated testing).
- Phase 5: Hardened Networking & VPN (WireGuard, DNS-over-TLS, split tunneling).
- Phase 6: Multi‑User & Administration (RBAC, centralized logging, audit aggregation).

---
*MAYOTIX Development Team*  
*Roadmap Version: 1.0*  
*Date: 2026-09-10*