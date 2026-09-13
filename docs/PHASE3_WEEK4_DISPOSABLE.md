# MAYOTIX OS Phase 3 — Week 4: Ephemeral / Disposable Workspace Sessions

## 1. Overview

Week 4 delivers **disposable workspace sessions** — one-time, throw-away environments that leave **zero persistent data** after logout. Every file the user creates, every browser cache entry, every shell history line exists only in RAM-backed tmpfs and is securely wiped when the session ends.

This capability addresses three threat categories:

| Threat | Mitigation |
|---|---|
| **Forensics / data remanence** | All user data lives on tmpfs (RAM); `shred` overwrites file contents before `rm -rf` on exit |
| **Persistent compromise** | Malware cannot survive logout — there is no writable persistent storage |
| **Lateral movement via home** | SELinux denies all access to the real `/home/*` tree; bwrap mounts an empty tmpfs over `/home` |

## 2. Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Display Manager (GDM/SDDM)              │
│  ┌─────────────────────┐  ┌──────────────────────────────┐  │
│  │ Mayotix Session     │  │ Mayotix Disposable Session ◄─┼──│─ User selects at login
│  │ (persistent)        │  │ (ephemeral)                  │  │
│  └─────────────────────┘  └──────────────┬───────────────┘  │
└──────────────────────────────────────────┼──────────────────┘
                                           │
                          Exec: /usr/bin/mayotix-disposable-session
                                           │
                    ┌──────────────────────▼──────────────────────┐
                    │              Bubblewrap (bwrap)              │
                    │                                              │
                    │  Namespaces:  user, IPC, PID, net (opt)      │
                    │  Caps dropped: SYS_ADMIN, SYS_PTRACE, …     │
                    │                                              │
                    │  ┌──────────────────────────────────────┐    │
                    │  │  Filesystem view                     │    │
                    │  │                                      │    │
                    │  │  /usr, /etc, /bin, /lib  → ro-bind   │    │
                    │  │  /var, /run, /sys        → ro-bind   │    │
                    │  │  /dev                    → devtmpfs  │    │
                    │  │  /proc                   → procfs    │    │
                    │  │                                      │    │
                    │  │  /home                   → tmpfs ◄── EPHEMERAL
                    │  │  /home/$USER             → bind(tmpdir)   │
                    │  │  /tmp                    → tmpfs ◄── EPHEMERAL
                    │  └──────────────────────────────────────┘    │
                    │                                              │
                    │  ┌────────────────────┐                      │
                    │  │  sway (compositor)  │                      │
                    │  └────────────────────┘                      │
                    └──────────────────────────────────────────────┘
                                     │
                              On logout / exit
                                     │
                    ┌────────────────▼─────────────────┐
                    │  Cleanup (trap EXIT INT TERM HUP) │
                    │  1. shred all files in tmpfs dirs  │
                    │  2. rm -rf ephemeral directories   │
                    │  3. Log completion                 │
                    └──────────────────────────────────┘
```

## 3. Components

### 3.1 Session Launcher: `mayotix-disposable-session`

**Path**: `/usr/bin/mayotix-disposable-session`  
**Source**: `desktop/sessions/mayotix-disposable-session.sh`

The launcher is a Bash script (`set -euo pipefail`) that:

1. **Creates ephemeral directories** — three `mktemp -d` calls create isolated tmpfs-backed trees for `/home`, `/tmp`, and XDG runtime.
2. **Builds a home skeleton** — `.config`, `.local/share`, `.cache`, `Desktop`, `Documents`, `Downloads`.
3. **Registers cleanup** — a `trap` on `EXIT INT TERM HUP` runs `shred -fuz` on every file, then `rm -rf` on the directories.
4. **Assembles bwrap arguments** — namespace isolation, capability dropping, filesystem binds, environment variables.
5. **Launches sway** — `exec bwrap … -- sway`.

#### Usage

```bash
# Default: network disabled
mayotix-disposable-session

# With network access
mayotix-disposable-session --network

