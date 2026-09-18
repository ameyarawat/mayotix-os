# MAYOTIX OS Phase 7 Week 1: Network Analysis & Packet Inspection Toolkit

## 1. Architectural Overview & Vision

Phase 7 introduces the **MAYOTIX Defender & Security Lab Environment**, empowering security engineers and privacy-conscious users to analyze, inspect, and audit network traffic natively without compromising system integrity.

Historically, network packet capture tools like `tcpdump` and `tshark` require running as the root superuser (`root`), introducing significant privilege escalation risks should a packet parser exploit or malformed protocol memory vulnerability occur.

In MAYOTIX OS, packet inspection is completely decoupled from full root privileges through a three-layer isolation model:
1. **Linux File Capabilities**: Confined execution using only `CAP_NET_RAW` and `CAP_NET_ADMIN`, preventing arbitrary root privilege execution.
2. **Dedicated SELinux MAC Domain (`mayotix_defender_t`)**: Confines packet inspection processes to restricted networking sockets, explicitly denying raw disk writes outside of `/var/log/mayotix/captures`.
3. **Unified CLI Integration (`mayotix capture`)**: Streamlined lifecycle controls integrated directly into the `mayotix` command-line suite with automated profile resolution and JSON telemetry.

```
+-------------------------------------------------------------------------------+
|                            MAYOTIX OS USERSPACE                               |
|                                                                               |
|   +---------------------+   +---------------------+   +-------------------+   |
|   |  Terminal / Shell   |   |  Security Center    |   |  Defender GUI     |   |
|   |  'mayotix capture'  |   |  Audit Hooks        |   |  (Desktop Lab)    |   |
|   +----------+----------+   +----------+----------+   +---------+---------+   |
|              |                         |                        |             |
|              +-------------------------+------------------------+             |
|                                        |                                      |
|                                        v                                      |
|             +----------------------------------------------------+            |
|             |        desktop/defender/mayotix-capture.sh         |            |
|             |   - Profile selection & BPF filter compiler        |            |
|             |   - Unprivileged capture orchestration             |            |
|             |   - Process state tracking (/run/mayotix)          |            |
|             +--------------------------+-------------------------+            |
|                                        |                                      |
+----------------------------------------|--------------------------------------+
                                         v
+-------------------------------------------------------------------------------+
|                 SELinux MAC CONFINEMENT (mayotix_defender_t)                  |
|                                                                               |
|   - Capabilities: CAP_NET_RAW, CAP_NET_ADMIN (Dropped root)                   |
|   - Network: Packet socket, Raw IP socket, Netlink route                      |
|   - Filesystem Containment:                                                   |
|       * Read: /etc (resolv.conf, protocols), /usr/lib, /usr/bin               |
|       * Write: /var/log/mayotix/captures/*.pcap ONLY                          |
|       * Denied: /home, /root, /boot, raw disks, block devices                 |
+-------------------------------------------------------------------------------+
```

---

## 2. Capability-Bounded Packet Inspection

Packet capture binaries (`tcpdump`, `tshark`) can be executed by non-root users or bounded service processes by assigning specific POSIX file capabilities instead of setuid root:

```bash
# Assign capabilities to packet capture binaries
sudo setcap cap_net_raw,cap_net_admin+ep /usr/sbin/tcpdump
sudo setcap cap_net_raw,cap_net_admin+ep /usr/bin/dumpcap
```

This ensures that:
- The capture process cannot mount filesystems, alter system clocks, load kernel modules, or bypass arbitrary file read/write permissions.
- In the event of a vulnerability in packet parsing (e.g. Wireshark dissector vulnerability), an attacker only gains a restricted process without root authority.

---

## 3. Dedicated Packet Filtering Profiles

The toolkit provides curated security profiles designed specifically to audit MAYOTIX OS hardening subsystems:

| Profile | Target Interface | BPF Filter Expression | Primary Use Case |
|---|---|---|---|
| `wireguard-egress` | `wg0` or Physical | `udp port 51820 or ip proto 50` | Audits encapsulated WireGuard VPN traffic and ESP protocols to confirm cryptographic tunneling. |
| `dot-dns` | `lo` or Physical | `tcp port 853 or udp port 853` | Verifies encrypted DNS-over-TLS query exchanges to ensure no plaintext port 53 leakage. |
| `leak-sniffer` | Physical (e.g. `eth0`, `wlan0`) | `not (tcp port 853 or udp port 51820 or udp port 67 or udp port 68) and not ip broadcast and not ip multicast` | Sniffs for any unencrypted cleartext egress leaking past VPN and firewall kill-switches. |
| `custom` | Any specified | User-defined BPF expression | Tailored packet filtering for custom network analysis scenarios. |

