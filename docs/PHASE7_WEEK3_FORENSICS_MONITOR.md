# MAYOTIX OS Phase 7 Week 3: Forensic Analysis Toolkit & Live Threat Behavioral Monitor

## 1. Architectural Overview & Vision

In Phase 7 Week 1 and Week 2, MAYOTIX Defender established capability-bounded network packet capture and isolated offline PCAP dissector sandboxing.

**Phase 7 Week 3** extends defender operations to the host process layer:
1. **Volatile Process Artifacts & Memory Forensics**:
   - Acquires `/proc/<pid>/` status, command lines, memory layout maps, and open file descriptors under bounded capabilities (`CAP_SYS_PTRACE`), eliminating the need to execute general analysis scripts as the root superuser.
   - Enforces strict write containment to `/var/log/mayotix/forensics/`.
2. **Deterministic Artifact Sanitization**:
   - Automated secret scrubber that redacts cryptographic private keys (PEM RSA/EC/OpenSSH, WireGuard keys), bearer tokens, API keys, and credentials from memory dumps prior to archiving or export.
3. **Live Threat Behavioral Monitor**:
   - Real-time watcher monitoring process trees, parentage, file descriptors, and sockets to detect reverse shells, network daemons spawning interactive shells, and binaries executing out of world-writable directories (`/tmp`, `/dev/shm`).
4. **Dedicated SELinux MAC Domain (`mayotix_forensics_t`)**:
   - Kernel-enforced MAC policy restricting memory extraction and forensic auditing to dedicated log directories while completely denying network socket access.

```
+-------------------------------------------------------------------------------+
|                            MAYOTIX OS USERSPACE                               |
|                                                                               |
|   +---------------------+   +---------------------+   +-------------------+   |
|   |  mayotix forensic   |   |  mayotix monitor    |   |  Defender Lab     |   |
|   |  (Dumper/Sanitizer) |   |  (Runtime Watcher)  |   |  Desktop Center   |   |
|   +----------+----------+   +----------+----------+   +---------+---------+   |
|              |                         |                        |             |
|              +-------------------------+------------------------+             |
|                                        |                                      |
+----------------------------------------|--------------------------------------+
                                         v
+-------------------------------------------------------------------------------+
|             VOLATILE FORENSICS & THREAT ENGINE (desktop/defender/)            |
|                                                                               |
|   - Memory Dumper   : dump-process.sh (CAP_SYS_PTRACE, /proc maps & status)   |
|   - Dump Sanitizer  : sanitize-dump.py (Scrub keys, tokens, credentials)      |
|   - Threat Monitor  : threat-monitor.py (Reverse shells, socket stdio check)  |
+-------------------------------------------------------------------------------+
                                         v
+-------------------------------------------------------------------------------+
|                 SELinux MAC CONFINEMENT (mayotix_forensics_t)                 |
|                                                                               |
|   - Bounded Capabilities: CAP_SYS_PTRACE, DAC_READ_SEARCH                     |
|   - Storage Confined    : /var/log/mayotix/forensics/*.dump ONLY              |
|   - Network Denial      : ZERO network socket classes allowed                 |
+-------------------------------------------------------------------------------+
```

---

## 2. Process Memory Dumping & Capability Bounding

The process dumper (`desktop/defender/forensics/dump-process.sh`) collects vital volatile state from the Linux `/proc` virtual filesystem:
- `/proc/<pid>/status`: UIDs, GIDs, capability sets, signal masks, and memory limits.
- `/proc/<pid>/cmdline`: Full invocation argument array.
- `/proc/<pid>/maps`: Virtual memory address ranges, permissions (rwxp), and mapped shared libraries or files.
- `/proc/<pid>/fd/`: Active open file descriptors, pipe endpoints, and socket inode numbers.
- `/proc/<pid>/environ`: Process environment variables.

Rather than running as unconfined `root`, the tool is designed to operate under `CAP_SYS_PTRACE` and `DAC_READ_SEARCH`, preventing attackers from exploiting memory scrapers to modify host state.

---

## 3. Automated Secret Sanitization Engine (`sanitize-dump.py`)

Memory dumps often inadvertently capture highly sensitive cryptographic material and credentials. The sanitizer engine scans raw artifacts and replaces sensitive secrets with deterministic redaction placeholders:

