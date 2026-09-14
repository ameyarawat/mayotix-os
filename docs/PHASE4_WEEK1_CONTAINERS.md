# MAYOTIX OS Phase 4 Week 1: Hardened Rootless Container Engine

## Overview
This document details the implementation of a secure, rootless container engine foundation for MAYOTIX OS Phase 4 Week 1. The goal is to enable unprivileged execution of Podman and Buildah with proper user namespace isolation, seccomp filtering, and SELinux confinement.

---

## Components Implemented

### 1. Registry Configuration (`/etc/containers/registries.conf`)
- **Purpose**: Enforce secure image pulling by blocking unencrypted HTTP and restricting to trusted registries.
- **Key Features**:
  - Whitelisted search registries: `docker.io`, `quay.io`, `ghcr.io`, `registry.fedoraproject.org`
  - Empty insecure and block lists (secure-by-default)
  - Explicit registry definitions with TLS enforcement

### 2. Storage Configuration (`/etc/containers/storage.conf`)
- **Purpose**: Configure overlay storage driver optimized for rootless operation.
- **Key Features**:
  - Overlay driver with metacopy support
  - Fuse-overlayfs mount program for unprivileged execution
  - Secure mount options (`nodev`, restricted permissions)
  - Separate runroot and graphroot paths

### 3. Kernel Sysctl Hardening (`/etc/sysctl.d/99-mayotix-containers.conf`)
- **Purpose**: Tune kernel parameters for secure user namespace usage.
- **Parameters Set**:
  - `user.max_user_namespaces = 15000` (limit namespace exhaustion)
  - `fs.inotify.max_user_watches = 524288` (sufficient for container tooling)
  - `fs.inotify.max_user_instances = 1024` (inotify scaling)

### 4. SubUID/SubGID Allocation
- **Purpose**: Enable proper UID/GID mapping in user namespaces.
- **Implementation**: 
  - Allocate range `100000:65536` for the default user (`mayotix`)
  - Ensures 65,536 UIDs/GIDs available per user for container isolation

### 5. Container Engine SELinux Policy (`mayotix_container.te` & `.fc`)
- **Purpose**: Confine Podman and Buildah processes to prevent host compromise.
- **Domain**: `mayotix_container_t`
- **Key Allowances**:
  - Execution of system binaries/libraries in `/usr`
  - Access to configuration in `/etc/containers`
  - Use of temporary storage in `/tmp` and `/var`
  - Restricted home directory access (read/write in user namespace)
  - Pseudo-terminal access (`/dev/pts/*`)
  - Limited Linux capabilities safe for user namespaces:
    - `net_bind_service`, `setuid`, `setgid`, `sys_admin`, `sys_chroot`
    - `chown`, `dac_override`, `fowner`
  - Unix domain socket IPC for container runtime communication
- **File Contexts**:
  - `/usr/bin/podman` → `mayotix_container_exec_t`
  - `/usr/bin/buildah` → `mayotix_container_exec_t`

### 6. Hardening Script (`scripts/configure-container-hardening.sh`)
- **Purpose**: Automate deployment of all Week 1 container security controls.
- **Features**:
  - Idempotent configuration application
  - Dry-run mode (`--dry-run`) for testing
  - Privilege checking (requires root or dry-run)
  - Modular functions for each configuration area
  - Proper error handling and logging

---

## Verification Procedures

### 1. Confirm Rootless Capability
```bash
# Check current user can run containers without root
podman info --format '{{.Host.RemoteSocket.Exists}}'
# Should show: false (indicating rootless mode)

# Verify user namespace allocation
cat /etc/subuid /etc/subgid
# Should show mapping for default user: 100000:65536
```

### 2. Validate SELinux Confinement
```bash
# Check SELinux policy module is loaded
semodule -l | grep mayotix_container
# Should list mayotix_container module

# Run a container and check context
podman run --rm alpine ps -ef
# Then check in another terminal:
ps -efZ | grep container
# Processes should show mayotix_container_t context
```

### 3. Test Registry Restrictions
```bash
# Attempt to pull from non-whitelisted registry (should fail)
podman pull docker.io/alpine:latest  # Should succeed (whitelisted)
podman pull example.com/alpine:latest  # Should fail (not whitelisted)

# Attempt to pull via HTTP (should fail)
podman pull --tls-verify=false docker.io/alpine:latest  # Should fail
```

### 4. Verify Sysctl Settings
```bash
sysctl user.max_user_namespaces
# Should return: user.max_user_namespaces = 15000

sysctl fs.inotify.max_user_watches
# Should return: fs.inotify.max_user_watches = 524288
```

---

## Security Properties Achieved

| Security Aspect | Implementation | Protection Provided |
|----------------|----------------|---------------------|
| **Privilege Separation** | Rootless user namespaces | No root privileges needed for container operations |
| **Filesystem Isolation** | Private overlay storage + restricted mounts | Containers cannot access host root filesystem |
| **Network Isolation** | User namespace network separation | Container network stack isolated from host |
| **Process Isolation** | PID namespaces + SELinux confinement | Container processes invisible to host, restricted syscalls |
| **Resource Limits** | User namespace UID/GID mapping | Prevents host UID exhaustion and privilege escalation |
| **Secure Boot Components** | SELinux policy + seccomp (via runtime) | Defense-in-depth against container escapes |
| **Supply Chain Security** | Registry TLS enforcement | Prevents man-in-the-middle image tampering |

---

## Usage Examples

### Basic Rootless Container Execution
```bash
# Pull an image (non-root)
podman pull docker.io/library/nginx:latest

# Run a container
podman run --name webserver -d -p 8080:80 docker.io/library/nginx:latest

# Execute commands inside container
podman exec -it webserver sh
```

### Buildah Image Construction
```bash
# Build image without daemon
bud build -t myapp:latest .

# Push to registry (requires authentication)
bud push myapp:latest docker.io/myusername/myapp:latest
```

### Inspecting Container Security
```bash
# Check container runtime security info
podman info --format '{{.Host.SecurityOptions}}'

# List containers with SELinux context
podman ps --format "{{.ID}} {{.Names}} {{.SELinuxContext}}"
```

---

## Integration Notes

This Week 1 foundation integrates with subsequent Phase 4 weeks as follows:

- **Week 2 (Image Integrity)**: The registry configuration provides the baseline for Cosign signature verification policies
- **Week 3 (Dev Environments)**: Rootless containers enable secure Distrobox/Toolbx execution with minimal attack surface
- **Week 4 (Policy Linters)**: SELinux policy can be validated by automated linters in pre-commit hooks
- **Week 5 (ISO Build)**: All container hardening components are included in the Phase 4 ISO build

---

## Troubleshooting

### Common Issues

1. **"operation not permitted" when running containers**
   - **Cause**: SubUID/SubGID not properly allocated
   - **Fix**: Verify `/etc/subuid` and `/etc/subgid` contain correct ranges for your user

2. **SELinux denial messages in audit log**
   - **Cause**: Missing SELinux policy rules
   - **Fix**: Check `ausearch -m avc -ts recent` and update `mayotix_container.te` as needed

3. **Unable to pull from registry**
   - **Cause**: Registry not in whitelist or TLS issues
   - **Fix**: Verify `/etc/containers/registries.conf` and ensure registries support TLS

4. **Permission denied on temporary storage**
   - **Cause**: Incorrect storage configuration
   - **Fix**: Verify `/etc/containers/storage.conf` and ensure `/var/lib/containers/storage` is writable

---

*MAYOTIX OS Engineering Team*  
*Phase 4 Week 1 — September 2026*