---

## 4. SELinux Security Policy Module (`mayotix_defender`)

The defender subsystem is governed by a dedicated SELinux policy module:
- **Type Definition**: `security/selinux/mayotix_defender.te`
- **File Contexts**: `security/selinux/mayotix_defender.fc`

### Core SELinux Types
- `mayotix_defender_t`: The confined process domain for capture scripts and sniffers.
- `mayotix_defender_exec_t`: Executable label assigned to `/usr/local/sbin/mayotix-capture` and `/usr/share/mayotix/defender/*`.
- `mayotix_defender_log_t`: Directory and file label for `/var/log/mayotix/captures(/.*)?`.

### Security Constraints Enforced by Policy
1. **Restricted Storage**: `mayotix_defender_t` is granted write permissions **only** to directories and files labeled `mayotix_defender_log_t` (`/var/log/mayotix/captures`). All write attempts to user homes, system binaries, or configuration files are strictly denied by the kernel.
2. **Bounded Capabilities**: Only `CAP_NET_RAW` and `CAP_NET_ADMIN` are permitted.
3. **Transition Rules**: Automatic domain transition from `unconfined_t` or `xdm_t` (graphical sessions) upon executing `mayotix-capture`.

---

## 5. Unified CLI Reference (`mayotix capture`)

The `mayotix` command-line utility provides native capture controls:

### 1. List Available Profiles
```bash
mayotix capture list-profiles
```
*Output:*
```text
Available MAYOTIX Defender Capture Profiles:
  wireguard-egress : Captures encapsulated VPN traffic on wg* or UDP/51820
  dot-dns          : Captures system-wide DNS-over-TLS packets on port 853
  leak-sniffer     : Detects cleartext unencrypted egress leaks on physical interfaces
  custom           : Arbitrary BPF packet capture filter expression
```

### 2. Start a Capture Session
```bash
# Start default WireGuard egress capture
mayotix capture start

# Start DNS-over-TLS inspection on loopback
mayotix capture start --profile dot-dns --interface lo

# Start cleartext leakage sniffer with custom output file
mayotix capture start --profile leak-sniffer --output /var/log/mayotix/captures/leak_audit.pcap

# Start custom BPF capture
mayotix capture start --profile custom --filter "tcp port 443"
```

### 3. Check Capture Status
```bash
mayotix capture status
```
*Human-Readable Output:*
```text
================================================================
              MAYOTIX Defender Capture Status                   
================================================================
  Status    : ACTIVE (PID: 14205)
  Interface : wg0
  Profile   : wireguard-egress
  Filter    : udp port 51820 or ip proto 50
  Output    : /var/log/mayotix/captures/wireguard-egress_20260918_115500.pcap
  Duration  : 42s
================================================================
```

*JSON Telemetry Output (`--json`):*
```json
{
  "active": true,
  "pid": 14205,
  "interface": "wg0",
  "profile": "wireguard-egress",
  "filter": "udp port 51820 or ip proto 50",
  "output_file": "/var/log/mayotix/captures/wireguard-egress_20260918_115500.pcap",
  "duration_seconds": 42
}
```

### 4. Stop an Active Capture Session
```bash
mayotix capture stop
```
*Output:*
```text
[✓] Capture process (PID 14205) stopped.
[✓] Capture saved to /var/log/mayotix/captures/wireguard-egress_20260918_115500.pcap (Size: 24K)
```

---

## 6. Verification & Test Harness

Run the automated verification suite to validate file presence, SELinux policy syntax, profile definitions, and CLI execution:

```bash
sudo ./scripts/verify-defender.sh --dry-run
```

The verification suite evaluates 26 discrete checks across 7 modules:
- **Module 1**: File Presence & Directory Structure (5 checks)
- **Module 2**: Security Permissions & Shebang Integrity (5 checks)
- **Module 3**: SELinux Policy Confinement & Type Enforcement (6 checks)
- **Module 4**: Defender Capture Profiles & BPF Logic (6 checks)
- **Module 5**: CLI Subcommand Integration (4 checks)
- **Module 6**: Capture Execution & Argument Parsing (Dry-Run) (5 checks)
- **Module 7**: Capability & Security Isolation Analysis (3 checks)
Target Score: **100% (All 34 checks passing)**
