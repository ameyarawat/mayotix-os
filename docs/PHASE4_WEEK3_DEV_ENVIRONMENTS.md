# MAYOTIX OS Phase 4 Week 3: Isolated Ephemeral Dev Environments

This document outlines the implementation of isolated, ephemeral development environments for MAYOTIX OS. We preserve workstation immutability by confining development toolchains within containers that enforce strict host filesystem boundaries, non-persistent state, and comprehensive audit logging.

---

## Overview

Phase 4 Week 3 focuses on delivering **zero-remanence development workspaces** via hardened Distrobox/Toolbx integrations. These environments ensure that:
- Host system remains pristine (no persistent changes from development tools).
- Developer workflows are reproducible and portable.
- All container lifecycle events are audited for security compliance.
- Ephemeral mode guarantees no data persists after container termination.

---

## Technical Implementation

### 1. Hardened Dev Container Engine (`desktop/dev-environments/mayotix-devbox.sh`)

A secure wrapper around Distrobox/Toolbx (with Podman fallback) that enforces:
- **Restricted Host Mounts**:
  - `~/Projects` → `/home/developer/Project` (read-write, labeled `z` for SELinux)
  - `$HOME` → `/home/developer` (read-only, prevents persistence of dotfile changes)
  - Host root `/` → `/rootfs` (read-only, no direct access to host system)
- **Isolated Filesystems**:
  - Private `/tmp` (tmpfs, no host tmp sharing)
  - Private IPC namespace (prevents cross-container interference)
- **Capability Hardening**:
  - Drops dangerous Linux capabilities (SYS_ADMIN, SYS_PTRACE, etc.)
- **Network Modes**:
  - `--network none`: Complete network isolation (default)
  - `--network private`: Isolated bridge network
  - `--network host`: Host network (use with caution)
- **Ephemeral Execution**:
  - `--ephemeral`: Automatically removes container on exit (`--rm`)
  - Without flag: Container persists for reuse (manual cleanup required)
- **Audit Integration**:
  - Invokes `devbox-audit-hook.sh` on container start/stop (if enabled)

#### Usage Examples

```bash
# Ephemeral, network-isolated dev shell (no persistence)
mayotix-devbox.sh --ephemeral --network none -- bash

# Persistent container with workspace mounted, audit enabled
mayotix-devbox.sh --workspace $HOME/code -- name my-dev-container

# Rootless container with host network (for debugging)
mayotix-devbox.sh --network host -- ephemeral -- podman ps
```

---

### 2. Dev Container Recipes & Containerfiles

#### Base Developer Image (`desktop/dev-environments/recipes/dev-base.Containerfile`)
- **Foundation**: Fedora 40 minimal base
- **Security First**:
  - Non-root user `developer` (UID 1000) by default
  - Minimal package set (bash, coreutils, git, make, gcc, etc.)
  - Pre-installed security linters: `shellcheck`, `hadolint`, `trivy`, `audit`
  - Container engines: `podman`, `buildah`, `skopeo` (for nested container safety)
- **Clean Build**: `dnf clean all` and cache removal to minimize image size

#### Rust/Go Developer Image (`desktop/dev-environments/recipes/dev-rust-go.Containerfile`)
- **Extends**: `mayotix/devbox:dev-base`
- **Toolchains**:
  - Rust: `rustc`, `cargo` (via Fedora packages)
  - Go: `golang` (via Fedora packages)
- **Maintains**:
  - Non-root user enforcement
  - All base image security properties
- **Ready For**: Systems programming, web services, cloud-native development

#### Building Recipes Locally
```bash
# Build base image
podman build -t mayotix/devbox:dev-base -f desktop/dev-environments/recipes/dev-base.Containerfile .

# Build Rust/Go variant
podman build -t mayotix/devbox:dev-rust-go -f desktop/dev-environments/recipes/dev-rust-go.Containerfile .
```

---

### 3. Dev Container Lifecycle Audit & Monitoring (`desktop/dev-environments/devbox-audit-hook.sh`)

Logs all container lifecycle events to both `journald` (via `logger`) and a local audit log (`~/.local/state/mayotix/devbox-audit.log`).

#### Captured Events
- `CREATE`: Container initialization
- `START`: Container process launch
- `ENTER`: User attaches to container (e.g., via `distrobox enter`)
- `EXEC`: Arbitrary command execution inside container
- `STOP`: Container graceful shutdown
- `TERMINATE`: Container process exit
- `REMOVE`: Container deletion

#### Audit Record Structure (JSON Lines)
```json
{
  "timestamp": "2026-09-14T10:30:00Z",
  "event": "DEVBOX_START",
  "container": "my-dev-container",
  "image": "mayotix/devbox:dev-rust-go",
  "user": "developer",
  "uid": 1000,
  "pid": 1234,
  "ephemeral": false,
  "network": "private",
  "workspace": "/home/developer/Projects",
  "exit_code": 0,
  "details": "{}"
}
```

#### Usage
```bash
# Manual audit invocation (typically called by mayotix-devbox.sh)
desktop/dev-environments/devbox-audit-hook.sh \
  --action START \
  --name my-dev-container \
  --image mayotix/devbox:dev-base \
  --ephemeral true \
  --network none \
  --workspace $HOME/Projects

# View recent audit events
desktop/dev-environments/devbox-audit-hook.sh --list
```

