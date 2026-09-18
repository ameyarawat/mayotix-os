# MAYOTIX OS Phase 8 Week 3: Automated Malware Detonation Pipeline & Runtime Behavioral Telemetry Tracer

## 1. Architectural Overview & Design Vision

Phase 8 Week 3 establishes the automated **Malware Detonation Pipeline** and **Runtime Behavioral Telemetry Tracer** for MAYOTIX OS. Building upon the isolated virtualization (Week 1) and virtual bridge / dynamic sinkhole containment (Week 2), Week 3 enables automated, safe detonation of untrusted binaries, scripts, and documents within ephemeral sandboxes.

The pipeline traces kernel system calls, captures outbound network sockets into the sinkhole, monitors filesystem modifications, and extracts Indicators of Compromise (IoCs) to compute real-time Threat Severity Scores.

```
+-----------------------------------------------------------------------------------+
|                              MAYOTIX OS USERSPACE                                 |
|                                                                                   |
|     +-----------------------------------------------------------------------+     |
|     |                             mayotix lab                               |     |
|     |       (detonate <sample> [--timeout] [--network] / reports / status)  |     |
|     +-----------------------------------+-----------------------------------+     |
|                                         |                                         |
+-----------------------------------------|-----------------------------------------+
                                          v
+-----------------------------------------------------------------------------------+
|                      PRIVILEGED IPC DAEMON (mayotix-daemon)                       |
|                                                                                   |
|   Endpoints:                                                                      |
|     - lab.detonate: Launches ephemeral detonation pipeline                        |
|     - lab.detonation_list: Lists captured forensic telemetry reports             |
|     - lab.detonation_report: Retrieves structured JSON report for a session       |
+-----------------------------------------+-----------------------------------------+
                                          |
                                          v
+-----------------------------------------------------------------------------------+
|               AUTOMATED DETONATION PIPELINE (detonation-pipeline.sh)              |
|                                                                                   |
|   1. Pre-Detonation Cryptographic Hashing (MD5, SHA-1, SHA-256)                   |
|   2. Virtual Bridge & Dynamic Sinkhole Containment Verification (10.99.0.1)       |
|   3. Ephemeral Sandbox Mount (Bubblewrap tmpfs /home, read-only root system)      |
|   4. Execution under strace (execve, openat, connect, socket, unlinkat, write)    |
|   5. Timeout Enforcement (10s default, SIGKILL on expiry)                         |
|   6. Discard-on-Exit Cleanup (Immediate volatile scratch purge)                   |
+-----------------------------------------+-----------------------------------------+
                                          |
                                          v
+-----------------------------------------------------------------------------------+
|             BEHAVIORAL TELEMETRY ANALYZER (behavior-analyzer.py)                  |
|                                                                                   |
|   - Network IoCs: Intercepted DNS queries, HTTP C2 requests, and sockets          |
|   - Filesystem Mutations: Dropped files, hidden dotfiles in /tmp or /dev/shm      |
|   - Process Lineage: Subprocesses spawned, shell executions, download utilities   |
|   - Threat Severity Scoring: Heuristic risk assessment (0-100) & classification   |
|   - JSON Report Output: /var/log/mayotix/labs/reports/detonation_<id>.json        |
+-----------------------------------------------------------------------------------+
```

---

## 2. Core Components

### 2.1 Automated Detonation Pipeline (`desktop/labs/detonation-pipeline.sh`)
- **Pre-detonation Hashing**: Automatically hashes target files before execution using MD5, SHA-1, and SHA-256.
- **Fail-Closed Sandbox**: Mounts the sample into a temporary disposable container with tmpfs `/tmp` and private home. Real user home directories (`/home/*`) are strictly excluded.
- **Runtime Tracing**: Executes the target binary wrapped in `strace` filtering for security-critical system calls (`execve`, `openat`, `connect`, `socket`, `unlinkat`, `write`, `renameat`).
- **Timeout Management**: Prevents malicious hangs via `timeout --preserve-status --kill-after=2`.
- **Zero Host Persistence**: All volatile execution files are wiped on exit via shell signal traps (`EXIT`, `INT`, `TERM`).

### 2.2 Behavioral Telemetry Analyzer & IoC Extractor (`desktop/labs/behavior-analyzer.py`)
- **Process Lineage**: Traces parent-child execution chains and identifies invoked shells (`/bin/sh`, `/bin/bash`) or download utilities (`curl`, `wget`, `nc`).
- **Network Interceptions**: Correlates outbound connections with the traffic sinkhole daemon logs (`/var/log/mayotix/labs/sinkhole.log`).
- **Filesystem Mutations**: Identifies dropped executables, hidden dotfiles, and persistence attempts.
- **Automated Threat Severity Scoring**:
  * **Shell Execution**: +25 points
  * **Suspicious Downloader Tools**: +30 points
  * **Outbound C2 Network Attempts**: +35 points
  * **Multiple Egress Targets**: +10 points
  * **Hidden Artifact Dropped**: +25 points
  * **Scratch Mutation**: +15 points
  * **Score Classifications**:
    - `0 - 20`: **BENIGN**
    - `21 - 50`: **LOW**
    - `51 - 75`: **MEDIUM**
    - `76 - 89`: **HIGH**
    - `90 - 100`: **CRITICAL**

### 2.3 SELinux MAC Domain Confinement (`security/selinux/mayotix_labs.te`)
- Extended with `sys_ptrace` capability and `allow mayotix_labs_t self:process ptrace` for sandbox execution tracing.
- Strictly confines report storage under `mayotix_labs_log_t` (`/var/log/mayotix/labs/reports/`).
- Zero permissions granted to `user_home_t` or `user_home_dir_t`.

---

## 3. Privileged IPC & Unified CLI

### 3.1 JSON-RPC Methods
| Method | Description | Parameters |
|--------|-------------|------------|
| `lab.detonate` | Detonates sample in ephemeral sandbox | `sample`, `timeout`, `network`, `dry_run` |
| `lab.detonation_list` | Lists captured detonation reports | `dry_run` |
| `lab.detonation_report` | Retrieves specific report | `report_id`, `dry_run` |

### 3.2 CLI Commands
```bash
# Detonate a suspicious binary in isolated sandbox with 15s timeout
mayotix lab detonate /path/to/suspicious_sample.bin --timeout 15 --network bridge

# Simulate detonation in dry-run mode with structured JSON telemetry
mayotix lab detonate /tmp/mock-sample.bin --dry-run --json

# List all completed detonation forensic reports
mayotix lab reports --json
```
