# MAYOTIX OS Phase 6 Week 1: Unified CLI & Privileged IPC Daemon

## 1. Architectural Overview & Vision

Phase 6 unifies system administration, security posture evaluation, network privacy monitoring, and firewall control into a single cohesive interface: the **`mayotix`** command-line suite backed by an isolated, privileged IPC daemon (**`mayotix-daemon`**).

Rather than forcing users or administrative tools to execute fragmented, standalone shell scripts with disparate output conventions, the unified CLI provides:
- A standardized, intuitive subcommand structure (`status`, `security`, `network`, `firewall`).
- Full `--json` support across every command for headless scripting, telemetry, and GUI integration.
- Strict privilege separation via a dedicated Unix domain socket (`/run/mayotix/mayotix.sock`).
- Immune to shell command injection (utilizing structured parameter arrays and `shell=False` everywhere).
- Seamless client-side local fallback if the background daemon is not active.

```
+-------------------------------------------------------------------------------+
|                            MAYOTIX OS USERSPACE                               |
|                                                                               |
|   +---------------------+   +---------------------+   +-------------------+   |
|   |  User Terminal /    |   |  Security Center    |   |  Automated        |   |
|   |  Shell ('mayotix')  |   |  Desktop GUI (GTK3) |   |  Audit Scripts    |   |
|   +----------+----------+   +----------+----------+   +---------+---------+   |
|              |                         |                        |             |
|              +-------------------------+------------------------+             |
|                                        |                                      |
|                                        | Unix Domain Socket (UDS)             |
|                                        | /run/mayotix/mayotix.sock (mode 0660)|
|                                        v                                      |
|   +-----------------------------------------------------------------------+   |
|   |            Privileged IPC Daemon (mayotix-daemon.py)                  |   |
|   |  - Systemd sandboxed: ProtectSystem=strict, PrivateTmp=yes            |   |
|   |  - Strict capabilities: CAP_NET_ADMIN, CAP_NET_RAW                    |   |
|   |  - JSON-RPC 2.0 Dispatcher (No shell execution, safe argument arrays) |   |
|   +------------------------------------+----------------------------------+   |
|                                        |                                      |
+----------------------------------------|--------------------------------------+
                                         v
               +---------------------------------------------------+
               |              Hardened System Subsystems           |
               |  - SELinux (getenforce, semodule, ausearch)       |
               |  - DNS-over-TLS (systemd-resolved)                |
               |  - WireGuard Kernel Module & Cryptokey Routing    |
               |  - nftables Fail-Closed Network Kill-Switch       |
               |  - Tor SOCKS5 & TransPort Isolation Proxy         |
               +---------------------------------------------------+
```

---

## 2. JSON-RPC 2.0 Protocol Specification

Communication between `mayotix` and `mayotix-daemon` adheres strictly to standard JSON-RPC 2.0 over Unix Domain Sockets:

### Request Format
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "status.get",
  "params": {}
}
```

### Response Format
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "os": "MAYOTIX OS",
    "version": "5.0-alpha",
    "security_score": 100,
    "subsystems": {
      "selinux": "Enforcing",
      "dot_dns": "Active (DoT 853)",
      "wireguard": "Connected",
      "killswitch": "Enabled (Fail-Closed)",
      "tor": "Active"
    }
  }
}
```

### Supported IPC Methods
| Method | Parameters | Description |
|---|---|---|
| `status.get` | None | Retrieves high-level OS version, uptime, and status across all 5 core subsystems. |
| `security.get` | None | Retrieves SELinux enforcement mode, active `.pp` modules, recent AVC denials, and ASLR/SMEP mitigations. |
| `network.get` | None | Retrieves DNS-over-TLS status, WireGuard interface handshake/routes, and Tor proxy ports. |
| `firewall.get` | None | Retrieves nftables table status, default hook policies, and cleartext packet drop counters. |
| `firewall.set_killswitch` | `{"state": "enable" \| "disable"}` | Atomically activates or relaxes the fail-closed network kill-switch. |
| `ping` | None | Health-check endpoint returning `"pong"`. |

---

## 3. CLI Commands & Usage Guide

The `mayotix` command is installed to `/usr/bin/mayotix` and can be invoked with standard subcommands:

### 1. `mayotix status`
Displays overall system health, security score, and subsystem operational states:
```bash
mayotix status
mayotix status --json
```

### 2. `mayotix security`
Inspects SELinux policy confinement, loaded custom policy modules, recent access vector cache (AVC) denials, and kernel hardware mitigations (ASLR level 2, SMEP, SMAP, NX):
```bash
mayotix security
mayotix security --json
```

### 3. `mayotix network`
Provides visibility into the Phase 5 network privacy stack:
- **Encrypted DNS**: Verifies port 853 TLS transport, DNSSEC validation, and stub pointer.
- **WireGuard**: Inspects tunnel encapsulation status, allowed IP routes, and watchdog state.
- **Tor Anonymity**: Shows SOCKS5 (9050) and TransPort (9040) binding.
```bash
mayotix network
mayotix network --json
```

### 4. `mayotix firewall`
Monitors and controls the atomic fail-closed `nftables` network kill-switch:
```bash
# View active tables and blocked packet counts
mayotix firewall
mayotix firewall --json

# Atomically enable fail-closed kill-switch
sudo mayotix firewall --enable

# Temporarily disable kill-switch for local maintenance
sudo mayotix firewall --disable
```

### 5. `mayotix version`
Displays semantic versioning and IPC protocol compatibility:
```bash
mayotix version
mayotix version --json
```

---

## 4. Security Hardening & Sandboxing

The daemon service definition (`services/mayotix-daemon.service`) enforces strict systemd process isolation:

- **Socket Permissions**: Bound to `/run/mayotix/mayotix.sock` with mode `0660`, owned by `root:mayotix`.
- **Filesystem Isolation**: `ProtectSystem=strict` ensures host filesystem cannot be modified by daemon processes; `/home` is mounted read-only (`ProtectHome=read-only`).
- **Namespace Isolation**: `PrivateTmp=yes` isolates `/tmp` into a private namespace.
- **Kernel Hardening**: `ProtectKernelTunables=yes`, `ProtectControlGroups=yes`, and `ProtectKernelModules=yes` prevent kernel tampering.
- **Bounded Capabilities**: Only `CAP_NET_ADMIN`, `CAP_NET_RAW`, and `CAP_DAC_OVERRIDE` are granted to inspect network and firewall states. All other ambient capabilities are dropped.

---

## 5. Verification & Test Suite

Run the automated 20-point verification harness:

```bash
# Dry run verification pass
sudo ./scripts/verify-cli.sh --dry-run

# Standard verification pass
sudo ./scripts/verify-cli.sh
```

Audit reports are automatically saved to `build/PHASE6_WEEK1_CLI_VERIFICATION_REPORT.txt`.
