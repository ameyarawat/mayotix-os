# MAYOTIX OS Phase 7 Week 2: Security Lab Environment & PCAP Dissector Sandbox

## 1. Architectural Overview & Threat Model

Analyzing untrusted packet capture files (`.pcap`, `.pcapng`) represents a substantial attack surface on security analysis workstations. Packet dissection engines (such as those in `tshark`, `tcpdump`, and Wireshark) contain complex C/C++ parsers for hundreds of application and transport layer protocols. Over the years, dozens of remote code execution (RCE) and denial of service (DoS) vulnerabilities have been discovered in protocol dissectors due to memory safety bugs (buffer overflows, off-by-one errors, and use-after-free conditions).

In MAYOTIX OS, Phase 7 Week 2 decouples packet inspection and heuristic scanning from host system access through a multi-tiered isolation strategy:

```
+-------------------------------------------------------------------------------+
|                            MAYOTIX OS USERSPACE                               |
|                                                                               |
|   +---------------------+   +---------------------+   +-------------------+   |
|   |  mayotix analyze    |   |  mayotix dissect    |   |  Defender Lab GUI |   |
|   |  (Threat Scanner)   |   |  (Sandboxed Tshark) |   |  (Security Desk)  |   |
|   +----------+----------+   +----------+----------+   +---------+---------+   |
|              |                         |                        |             |
|              +-------------------------+------------------------+             |
|                                        |                                      |
+----------------------------------------|--------------------------------------+
                                         v
+-------------------------------------------------------------------------------+
|                 BUBBLEWRAP DISSECTOR SANDBOX (profile: dissector)             |
|                                                                               |
|   - Namespaces : --unshare-user, --unshare-net, --unshare-ipc, --unshare-pid  |
|   - Network    : Completely offline (NETWORK="none"), 0 socket interfaces     |
|   - Privileges : --cap-drop ALL, --new-session, noatsecure                    |
|   - Filesystem : Read-only system libraries, Ephemeral tmpfs (/tmp, /home)    |
|   - Target PCAP: Read-only mount (--ro-bind "$pcap" "$pcap")                  |
+-------------------------------------------------------------------------------+
                                         v
+-------------------------------------------------------------------------------+
|                 SELinux MAC CONFINEMENT (mayotix_dissector_t)                 |
|                                                                               |
|   - ZERO network sockets: Denies packet, rawip, tcp, and udp socket creation  |
|   - Confined Reads: Only /var/log/mayotix/captures and user pcap              |
|   - Execution Restriction: Denies shell spawning and unconfined escalation    |
+-------------------------------------------------------------------------------+
```

---

## 2. Bubblewrap Dissector Sandbox Isolation

The dissector sandbox launcher (`desktop/defender/dissect-pcap.sh`) leverages the `sandbox/bubblewrap/profiles/dissector` profile to create a fully ephemeral, offline containment pod:

```bash
exec bwrap \
    --ro-bind /usr /usr \
    --ro-bind-try /lib /lib \
    --ro-bind-try /lib64 /lib64 \
    --ro-bind-try /bin /bin \
    --ro-bind-try /sbin /sbin \
    --ro-bind-try /etc /etc \
    --ro-bind "$REAL_PCAP" "$REAL_PCAP" \
    --dev /dev \
    --tmpfs /tmp \
    --tmpfs /run \
    --tmpfs /home \
    --unshare-user \
    --unshare-net \
    --unshare-ipc \
    --unshare-pid \
    --unshare-uts \
    --unshare-cgroup \
    --cap-drop ALL \
    --die-with-parent \
    -- "${DISSECT_ARGS[@]}"
```

### Protection Characteristics
1. **Network Denial**: Even if a malicious PCAP exploits a zero-day in a protocol dissector to achieve shellcode execution, the sandbox has no network namespace or loopback interface to exfiltrate data or establish reverse shells.
2. **Persistence Prevention**: The root filesystem is mounted strictly read-only, and `/tmp`, `/run`, and `/home` are ephemeral tmpfs filesystems that are discarded upon process exit.
3. **Privilege Elimination**: All Linux capabilities are dropped (`--cap-drop ALL`).

---

## 3. Automated Threat & Heuristic Scanner (`scan-pcap.py`)

The automated threat scanner (`desktop/defender/scan-pcap.py`) is a standalone, dependency-free Python analyzer designed to audit captures for privacy violations, cleartext leakage, and network attacks.

