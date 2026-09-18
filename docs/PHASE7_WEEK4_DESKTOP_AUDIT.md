# MAYOTIX OS Phase 7 Week 4: Defender Desktop Center, IPC Daemon Integration & Comprehensive Security Audit

## 1. Architectural Overview & Vision

Phase 7 completes the MAYOTIX OS Defender & Security Lab Environment. Across Weeks 1, 2, and 3:
- **Week 1**: Built the capability-bounded network packet capture engine (`CAP_NET_RAW` / `CAP_NET_ADMIN`), profile filters (WireGuard Egress, DoT DNS, Leak Sniffer), and dedicated `mayotix_defender_t` SELinux MAC policy.
- **Week 2**: Created the isolated PCAP Dissector Sandbox (`dissect-pcap.sh`) enforced by Bubblewrap unshared network namespaces, zero capabilities, and automated threat scanning (`scan-pcap.py`) under `mayotix_dissector_t`.
- **Week 3**: Implemented process volatile memory acquisition (`dump-process.sh` under `CAP_SYS_PTRACE`), secret sanitizer (`sanitize-dump.py`), runtime threat monitor (`threat-monitor.py`), and `mayotix_forensics_t` SELinux confinement.

**Phase 7 Week 4** brings these capabilities together into a cohesive desktop security experience:
1. **Privileged IPC Daemon Integration (`daemon/mayotix-daemon.py`)**:
   - JSON-RPC 2.0 endpoints for all Defender subsystems (`capture.*`, `pcap.*`, `forensic.*`, `monitor.*`).
   - Secure parameter validation whitelisting safe capture profiles and sanitizing execution paths.
   - Bounded POSIX capabilities without exposing unconfined root execution to desktop userspace.
2. **Native Defender Desktop Control Center GUI (`desktop/defender/mayotix-defender-gui.py`)**:
   - Lightweight GTK3 / Wayland graphical control interface.
   - **Tab 1: Packet Inspection**: Profile selection, start/stop toggle, live packet statistics, and capture storage management.
   - **Tab 2: Live Threat Behavioral Monitor**: Process scan trigger, active detection heuristics display, and threat alert feed.
   - **Tab 3: Forensics & PCAP Analysis Sandbox**: Offline dissector launcher, sanitizer engine, and JSON inspection report viewers.
   - Built-in headless validation (`--dry-run`, `--json`) for continuous integration testing.
3. **XDG Desktop Launcher Integration (`desktop/applications/mayotix-defender.desktop`)**:
   - Registered under standard system security categories (`System;Security;`).
   - Wayland compositor compatible with standard startup notifications.
4. **Comprehensive Phase 7 Security Audit Harness (`scripts/conduct-security-audit-phase7.sh`)**:
   - Evaluates 8 security dimensions totaling 100 points:
     * Base Kernel & System Hardening (10 pts)
     * SELinux Policy Confinement (10 pts)
     * Bubblewrap Sandboxing & Dissector Isolation (10 pts)
     * Network Privacy Stack (20 pts)
     * Capability-Bounded Packet Inspection (15 pts)
     * Automated PCAP Threat Scanning & Sandbox (15 pts)
     * Process Memory Forensics & Sanitization (10 pts)
     * Runtime Threat Monitor, IPC & Desktop Center (10 pts)

```
+-------------------------------------------------------------------------------+
|                      MAYOTIX OS DEFENDER DESKTOP (GTK3 / Wayland)             |
|                                                                               |
|   +-----------------------------------------------------------------------+   |
|   | [Tab 1: Packet Inspection] [Tab 2: Threat Monitor] [Tab 3: Forensics] |   |
|   +-----------------------------------------------------------------------+   |
|   | - Profile Selector          - Process Tree Watcher - Dissector Sandbox|   |
|   | - Live Packet Counters      - Reverse Shell Alert  - Secret Sanitizer |   |
|   | - /var/log/mayotix/captures - Stdio Socket Check   - Offline Reports  |   |
|   +-----------------------------------+-----------------------------------+   |
|                                       |                                       |
+---------------------------------------|---------------------------------------+
                                        v JSON-RPC 2.0 Unix Domain Socket
+-------------------------------------------------------------------------------+
|                     PRIVILEGED IPC DAEMON (daemon/mayotix-daemon.py)          |
|                                                                               |
|   RPC Endpoints:                                                              |
|     - capture.start, capture.stop, capture.status, capture.list_profiles      |
|     - pcap.analyze, pcap.dissect                                              |
|     - forensic.dump, forensic.sanitize                                        |
|     - monitor.scan                                                            |
|                                                                               |
|   Confinement: Bounded POSIX Capabilities (CAP_NET_ADMIN, CAP_SYS_PTRACE)     |
+-------------------------------------------------------------------------------+
         |                              |                               |
         v                              v                               v
+------------------+         +--------------------+         +-------------------+
| mayotix-capture  |         | dissect-pcap.sh /  |         | dump-process.sh / |
| (CAP_NET_RAW)    |         | scan-pcap.py       |         | threat-monitor.py |
| mayotix_defender |         | mayotix_dissector  |         | mayotix_forensics |
+------------------+         +--------------------+         +-------------------+
```