| Secret Category | Detection Pattern | Redaction Mask |
|---|---|---|
| **PEM Private Keys** | `-----BEGIN [RSA|EC|DSA|OPENSSH] PRIVATE KEY-----` | `[REDACTED_PRIVATE_KEY]` |
| **WireGuard Keys** | `PrivateKey = [A-Za-z0-9+/]{43}=` | `PrivateKey = [REDACTED_WIREGUARD_KEY]` |
| **Bearer Tokens** | `Bearer [a-zA-Z0-9_\-\.]{16,}` | `Bearer [REDACTED_BEARER_TOKEN]` |
| **JWT Tokens** | `eyJ[a-zA-Z0-9_-]+\.eyJ[a-zA-Z0-9_-]+\....` | `[REDACTED_JWT_TOKEN]` |
| **Cloud & Git Tokens** | `ghp_[a-zA-Z0-9]{36}`, `AKIA[0-9A-Z]{16}` | `[REDACTED_GITHUB_TOKEN]`, `[REDACTED_AWS_KEY]` |
| **Passwords / API Keys** | `(password\|api_key\|auth_token)[=:]['"]?...` | `\1=[REDACTED_CREDENTIAL]` |

---

## 4. Live Threat Behavioral Monitor (`threat-monitor.py`)

The runtime threat monitor continually inspects process behavior against defined heuristic attack patterns:

1. **Reverse Shell Detection (`CRITICAL`)**:
   - Inspects file descriptors `/proc/<pid>/fd/0`, `/proc/<pid>/fd/1`, and `/proc/<pid>/fd/2`.
   - If an interactive shell interpreter (`sh`, `bash`, `dash`, `zsh`) has stdin or stdout mapped to a socket endpoint (`socket:[...]`), it triggers an immediate critical alert.
2. **Network Daemon Shell Spawning (`HIGH`)**:
   - Flags when background network services (e.g., `nginx`, `httpd`, `node`, `python3`, `nc`, `socat`) spawn interactive child shells.
3. **World-Writable Directory Execution (`HIGH`)**:
   - Flags any active process whose binary path (`/proc/<pid>/exe`) originates in `/tmp`, `/var/tmp`, or `/dev/shm`.

---

## 5. Dedicated SELinux Forensics Policy (`mayotix_forensics`)

Defined in `security/selinux/mayotix_forensics.te` and `mayotix_forensics.fc`:
- **Process Domain**: `mayotix_forensics_t`
- **Execution Label**: `mayotix_forensics_exec_t`
- **Storage Label**: `mayotix_forensics_log_t` (`/var/log/mayotix/forensics(/.*)?`)

### Security Constraints:
1. **Network Prohibition**: The policy defines **zero network socket classes**. The kernel forbids forensic processes from establishing connections or binding ports.
2. **Filesystem Containment**: Writes are confined exclusively to `mayotix_forensics_log_t`. Modification of system configurations or binaries is blocked.

---

## 6. Unified CLI Reference (`mayotix`)

### 1. `mayotix forensic dump`
```bash
# Acquire process dump for PID 1420
mayotix forensic dump --pid 1420

# Acquire process dump with automated secret scrubbing
mayotix forensic dump --pid 1420 --sanitize

# Dry-run simulation
mayotix forensic dump --pid 1 --dry-run
```

### 2. `mayotix forensic sanitize`
```bash
# Sanitize an existing memory dump file
mayotix forensic sanitize /var/log/mayotix/forensics/proc_1420.dump --output /tmp/clean.dump

# Simulate sanitization on mock secrets
mayotix forensic sanitize --dry-run
```

### 3. `mayotix monitor`
```bash
# Run one-shot threat audit across all processes
mayotix monitor

# Filter to output only when active threats are detected
mayotix monitor --threats-only

# Continuous monitoring with 5-second polling interval
mayotix monitor --interval 5

# JSON telemetry output
mayotix monitor --json --dry-run
```

---

## 7. Automated Verification Suite

Run the Phase 7 Week 3 verification test suite:
```bash
sudo ./scripts/verify-defender-week3.sh --dry-run
```

- **Module 1**: File Presence & Directory Structure (7 checks)
- **Module 2**: Security Permissions & Shebang Integrity (7 checks)
- **Module 3**: Process Memory Dumper & Capability Confinement (4 checks)
- **Module 4**: Artifact Sanitizer & Secret Redaction Engine (5 checks)
- **Module 5**: Live Threat Behavioral Monitor Heuristics (5 checks)
- **Module 6**: SELinux Forensics Policy & Confinement (5 checks)
- **Module 7**: CLI Subcommand Integration (4 checks)
- **Module 8**: Audit Summary & Reporting (1 check)
Target Score: **100% (All 38 checks passing)**