---

## Operational Workflow

### Typical Developer Session
1. **Launch Ephemeral Workspace**
   ```bash
   mayotix-devbox.sh --ephemeral --network none
   ```
   - Drops into a shell with `~/Projects` mounted RW
   - Host system and dotfiles protected via read-only binds
   - No network access (air-gapped by default)

2. **Develop & Test**
   - Edit files in `~/Projects` (changes persist on host)
   - Build/test using pre-installed toolchains (rust, go, etc.)
   - Scan containers with `trivy` (aligns with Phase 2)
   - Lint scripts with `shellcheck`, Dockerfiles with `hadolint`

3. **Exit & Cleanup**
   - On `exit` or `Ctrl+D`:
     - Container automatically removed (`--ephemeral`)
     - Ephemeral `/home` and `/tmp` tmpfs destroyed
     - Audit hook logs termination event
   - **Zero remanence**: No persistent container images, layers, or runtime artifacts left behind

### Persistent Containers (Optional)
For long-running services or cached build environments:
```bash
mayotix-devbox.sh --name persistent-dev --workspace $HOME/code
# Use container across multiple sessions
# Manual cleanup: podman rm -f persistent-dev
```

---

## Security Properties

| Property                | Implementation Detail                                                                 |
|-------------------------|---------------------------------------------------------------------------------------|
| **Filesystem Immunity** | Host root mounted read-only; only `~/Projects` and `$HOME` (ro) exposed               |
| **Ephemeral Storage**   | `/tmp`, `/var/tmp`, and `$HOME` (when ephemeral) are tmpfs, destroyed on exit       |
| **Process Isolation**   | Private user, IPC, PID, and optional network namespaces                              |
| **Privilege Reduction** | Drop of SYS_ADMIN, SYS_PTRACE, SYS_RAWIO, CAP_NET_ADMIN, etc.                        |
| **Mandatory Access Control** | SELinux enforcing; all bind mounts use `:z` label for container isolation      |
| **Supply Chain Safety** | Base images built from Fedora; signed via Cosign (Phase 2 policy)                    |
| **Observability**       | Full lifecycle audit to journald + local audit log                                   |

---

## Verification Procedures

### 1. Confirm Host Filesystem Protection
```bash
# Inside container:
touch /tmp/host-test      # Should succeed (private tmpfs)
touch /etc/host-test      # Should fail (read-only bind)
touch /host-system-test   # Should fail (no direct host access)
ls /home/$USER            # Should show only Projects (if bound ro) or empty
```

### 2. Verify Ephemeral Cleanup
```bash
mayotix-devbox.sh --ephemeral --network none -- bash -c "touch /persist && ls -la /persist"
# File created inside container
exit
# Re-launch same command:
mayotix-devbox.sh --ephemeral --network none -- bash -c "ls -la /persist 2>/dev/null || echo 'File not found'"
# Expected: "File not found"
```

### 3. Audit Log Validation
```bash
# Trigger an audited event
desktop/dev-environments/devbox-audit-hook.sh --action CREATE --name test-audit --image busybox

# Check journal
journalctl -t mayotix-devbox | grep test-audit

# Check local audit log
desktop/dev-environments/devbox-audit-hook.sh --list
```

---

## Maintenance & Image Management

### Base Image Updates
To refresh the base developer image with latest Fedora packages:
```bash
# Rebuild base (pulls latest Fedora:40)
podman build --pull -t mayotix/devbox:dev-base -f desktop/dev-environments/recipes/dev-base.Containerfile .

# Rebuild dependent images
podman build --pull -t mayotix/devbox:dev-rust-go -f desktop/dev-environments/recipes/dev-rust-go.Containerfile .
```

### Security Scanning (Phase 2 Integration)
Scan dev container images for vulnerabilities before use:
```bash
scripts/scan-container-vulnerabilities.sh --image mayotix/devbox:dev-base
# Blocks if CRITICAL/HIGH CVEs found
```

### Pruning Ephemeral Data
Ephemeral containers leave no persistent data by design. For persistent containers:
```bash
# List all devbox containers
podman ps -a --filter "label=io.containers.devbox=true"

# Remove stopped containers
podman container prune --filter "until=24h"
```

---

## Reference Architecture

```
Host System (Immutable)
├── / (ro bind)        → Container: /rootfs
├── /home              → Container: /home/developer (ro)
├── ~/Projects         → Container: /home/developer/Projects (rw, :z)
├── /tmp               → Host tmp (not shared)
└── /var/run/user/$UID/
                         → Container: /run/user/$UID (optional, for wayland/X11)

Container Isolation
├── User Namespace:    Unshared (UID 1000 mapped to host developer)
├── IPC Namespace:     Private
├── PID Namespace:     Private (PID 1 inside container)
├── Network Namespace: --network none (default) / private / host
├── Capabilities:      Dropped (SYS_ADMIN, SYS_PTRACE, SYS_RAWIO, NET_ADMIN, NET_RAW, etc.)
├── SELinux:           Enforced with type transition to devbox_t
└── Seccomp:           Inherits system default (can be hardened further via profile)
```

---

*MAYOTIX OS Engineering Team*  
*Phase 4 Week 3 — September 2026*