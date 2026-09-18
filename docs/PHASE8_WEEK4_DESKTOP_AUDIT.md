# MAYOTIX OS Phase 8 Week 4: Labs Desktop Studio, Incident Console & Comprehensive Security Audit

## 1. Architectural Overview & Vision

Phase 8 Week 4 represents the capstone integration for **Phase 8: MAYOTIX Labs, Isolated Disposable Virtualization & Automated Incident Response Toolkit**. It consolidates all previous capabilities into a native graphical workstation application and executes the end-of-phase 100-point security audit:

1. **MAYOTIX Labs Control Studio (`desktop/labs/mayotix-labs-gui.py`)**:
   - Native GTK3 / Wayland desktop console for security analysts and incident responders.
   - Four dedicated operational tabs:
     * **Tab 1: Disposable Lab Sandboxes**: Ephemeral container manager (templates: `malware`, `forensics`, `network`, `base`), live session monitoring, and one-click session destruction.
     * **Tab 2: Malware Detonation Studio**: Target sample selection, configurable execution timeouts (1-300s), network mode selection (`none` vs `bridge`), real-time execution progress, and syscall telemetry viewer.
     * **Tab 3: Traffic Sinkhole & Network Controller**: Bridge `mayotix-br0` controller, DNS blackhole & HTTP C2 emulator toggle, and live intercepted event log streamer.
     * **Tab 4: Behavioral Reports & Incident Triage**: Browse captured detonation reports, view threat severity scores (0-100), process fork trees, dropped file IoCs, and one-click host triage snapshots.
2. **XDG Desktop Application Integration (`desktop/applications/mayotix-labs.desktop`)**:
   - Full FreeDesktop compliance for native desktop launcher integration.
3. **Phase 8 Comprehensive Security Audit (`scripts/conduct-security-audit-phase8.sh`)**:
   - Automated 100-point security audit scoring all Phase 8 controls.

```
+-----------------------------------------------------------------------------------+
|                            MAYOTIX OS DESKTOP (WAYLAND)                           |
|                                                                                   |
|   +---------------------------------------------------------------------------+   |
|   |                  MAYOTIX Labs Control Studio (GTK3)                       |   |
|   |                                                                           |   |
|   |  [Tab 1: Sandboxes] [Tab 2: Detonation] [Tab 3: Sinkhole] [Tab 4: Triage] |   |
|   +-------------------------------------+-------------------------------------+   |
|                                         |                                         |
+-----------------------------------------|-----------------------------------------+
                                          v
+-----------------------------------------------------------------------------------+
|                      PRIVILEGED IPC DAEMON (mayotix-daemon)                       |
|                                                                                   |
|   Endpoints:                                                                      |
|     - lab.launch, lab.list, lab.destroy, lab.status                               |
|     - lab.network_start, lab.network_stop, lab.network_status                     |
|     - lab.sinkhole_start, lab.sinkhole_stop, lab.sinkhole_status, lab.sinkhole_logs|
|     - lab.detonate, lab.detonation_list, lab.detonation_report                    |
|     - incident.triage, incident.report                                            |
+-----------------------------------------------------------------------------------+
```

---

## 2. Desktop Control Studio Operational Workflows

### 2.1 Launching Ephemeral Sandboxes
1. Navigate to **Tab 1: Lab Sandboxes**.
2. Click **Launch Malware Sandbox** or **Launch Base Sandbox**.
3. Ephemeral tmpfs is allocated under a dedicated unprivileged user namespace. Real `/home/*` directories are strictly air-gapped.
4. On exit or clicking **Destroy Active Sandbox**, all sandbox artifacts are purged instantly.

### 2.2 Executing Automated Malware Detonation
1. Navigate to **Tab 2: Detonation Studio**.
2. Select target executable (e.g., `/tmp/sample.bin`).
3. Set execution timeout (default: 10s) and network mode (`bridge` connects to sinkhole).
4. Click **Detonate Sample**. Real-time execution traces, intercepted syscalls, and threat score appear in the output console.

### 2.3 Traffic Sinkhole Monitoring
1. Navigate to **Tab 3: Traffic Sinkhole**.
2. Start `mayotix-br0` and the DNS/HTTP sinkhole.
3. Observe live outbound beacons intercepted by the gateway (`10.99.0.1`) without any leakage to host physical interfaces (`DROP_PHYSICAL_EGRESS`).

### 2.4 Incident Response & Forensic Triage
1. Navigate to **Tab 4: Reports & Triage**.
2. Click **Capture Host Triage Snapshot** to generate a SHA-256 verified forensic archive (`triage_<timestamp>.tar.gz`).
3. Inspect historical reports and threat scores.

---

## 3. Comprehensive Security Audit Scoring Framework

The Phase 8 Security Audit (`scripts/conduct-security-audit-phase8.sh`) enforces a 100/100 point standard:

| Category | Description | Max Points |
|----------|-------------|------------|
| **1. Base Kernel & System Hardening** | Kernel taint status, sysctl controls, host triage collector | 10 pts |
| **2. SELinux MAC Domain & Airgap** | `mayotix_labs_t` ptrace confinement, zero `user_home_t` access | 10 pts |
| **3. Disposable Virtualized Labs** | Subnet `10.99.0.0/24`, security templates, discard-on-exit semantics | 15 pts |
| **4. Virtual Bridge & Containment Firewall** | `mayotix-br0`, fail-closed nftables physical drop, port filtering | 15 pts |
| **5. Dynamic Traffic Sinkhole & DNS Blackhole** | DNS resolution to gateway, HTTP C2 emulation, forensic logging | 15 pts |
| **6. Automated Detonation Pipeline** | Pre-flight crypto hashes (SHA-256), syscall tracing, timeout guard | 15 pts |
| **7. Behavioral Telemetry & Threat Scoring** | Process lineage, socket IoCs, heuristic threat score (0-100) | 10 pts |
| **8. Privileged IPC & Desktop Studio** | JSON-RPC 2.0 endpoints, GTK3 GUI, XDG desktop entry | 10 pts |
| **TOTAL** | **Target Pass Score** | **100 / 100 pts** |