# Help
mayotix-disposable-session --help
```

#### Environment Variables Set Inside the Sandbox

| Variable | Value | Purpose |
|---|---|---|
| `HOME` | `/home/$USER` | Points to ephemeral home |
| `XDG_CONFIG_HOME` | `/home/$USER/.config` | Freedesktop config |
| `XDG_DATA_HOME` | `/home/$USER/.local/share` | Freedesktop data |
| `XDG_CACHE_HOME` | `/home/$USER/.cache` | Freedesktop cache |
| `XDG_SESSION_TYPE` | `wayland` | Session type |
| `XDG_CURRENT_DESKTOP` | `Mayotix` | Desktop identity |
| `MAYOTIX_DISPOSABLE` | `1` | Flag for scripts to detect disposable mode |
| `MAYOTIX_SESSION_ID` | `disposable-<epoch>-<pid>` | Unique session identifier |

### 3.2 Display Manager Entry: `mayotix-disposable.desktop`

**Install path**: `/usr/share/wayland-sessions/mayotix-disposable.desktop`  
**Source**: `desktop/sessions/mayotix-disposable.desktop`

```ini
[Desktop Entry]
Type=Session
Name=Mayotix Disposable Session
Comment=Ephemeral workspace — nothing persists after logout
Exec=/usr/bin/mayotix-disposable-session
TryExec=/usr/bin/mayotix-disposable-session
DesktopNames=Mayotix
Icon=system-lock-screen
```

GDM and SDDM scan `/usr/share/wayland-sessions/` for `Type=Session` entries. After installation, "Mayotix Disposable Session" appears in the session selector on the login screen alongside the standard persistent session.

### 3.3 SELinux Policy: `mayotix_disposable_t`

**Source**: `security/selinux/mayotix_disposable.te` and `mayotix_disposable.fc`

#### Domain Transition

```
xdm_t / unconfined_t
        │
        │  exec /usr/bin/mayotix-disposable-session
        │  (labeled mayotix_disposable_exec_t)
        │
        ▼
mayotix_disposable_t
```

The display manager (`xdm_t`) or a user shell (`unconfined_t`) executes the disposable session script, triggering an automatic domain transition into `mayotix_disposable_t`.

#### Access Matrix

| Resource | Access | Rationale |
|---|---|---|
| `/usr`, `/bin`, `/sbin`, `/lib` (`bin_t`, `lib_t`) | Read + execute | System binaries and shared libraries |
| `/etc` (`etc_t`, `locale_t`) | Read-only | Configuration, locale data |
| `/tmp`, tmpfs (`tmp_t`, `tmpfs_t`) | **Full read/write/create/delete** | Ephemeral workspace — core writable area |
| `/home` root (`home_root_t`) | Search + getattr only | bwrap needs to traverse `/home` to mount over it |
| `/home/$USER` (`user_home_t`, `user_home_dir_t`) | **DENIED** | No allow rules — default deny blocks all access |
| `/var` (`var_t`, `var_log_t`) | Read-only | System state (read), no writes |
| `/dev` (`device_t`, `null_device_t`, `urandom_device_t`) | Read/write for null, urandom | Graphical session device access |
| `/dev/pts` (`devpts_t`) | Read/write + ioctl | PTY allocation for terminal emulators |
| `/proc` (`proc_t`) | Read-only | Process enumeration (mesa, libinput) |
| `/sys` (`sysfs_t`) | Read-only | Hardware enumeration (mesa, libinput) |
| Unix sockets | Full (self) | D-Bus and Wayland IPC |
| Capabilities | `setuid`, `setgid`, `sys_chroot`, `dac_read_search` | Minimal set for bwrap namespace setup |

#### Key Security Property: Home Directory Denial

The disposable policy **intentionally omits** all `allow` rules for `user_home_t` and `user_home_dir_t`. SELinux operates on a default-deny basis — without an explicit allow rule, any attempt to read, write, or traverse the persistent home directory generates an AVC denial and is blocked.

This is the critical difference from `mayotix_sandbox_t`, which grants read access to the user's home for sandboxed applications that need to open user files.

#### Compiling and Loading the Policy

```bash
# Compile
checkmodule -M -m -o mayotix_disposable.mod mayotix_disposable.te

