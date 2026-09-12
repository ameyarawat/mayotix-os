# MAYOTIX OS Phase 3 Week 3: Security Center GUI

## Overview

This document outlines the architecture and implementation details for the Mayotix Security Center. Designed for Phase 3 Week 3, the Security Center is a live, graphical dashboard for monitoring and auditing the core security postures of the MAYOTIX OS. It visualizes the defense-in-depth mechanisms engineered in earlier phases.

The Security Center aggregates data from:
1. **SELinux:** Current enforcement mode and recent AVC denials.
2. **Firewalld:** Service status and active zones.
3. **Audit/Integrity Engine:** Kernel event logs covering MAC/DAC events.
4. **OS Updates:** System update pending status (mocked for Week 3 framework validation).

## Architecture

The system uses a decoupled frontend-backend architecture integrated over the D-Bus session bus. 

### Frontend (`mayotix-security-center`)
- **Technology:** Python 3 + GTK3 (`gi.repository.Gtk`).
- **Function:** Renders responsive status cards (FlowBox) dynamically subscribing to D-Bus signals.
- **Confinement:** Confined within `mayotix_security_center_t` SELinux domain and executed from the Wayland compositor.

### Backend (`mayotix-security-center-daemon`)
- **Technology:** Python 3 + `dbus-python` / `gi`.
- **Function:** Runs as a systemd user service (`mayotix-security-center.service`), periodically invoking security binaries (e.g., `getenforce`, `firewall-cmd`, `ausearch`) to collect local metrics.
- **Interface:** Exposes `com.mayotix.SecurityCenter` on D-Bus. Emits `StatusUpdated` with a JSON payload.

## Implementation Details

### D-Bus IPC & Synchronization

The daemon registers to the D-Bus Session Bus as `com.mayotix.SecurityCenter` and broadcasts state updates every 30 seconds. The frontend GTK loop registers a `DBusGMainLoop` listener for the `StatusUpdated` signal. 
Parsing logic securely interprets JSON payloads. In case the daemon isn't responsive, the frontend implements a native fallback worker thread for immediate feedback.

### Systemd Service Hardening

The `mayotix-security-center.service` unit follows the strict systemd hardening template established in previous phases:
- `NoNewPrivileges=yes`
- `ProtectSystem=strict`
- `RestrictNamespaces=yes`
- Allows network metadata (`AF_NETLINK`/`AF_INET`) but restricts unneeded system calls and process capabilities.

### SELinux Policy (`mayotix_security_center.te`)

A dedicated SELinux Type Enforcement (TE) policy ensures the Security Center backend and frontend cannot be leveraged to pivot into other systems:
- Defines `mayotix_security_center_t`.
- **Requires:** Explicit `require {}` definitions for `xdm_t`, `unconfined_t`, and target types.
- **Allowed Capabilities:** `read` access to `/var/log/audit/audit.log` (via `auditd_log_t`).
- **IPC:** Allows `unix_stream_socket` interactions to facilitate D-Bus capabilities.

## Usage and Integration

### Manual Run
To run the daemon directly:
```bash
python3 desktop/security-center/mayotix-security-center-daemon
```

To run the GUI:
```bash
python3 desktop/security-center/mayotix-security-center
```

### Installation
1. Policy module compilation:
   ```bash
   checkmodule -M -m -o security/selinux/mayotix_security_center.mod security/selinux/mayotix_security_center.te
   semodule_package -o security/selinux/mayotix_security_center.pp -m security/selinux/mayotix_security_center.mod
   semodule -i security/selinux/mayotix_security_center.pp
   ```
2. Enable Systemd Service:
   Copy `services/mayotix-security-center.service` to `~/.config/systemd/user/` and `systemctl --user enable --now mayotix-security-center.service`.

## Security Features

1. **Least Privilege Backend:** The daemon runs as a restricted unit, only invoking read-only queries (e.g. `firewall-cmd --state`). It lacks modification rights.
2. **SELinux Confinement:** Domain transition ensures compromised UI components cannot access user `$HOME` arbitrarily.
3. **Robust IPC:** Pure message-passing structure (JSON over D-Bus) limits serialization-based attacks.

## Files Created

```
desktop/
├── security-center/
│   ├── mayotix-security-center          # Python/GTK UI
│   └── mayotix-security-center-daemon   # Python/D-Bus Backend
├── apps/
│   └── mayotix-security-center.desktop  # Desktop Entry
services/
└── mayotix-security-center.service      # Systemd Hardened User Unit
security/
└── selinux/
    └── mayotix_security_center.te       # SELinux Contexts
docs/
└── PHASE3_WEEK3_SECURITY_CENTER.md      # This Document
```