---

## 2. Privileged IPC Daemon Endpoints

The IPC daemon (`daemon/mayotix-daemon.py`) provides capability-bounded privilege separation between desktop user interfaces and underlying system security mechanisms.

| RPC Method | Parameters | Description |
|:---|:---|:---|
| `capture.start` | `{"interface": str, "profile": str, "duration": int}` | Starts capability-bounded packet capture into `/var/log/mayotix/captures/`. |
| `capture.stop` | `{"handle": str}` | Stops an active capture session. |
| `capture.status` | `{}` | Returns active capture sessions, packet counters, and storage usage. |
| `capture.list_profiles`| `{}` | Returns available capture profiles (`wireguard-egress`, `dot-dns`, `leak-sniffer`). |
| `pcap.analyze` | `{"file": str}` | Runs heuristic threat analysis against a PCAP file. |
| `pcap.dissect` | `{"file": str, "output": str}` | Launches isolated Bubblewrap dissector sandbox. |
| `forensic.dump` | `{"pid": int}` | Acquires process volatile memory artifacts under `CAP_SYS_PTRACE`. |
| `forensic.sanitize` | `{"file": str}` | Redacts private keys, tokens, and credentials from memory dumps. |
| `monitor.scan` | `{}` | Executes runtime process tree scan for reverse shells and anomalies. |

---

## 3. Desktop Control Center GUI Specifications

The Defender GUI (`desktop/defender/mayotix-defender-gui.py`) is implemented using PyGObject (GTK+ 3) designed for native Wayland compositors:

### Tab 1: Packet Inspection
- **Capture Profile Selector**: Dropdown supporting `WireGuard Egress (UDP 51820)`, `DNS-over-TLS (Port 853)`, and `Cleartext Leak Sniffer (Ports 53/80)`.
- **Interface Selection**: Detection and selection of default active network interfaces.
- **Session Control**: Start/Stop toggle button with live spinner and capture duration timer.
- **Telemetry Display**: Displays active packet counts, bytes captured, and storage target path.

### Tab 2: Live Threat Behavioral Monitor
- **Real-Time Process Scan**: On-demand and periodic evaluation of active processes against threat rules:
  * `REVERSE_SHELL_DETECTION`: Socket file descriptors mapped to interactive shells.
  * `NETWORK_DAEMON_SHELL_SPAWN`: Web servers or network daemons spawning command interpreters.
  * `WRITABLE_DIR_EXECUTION`: Binaries executing out of `/tmp` or `/dev/shm`.
  * `UNAUTHORIZED_SOCKET_BINDING`: Non-standard listening ports.
- **Alert TreeView**: Color-coded threat severity table (CRITICAL, HIGH, MEDIUM, LOW) with process IDs, names, and command lines.

### Tab 3: Forensics & PCAP Analysis Sandbox
- **Offline Dissector Launcher**: Dissects `.pcap` files in a zero-socket, zero-capability Bubblewrap sandbox.
- **Artifact Sanitizer View**: Redacts sensitive secrets from `/proc` memory dumps before export.
- **Interactive JSON Viewer**: Scored compliance reports and finding breakdown.

---

## 4. Phase 7 Comprehensive Security Audit Specification

The audit harness (`scripts/conduct-security-audit-phase7.sh`) validates the overall security posture across 8 foundational dimensions:

```
================================================================================
            MAYOTIX OS Phase 7: Comprehensive Security Audit                    
================================================================================
  Operating System    : MAYOTIX OS 5.0-alpha
  Timestamp           : 2026-09-18 07:08:15 UTC
  Pass Threshold      : 100/100

  Security Category Breakdown:
    1. Base Kernel & System Hardening               : 10/10 pts
    2. SELinux Policy Confinement                   : 10/10 pts
    3. Bubblewrap Sandboxing & Dissector Isolation  : 10/10 pts
    4. Network Privacy Stack (DoT/WireGuard/Tor/FW) : 20/20 pts
    5. Capability-Bounded Packet Inspection         : 15/15 pts
    6. Automated PCAP Threat Scanning & Sandbox     : 15/15 pts
    7. Process Memory Forensics & Sanitization      : 10/10 pts
    8. Runtime Threat Monitor, IPC & Desktop Center : 10/10 pts
  --------------------------------------------------------------------------------
  Total Compliance Score : 100/100 pts (PASS - 100% COMPLIANT)
================================================================================
```

---

## 5. Verification & Usage Guide

### CLI Invocations
```bash
# Test GUI headless validation
python3 desktop/defender/mayotix-defender-gui.py --dry-run --json

# Run Phase 7 Comprehensive Security Audit
sudo ./scripts/conduct-security-audit-phase7.sh

# Run Phase 7 Week 4 Verification Harness
sudo ./scripts/verify-defender-week4.sh --dry-run
```