# Package
semodule_package -o mayotix_disposable.pp -m mayotix_disposable.mod -f mayotix_disposable.fc

# Install
sudo semodule -i mayotix_disposable.pp

# Verify
sudo semodule -l | grep mayotix_disposable

# Apply file contexts
sudo restorecon -v /usr/bin/mayotix-disposable-session
```

## 4. Session Lifecycle

### 4.1 Startup Sequence

```
1. User selects "Mayotix Disposable Session" at login screen
2. Display manager (xdm_t) exec's /usr/bin/mayotix-disposable-session
3. SELinux transitions process to mayotix_disposable_t
4. Script creates ephemeral tmpfs directories under /tmp/
5. Home skeleton (.config, .cache, Desktop, …) is populated
6. Cleanup trap is registered (EXIT, INT, TERM, HUP)
7. bwrap prerequisites are verified
8. bwrap argument array is assembled:
   - Namespace isolation (user, IPC, PID, optionally net)
   - 11 dangerous capabilities dropped
   - Read-only binds for system directories
   - tmpfs overlay on /home and /tmp
   - Ephemeral home bound into the container
   - Environment variables set
9. bwrap exec's sway inside the sandbox
10. User works normally — all writes go to tmpfs
```

### 4.2 Shutdown Sequence

```
1. User logs out of sway (or session is terminated)
2. bwrap process exits, returning control to the launcher
3. EXIT trap fires cleanup()
4. For each ephemeral directory (HOME_TMP, TMP_TMP, XDG_TMP):
   a. If shred is available: find -type f -exec shred -fuz
      (overwrites file contents with random data, then zeros, then unlinks)
   b. rm -rf the directory tree
5. Script logs "Cleanup complete. No persistent data remains."
6. Script exits, display manager returns to login screen
```

### 4.3 Signal Handling

The cleanup trap covers:
- `EXIT` — normal logout
- `INT` — Ctrl+C (if session is terminal-based)
- `TERM` — `kill` / system shutdown
- `HUP` — terminal hangup / session disconnect

## 5. Security Analysis

### 5.1 Threat: Data Remanence (Forensic Recovery)

**Risk**: After logout, an attacker with physical access recovers user data from disk.

**Mitigation layers**:
1. **No disk writes** — all user data lives on tmpfs (RAM-backed filesystem). There are no persistent writes to any block device.
2. **Secure wipe on exit** — `shred -fuz` overwrites file contents with random data before unlinking. On tmpfs, the kernel reclaims the memory pages on `munmap/free`.
3. **Swap protection** — MAYOTIX Phase 2 enables encrypted swap; any pages that swap out are encrypted at rest.
4. **No core dumps** — capability `SYS_PTRACE` is dropped, and MAYOTIX Phase 2 sets `kernel.core_pattern=|/bin/false`.

### 5.2 Threat: Persistent Malware Installation

**Risk**: Malware downloaded during a disposable session installs itself to survive reboot.

**Mitigation layers**:
1. **No writable persistent paths** — `/home`, `/usr`, `/etc`, `/var` are all read-only or denied.
2. **SELinux confinement** — `mayotix_disposable_t` has no `write` or `create` permission on any persistent filesystem type.
3. **Namespace isolation** — user namespace prevents privilege escalation; PID namespace limits process visibility.
4. **Session destruction** — even if malware writes to tmpfs, everything is wiped on logout.

### 5.3 Threat: Lateral Movement via Home Directory

**Risk**: A compromised disposable session reads SSH keys, GPG keys, browser credentials from `~/.ssh`, `~/.gnupg`, etc.

**Mitigation layers**:
1. **SELinux deny** — no allow rules for `user_home_t` or `user_home_dir_t`; AVC denial blocks access at the kernel level.
2. **bwrap mount overlay** — `/home` is a fresh tmpfs; the real home directory is never mounted into the namespace.
3. **Double barrier** — both the namespace mount table AND the MAC policy must be bypassed simultaneously.

### 5.4 Threat: Network-Based Exfiltration

**Risk**: Data exfiltration from the disposable session.

**Mitigation**:
- Network is **disabled by default** (`--unshare-net`).
- When network is explicitly enabled (`--network` flag), standard MAYOTIX firewall rules still apply.
- The disposable session has no access to persistent secrets anyway, limiting the value of exfiltration.

## 6. Namespace Isolation Details

| Namespace | Flag | Effect |
|---|---|---|
| User | `--unshare-user` | Prevents UID/GID privilege escalation |
| IPC | `--unshare-ipc` | Isolates System V IPC (shared memory, semaphores, message queues) |
| PID | `--unshare-pid` | Process table isolation; PID 1 inside sandbox is bwrap init |
| Network | `--unshare-net` | No network interfaces (default); loopback only |

## 7. Dropped Capabilities

The following capabilities are explicitly dropped inside the sandbox:

| Capability | Risk if Retained |
|---|---|
| `CAP_SYS_ADMIN` | Mount filesystems, configure namespaces, bypass many checks |
| `CAP_SYS_MODULE` | Load kernel modules |
| `CAP_SYS_PTRACE` | Trace/debug arbitrary processes, read memory |
| `CAP_SYS_RAWIO` | Raw I/O port and memory access |
| `CAP_SYS_BOOT` | Reboot the system |
| `CAP_SYS_NICE` | Elevate scheduling priority |
| `CAP_NET_ADMIN` | Network configuration, firewall rules |
| `CAP_NET_RAW` | Raw sockets (packet sniffing) |
| `CAP_MKNOD` | Create device nodes |
| `CAP_AUDIT_WRITE` | Write to the kernel audit log |
| `CAP_AUDIT_CONTROL` | Configure audit subsystem |

## 8. Installation

### 8.1 Script Installation

```bash
# Install the session launcher
sudo install -m 755 desktop/sessions/mayotix-disposable-session.sh \
    /usr/bin/mayotix-disposable-session

