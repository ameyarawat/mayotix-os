# MAYOTIX OS Phase 8 Week 1: Isolated Disposable Labs & Automated Incident Response

## 1. Architectural Overview & Vision

Phase 8 introduces **MAYOTIX Labs & Incident Response Framework**, providing automated security investigation, malware triage, and sandboxed dynamic analysis.

Building on the network privacy, packet inspection, memory forensics, and runtime behavioral monitoring established in earlier phases, Phase 8 Week 1 delivers:
1. **Isolated Disposable Lab Environments (`desktop/labs/mayotix-lab.sh`)**:
   - Ephemeral analysis sandboxes designed for dynamic testing of untrusted code and malware.
   - Strictly air-gapped from host user files: private `/tmp`, ephemeral tmpfs `/home`, and read-only host system mounts.
   - Internal virtual bridge networking (`10.99.0.0/24`) isolating lab traffic from host physical adapters.
   - Automatic discard-on-exit semantics: all volatile session state, temporary files, and spawned processes are immediately purged upon session termination.
2. **Automated Incident Response Triage Engine (`desktop/defender/incident/triage-snapshot.sh`)**:
   - Gathers host-wide forensic state during active security events or breaches:
     * Active connections, listening sockets, routing tables, and interface states.
     * Process hierarchy tree and parent-child execution lineages.
     * Kernel version, taint flags (`/proc/sys/kernel/tainted`), and loaded module manifests.
     * Recent SELinux AVC denials and audit log security events.
     * Failed systemd units and abnormal background services.
   - Packages artifacts into a cryptographically verified, SHA-256 hashed tarball under `/var/log/mayotix/incident/`.
3. **Dedicated SELinux MAC Domain (`mayotix_labs_t`)**:
   - Kernel-enforced policy explicitly omitting `user_home_t` and `user_home_dir_t`, guaranteeing zero breakout into host user home directories.
   - Confines virtual bridge and socket operations to dedicated internal interfaces.
4. **Privileged IPC Daemon & Unified CLI Integration**:
   - Full integration with `daemon/mayotix-daemon.py` via `lab.*` and `incident.*` JSON-RPC 2.0 endpoints.
   - Seamless management through `mayotix lab` and `mayotix incident` CLI subcommands.

```
+-------------------------------------------------------------------------------+
|                            MAYOTIX OS USERSPACE                               |
|                                                                               |
|   +--------------------------+             +------------------------------+   |
|   |       mayotix lab        |             |       mayotix incident       |   |
|   |  (launch / list / destroy)             |  (triage snapshot / report)  |   |
|   +------------+-------------+             +--------------+---------------+   |
|                |                                          |                   |
+----------------|------------------------------------------|-------------------+
                 v                                          v
+-------------------------------------------------------------------------------+
|                     PRIVILEGED IPC DAEMON (mayotix-daemon)                    |
|                                                                               |
|   Endpoints:                                                                  |
|     - lab.launch, lab.list, lab.destroy, lab.status                           |
|     - incident.triage, incident.report                                        |
|   Validation: Strict whitelisting for templates (base, malware, forensics)    |
|               and network isolation modes (none, bridge)                      |
+-------------------------------------------------------------------------------+
                 |                                          |
                 v                                          v
+------------------------------------+     +------------------------------------+
|        ISOLATED LAB SANDBOX        |     |      INCIDENT TRIAGE ENGINE        |
|      (desktop/labs/mayotix-lab.sh) |     | (defender/incident/triage-snapshot)|
|                                    |     |                                    |
| - Bridge Network: 10.99.0.0/24     |     | - Sockets: ss -tulpn, ip route     |
| - Read-Only Host System            |     | - Processes: ps auxf               |
| - Air-Gapped from /home/*          |     | - Kernel: /proc taint, lsmod       |
| - Ephemeral Discard-on-Exit        |     | - SELinux: AVC audit log events    |
+------------------------------------+     | - SHA-256 Hashed Archive Output    |
                 |                         +------------------------------------+
                 v                                          |
+-----------------------------------------------------------v-------------------+
|                     SELinux MAC CONFINEMENT (mayotix_labs_t)                  |
|                                                                               |
|   - Real User Home Directories (user_home_t)  : EXPLICITLY DENIED (Air-Gap)   |
|   - Logging & Triage Archives                 : /var/log/mayotix/labs/ &      |
|                                                 /var/log/mayotix/incident/    |
+-------------------------------------------------------------------------------+
```

---

## 2. Lab Isolation & Ephemeral Networking

The lab environment harness provides two isolated networking modes:
- **`none` (Strict Air-Gap)**: The sandbox executes inside an unshared network namespace with no network devices except local loopback (`lo`). Untrusted samples have zero ability to contact the host, LAN, or external internet.
- **`bridge` (Internal Virtual Network)**: Connects the lab container to an internal virtual bridge (`mayotix-br0`, subnet `10.99.0.0/24`, gateway `10.99.0.1`). Network traffic is isolated from host physical adapters (`enp*`, `wlan*`) and cannot bypass the host firewall.

### File System Air-Gap
- `/usr`, `/bin`, `/sbin`, `/lib`, `/lib64`, `/etc`: Bound read-only (`--ro-bind`).
- `/root`, `/tmp`: Bound to an ephemeral tmpfs scratch space.
- Host `/home`: Completely unmapped and inaccessible.

---

## 3. Automated Incident Triage Telemetry

When an alert triggers, `triage-snapshot.sh` collects comprehensive host state:
1. `network_sockets.txt`: Active listening ports, established TCP connections, routing tables, and interface link states.
2. `process_tree.txt`: Full process tree showing parent PIDs, user IDs, and command lines.
3. `kernel_state.txt`: Kernel version, taint bitmask, and active module list.
4. `selinux_avc_denials.txt`: Recent AVC denials and access violations.
5. `systemd_failed_units.txt`: Service degradation and crashed daemon states.
6. `manifest.json`: Timestamp, collector version, and cryptographic hash verification.

---

## 4. Verification & Usage Guide

```bash
# Test lab launch in dry-run mode
mayotix lab launch --template malware --network none --dry-run

# Check lab subsystem status
mayotix lab status --dry-run --json

# Trigger automated incident response triage snapshot
mayotix incident triage --dry-run

# Run full Phase 8 Week 1 verification suite
sudo ./scripts/verify-labs-week1.sh --dry-run
```