### Security Heuristic Rules Evaluated
1. **Cleartext Protocol Leakage**: Detects unencrypted application protocols (HTTP on 80/8080, FTP on 21, Telnet on 23, SMTP on 25, POP3 on 110, IMAP on 143).
2. **Encrypted DNS Compliance**: Inspects queries to ensure all domain resolution utilizes DNS-over-TLS (DoT port 853). Flags any plaintext queries on UDP/TCP port 53.
3. **WireGuard Encapsulation Integrity**: Validates UDP 51820 traffic to ensure WireGuard tunnels are intact without unencrypted payload spillage.
4. **Reconnaissance & Scan Detection**: Detects abnormal TCP SYN scans and egress port fan-out.
5. **Dynamic Security Scoring**: Generates an actionable score from 0 to 100 with risk level classification (`LOW`, `MEDIUM`, `HIGH`, `CRITICAL`).

---

## 4. Dedicated SELinux Dissector Policy (`mayotix_dissector`)

The dissector subsystem is confined by a dedicated SELinux policy:
- **Type Definition**: `security/selinux/mayotix_dissector.te`
- **File Contexts**: `security/selinux/mayotix_dissector.fc`

### Core SELinux Types
- `mayotix_dissector_t`: Confined process domain for dissector processes.
- `mayotix_dissector_exec_t`: Executable label assigned to `/usr/local/sbin/mayotix-dissect` and `/usr/share/mayotix/defender/dissect-pcap.sh`.

### Key Enforcements
- **Zero Network Sockets**: The policy omits all socket classes (`tcp_socket`, `udp_socket`, `rawip_socket`, `packet_socket`), ensuring the kernel forbids socket allocation even if a sandboxed process requests one.
- **Confined Storage Access**: Granted read-only access to `mayotix_defender_log_t` (`/var/log/mayotix/captures`). Writing to system binaries or configuration files is blocked.

---

## 5. Unified CLI Reference (`mayotix`)

The unified CLI provides two new subcommands for defender workflows:

### 1. `mayotix analyze <pcap_file>`
Scans a packet capture for threat patterns and security compliance:
```bash
# Analyze a packet capture with formatted terminal report
mayotix analyze /var/log/mayotix/captures/wireguard-egress_20260918.pcap

# Generate machine-readable JSON telemetry
mayotix analyze /var/log/mayotix/captures/wireguard-egress_20260918.pcap --json

# Run dry-run simulation
mayotix analyze --dry-run
```

*Example Output:*
```text
================================================================
         MAYOTIX OS Defender Threat & Heuristic Report         
================================================================
  Target PCAP    : /var/log/mayotix/captures/wireguard-egress_20260918.pcap
  Total Packets  : 128
  Security Score : 100/100 (Threat Level: LOW)

  Metrics Summary:
    - Cleartext Leaks (HTTP/FTP/Telnet) : 0
    - Plaintext DNS Queries (Port 53)   : 0
    - Encrypted DNS Packets (DoT 853)   : 14
    - WireGuard Encapsulated Packets    : 114
    - SYN Scan Probes                   : 0

  Security Findings:
    1. [INFO] ENCRYPTED_DNS_COMPLIANCE
       Zero plaintext DNS queries detected; DoT policy compliant.
    2. [INFO] WIREGUARD_TUNNEL_VALIDATED
       Verified 114 encapsulated WireGuard packets on UDP/51820.
================================================================
```

### 2. `mayotix dissect <pcap_file>`
Executes deep packet dissection inside the isolated Bubblewrap sandbox:
```bash
# Display summary protocol hierarchy
mayotix dissect /var/log/mayotix/captures/wireguard-egress_20260918.pcap --summary

# Dissect with display filter
mayotix dissect /var/log/mayotix/captures/wireguard-egress_20260918.pcap --filter "udp.port == 51820"

# Dissect first 50 packets using tcpdump
mayotix dissect /var/log/mayotix/captures/wireguard-egress_20260918.pcap --tool tcpdump --count 50
```

---

## 6. Verification & Automated Test Harness

The verification suite evaluates 26 discrete checks across 7 modules:
```bash
sudo ./scripts/verify-defender-week2.sh --dry-run
```

- **Module 1**: File Presence & Directory Structure (7 checks)
- **Module 2**: Security Permissions & Shebang Integrity (5 checks)
- **Module 3**: Bubblewrap Sandbox Profile & Isolation Directives (4 checks)
- **Module 4**: SELinux Dissector Policy & Confinement (5 checks)
- **Module 5**: Automated Threat & Heuristics Scanner (5 checks)
- **Module 6**: CLI Subcommand Integration (mayotix analyze & dissect) (4 checks)
- **Module 7**: Compliance Summary & Reporting (1 check)
Target Score: **100% (All 31 checks passing)**