# Install the display manager session entry
sudo install -m 644 desktop/sessions/mayotix-disposable.desktop \
    /usr/share/wayland-sessions/mayotix-disposable.desktop
```

### 8.2 SELinux Policy Installation

```bash
cd security/selinux/

# Compile the type enforcement module
checkmodule -M -m -o mayotix_disposable.mod mayotix_disposable.te

# Package with file contexts
semodule_package -o mayotix_disposable.pp \
    -m mayotix_disposable.mod \
    -f mayotix_disposable.fc

# Load the policy module
sudo semodule -i mayotix_disposable.pp

# Apply file contexts to the installed binary
sudo restorecon -Rv /usr/bin/mayotix-disposable-session
```

### 8.3 Prerequisites

- `bubblewrap` (bwrap) — unprivileged sandboxing
- `sway` — Wayland compositor (launched inside the sandbox)
- `coreutils` — `shred` for secure wipe (optional but recommended)
- SELinux in enforcing mode with `checkmodule` / `semodule` tools

## 9. Verification

### 9.1 Display Manager Integration

```bash
# Confirm the session file is discovered
ls -la /usr/share/wayland-sessions/mayotix-disposable.desktop

# Restart the display manager and verify the entry appears
sudo systemctl restart gdm
# "Mayotix Disposable Session" should appear in the session selector
```

### 9.2 SELinux Policy Verification

```bash
# Verify module is loaded
sudo semodule -l | grep mayotix_disposable

# Check file context
ls -Z /usr/bin/mayotix-disposable-session
# Expected: system_u:object_r:mayotix_disposable_exec_t:s0

# After launching a disposable session, verify the domain
ps -eZ | grep mayotix
# Expected: …:mayotix_disposable_t:… processes

# Check for AVC denials (should be clean for normal operation)
sudo ausearch -m avc -ts recent | grep mayotix_disposable
```

### 9.3 Isolation Verification

```bash
# Inside a disposable session:

# Verify ephemeral home
echo $MAYOTIX_DISPOSABLE   # → 1
echo $HOME                  # → /home/<user>
ls -la ~/                   # Should show fresh skeleton, NOT persistent files

# Verify no access to persistent home
# (This relies on bwrap mount overlay; SELinux is the backstop)
cat /home/<user>/.ssh/id_rsa 2>&1  # Should fail — file doesn't exist in tmpfs

# Verify network isolation (default)
ip link show       # Should show only loopback (lo)
ping -c1 8.8.8.8   # Should fail with "Network is unreachable"

# Verify capability restrictions
cat /proc/self/status | grep Cap
# CapBnd should show reduced bitmask (no SYS_ADMIN, SYS_PTRACE, etc.)

# Verify PID namespace
ps aux   # Should show only sandbox processes, not host PIDs
```

### 9.4 Cleanup Verification

```bash
# Before logout, note the ephemeral directory paths from launch logs:
#   [mayotix-disposable-session] Home: /tmp/mayotix-disposable-session.home.XXXXXX

# After logout, from a persistent session:
ls /tmp/mayotix-disposable-session.*
# Should return "No such file or directory" — cleanup removed everything
```

### 9.5 Automated Test Script

```bash
#!/usr/bin/env bash
# Quick smoke test for the disposable session launcher
set -e

echo "=== Disposable Session Smoke Test ==="

# 1. Script exists and is executable
test -x /usr/bin/mayotix-disposable-session \
    && echo "PASS: Script exists and is executable" \
    || echo "FAIL: Script not found or not executable"

# 2. Desktop file exists
test -f /usr/share/wayland-sessions/mayotix-disposable.desktop \
    && echo "PASS: Desktop session file exists" \
    || echo "FAIL: Desktop session file not found"

# 3. SELinux module loaded
sudo semodule -l | grep -q mayotix_disposable \
    && echo "PASS: SELinux module loaded" \
    || echo "FAIL: SELinux module not loaded"

# 4. File context correct
CONTEXT=$(ls -Z /usr/bin/mayotix-disposable-session 2>/dev/null | awk '{print $1}')
echo "$CONTEXT" | grep -q "mayotix_disposable_exec_t" \
    && echo "PASS: SELinux file context correct" \
    || echo "FAIL: File context is '$CONTEXT'"

# 5. bwrap available
command -v bwrap >/dev/null \
    && echo "PASS: bwrap installed" \
    || echo "FAIL: bwrap not found"

echo "=== Smoke Test Complete ==="
```

## 10. Troubleshooting

### Session fails to start

```bash
# Check bwrap is installed
command -v bwrap

# Check SELinux isn't blocking the transition
sudo ausearch -m avc -ts recent | grep disposable

# Run with verbose output
bash -x /usr/bin/mayotix-disposable-session 2>&1 | head -50
```

### Graphical applications don't launch

```bash
# Verify Wayland socket is accessible inside the sandbox
ls -la $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY

# Check DISPLAY / WAYLAND_DISPLAY are set
echo $WAYLAND_DISPLAY
echo $DISPLAY
```

### SELinux AVC denials in the session

```bash
# Get human-readable denial explanations
sudo ausearch -m avc -ts recent | audit2why

# If a legitimate access is being blocked, update the .te policy:
# 1. Add the required allow rule
# 2. Recompile and reload: checkmodule → semodule_package → semodule -i
```

## 11. File Inventory

| File | Install Path | Purpose |
|---|---|---|
| `desktop/sessions/mayotix-disposable-session.sh` | `/usr/bin/mayotix-disposable-session` | Session launcher script |
| `desktop/sessions/mayotix-disposable.desktop` | `/usr/share/wayland-sessions/mayotix-disposable.desktop` | Display manager entry |
| `security/selinux/mayotix_disposable.te` | Compiled to `.pp` module | SELinux type enforcement policy |
| `security/selinux/mayotix_disposable.fc` | Compiled into `.pp` module | SELinux file context definitions |
| `docs/PHASE3_WEEK4_DISPOSABLE.md` | Reference documentation | This document |

---

*MAYOTIX Development Team*  
*Phase 3 Week 4 — Ephemeral / Disposable Workspace Sessions*  
*Date: 2026-09-13*
