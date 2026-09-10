# MAYOTIX OS Phase 3 Week 2: Containerized Application Sandbox

## Overview

This document describes the application sandboxing implementation for MAYOTIX OS Phase 3 Week 2. The sandboxing system provides defense-in-depth isolation for desktop applications using multiple complementary technologies:

1. **Bubblewrap** - Low-level Linux namespace and capability isolation
2. **Flatpak** - Application distribution with built-in sandboxing and permission controls
3. **SELinux** - Mandatory Access Control (MAC) enforcing domain transitions and restrictions
4. **Desktop Integration** - Hardened .desktop files that launch applications through sandboxing wrappers

The goal is to create a secure desktop environment where applications are confined to minimal necessary privileges, reducing the attack surface and limiting potential damage from compromised applications.

## Threat Model

The sandboxing system addresses the following threats:

- **Compromised Applications**: Limit damage from vulnerabilities in applications (e.g., browser exploits)
- **Malicious Applications**: Prevent unauthorized access to user data, hardware, or system resources
- **Inter-Application Attacks**: Isolate applications from each other to prevent cross-app data leaks
- **Privilege Escalation**: Restrict capabilities and access that could be used for local privilege escalation
- **Information Leakage**: Prevent unauthorized reading of sensitive files (SSH keys, documents, etc.)

## Architecture

### Bubblewrap Sandboxing

Bubblewrap provides low-level namespace isolation and capability dropping. The MAYOTIX implementation includes:

- **Minimal Read-Only Root**: Mounts essential system directories (/usr, /lib, /bin, etc.) as read-only binds
- **Ephemeral Storage**: Uses tmpfs for /tmp and /home directories to isolate application state
- **Namespace Isolation**: Configurable user, network, IPC, UTS, and cgroup namespaces
- **Capability Management**: Drops all Linux capabilities by default, with selective addition as needed
- **Profile-Based Configuration**: Predefined profiles for different security requirements

#### Key Components

- `sandbox/bubblewrap/mayotix-bwrap.sh`: Main sandboxing launcher script
- `sandbox/bubblewrap/profiles/network-isolated`: Profile for offline tools (no network access)
- `sandbox/bubblewrap/profiles/minimal-net`: Profile for tools needing minimal network access

### Flatpak Sandboxing

Flatpak provides application distribution with built-in sandboxing and permission controls. Our implementation includes:

- **Global Overrides**: System-wide restrictions that apply to all Flatpak applications
- **Wayland-Only Display**: Blocks X11 access to enforce Wayland-only display server
- **Restricted Host Access**: Limits filesystem, device, and IPC access to host system
- **Controlled Network Access**: Allows network access for updates while restricting other host interactions

#### Key Components

- `sandbox/flatpak/global-overrides.conf`: Hardened Flatpak override configuration
- `sandbox/flatpak/configure-flatpak.sh`: Script to install and apply the overrides

### SELinux Policy

SELinux provides Mandatory Access Control that enforces domain transitions and restricts application behavior even if they escape other sandboxing layers.

#### Key Components

- `security/selinux/mayotix_sandbox.te`: SELinux policy module defining the mayotix_sandbox_t domain
- Policy allows transitions from login domains (xdm_t, unconfined_t)
- Restricts access to system resources while permitting necessary operations
- Controls IPC via unix domain sockets and temporary/variable file access

### Desktop Integration

Hardened .desktop files ensure applications are launched through sandboxing wrappers, providing a seamless user experience while maintaining security.

#### Key Components

- `desktop/apps/`: Directory containing sandboxed application desktop entries
- Firefox launcher with Flatpak/bwrap integration
- Terminal emulator launcher with sandboxing implementation

## Implementation Details

### Bubblewrap Implementation

The `mayotix-bwrap.sh` script provides a flexible interface for sandboxing applications:

```bash
# Basic usage
mayotix-bwrap [--profile <profile>] [--network <none|private|host>] [--cap <cap>] [--] <command> [args...]
```

#### Profiles

1. **network-isolated**: Sets `--network none` for complete network isolation
   - Ideal for offline tools like text editors, image viewers, etc.
   - Unshares user, network, IPC, UTS, and cgroup namespaces
   - Drops all capabilities by default

2. **minimal-net**: Sets `--network private` for isolated network namespace
   - Designed for tools needing minimal network access (updates, licensing)
   - Creates private network stack but drops capabilities by default
   - Users can add specific capabilities via `--cap` if needed

#### Example Usage

```bash
# Run a network-isolated text editor
maywrap --profile network-isolated -- /usr/bin/gedit

# Run a tool that needs to bind to low ports (requires CAP_NET_BIND_SERVICE)
maywrap --network private --cap CAP_NET_BIND_SERVICE -- /usr/bin/some-network-tool

# Run with host networking (less secure, for specific cases)
maywrap --network host -- /usr/bin/some-tool-that-needs-host-net
```

### Flatpak Implementation

The Flatpak hardening focuses on restricting host access while maintaining necessary functionality:

#### Global Overrides Configuration

```ini
[Context]
# Filesystem access
host=false              # Disable host filesystem access
devices=false           # Disable access to host devices

# Socket access
socket=x11=false        # Block X11 (enforce Wayland-only)
socket=wayland=true     # Allow Wayland display socket
socket=pulseaudio=false # Disable PulseAudio (can be enabled per-app if needed)
socket=session-bus=true # Allow session bus communication
socket=system-bus=false # Restrict system bus access

# Network and IPC
network=true            # Allow network access (needed for updates)
ipc=false               # Disable host IPC
```

#### Application of Overrides

The `configure-flatpak.sh` script installs the overrides to `/etc/flatpak/overrides/global`, ensuring they apply system-wide to all Flatpak applications.

### SELinux Policy

The `mayotix_sandbox.te` policy defines a confined domain for sandboxed applications:

#### Key Allow Rules

- **Execution Access**: Read/execute access to binaries and libraries
- **Configuration Access**: Read access to /etc files (resolv.conf, nsswitch.conf)
- **Temporary Storage**: Read/write/create access to tmpfs and /var temporary files
- **Home Directory**: Read access to user's home directory (can be extended per-app)
- **IPC Access**: Unix stream socket communication for session bus, Wayland, etc.
- **Capabilities**: Specific capabilities allowed for sandboxing operations (net_bind_service, net_raw, sys_chroot)

#### Domain Transitions

- Allows transitions from `xdm_t` (display manager) and `unconfined_t` (user sessions)
- Ensures sandboxed applications start in the confined `mayotix_sandbox_t` domain

## Security Features

### Defense in Depth

The implementation layers multiple security mechanisms:

1. **Namespace Isolation** (Bubblewrap): Separates filesystem, network, IPC, UTS, and process trees
2. **Capability Restriction** (Bubblewrap): Drops Linux capabilities that could be used for privilege escalation
3. **Filesystem Isolation** (Bubblewrap + Flatpak): Read-only system mounts, ephemeral storage
4. **MAC Enforcement** (SELinux): Mandatory access controls that restrict actions even if other layers are bypassed
5. **Display Server Isolation** (Flatpak): Wayland-only enforcement blocks X11 attack surface
6. **Application Distribution** (Flatpak): Sandboxed application bundles with explicit permissions

### Default Deny Principle

- Network access: Disabled by default (network-isolated profile) or restricted (private namespace)
- Host filesystem access: Disabled (Flatpak host=false)
- Device access: Disabled (Flatpak devices=false)
- IPC access: Disabled by default (Flatpak ipc=false, Bubblewrap unshare-ipc)
- Capabilities: All dropped by default (Bubblewrap --cap-all)
- X11 access: Explicitly blocked (Flatpak socket=x11=false)

### Least Privilege

Each component grants only the minimum permissions necessary:

- Bubblewrap profiles can be tailored per-application
- Flatpak overrides provide baseline restrictions with per-app exceptions possible
- SELinux policy defines narrow permissions for the sandbox domain
- Desktop integrations launch specific applications with appropriate sandboxing

## Usage and Integration

### For Developers

Application developers can test their applications in the sandbox:

```bash
# Test with network isolation (default)
maywrap --profile network-isolated -- ./my-app

# Test with minimal network and specific capabilities
maywrap --network private --cap CAP_NET_BIND_SERVICE,CAP_NET_RAW -- ./my-network-tool

# Verify Flatpak application runs with overrides
flatpak run --branch=stable --arch=x86_64 --command=my-app org.example.MyApp
```

### For System Administrators

Administrators can manage and customize the sandboxing:

#### Modifying Profiles

1. Edit existing profiles in `sandbox/bubblewrap/profiles/`
2. Create new profiles as needed for specific application types
3. Profile files are sourced by the wrapper script, so they can set any script variable

#### Adjusting Flatpak Overrides

1. Modify `sandbox/flatpak/global-overrides.conf`
2. Run `sandbox/flatpak/configure-flatpak.sh` to apply changes
3. Changes affect all Flatpak applications on the system

#### SELinux Policy Management

1. Compile and load the policy:
   ```bash
   checkmodule -m -M -o mayotix_sandbox.mod mayotix_sandbox.te
   semodule_package -o mayotix_sandbox.pp -m mayotix_sandbox.mod
   semodule -i mayotix_sandbox.pp
   ```
2. To remove: `semodule -r mayotix_sandbox`
3. Check policy status: `semodule -l | grep mayotix`

### Application-Specific Sandboxing

For applications needing custom sandboxing, create specific profiles or desktop entries:

1. Create a new profile in `sandbox/bubblewrap/profiles/`
2. Create a .desktop file in `desktop/apps/` that uses the profile
3. For Flatpak applications, ensure they respect the global overrides or create specific overrides

## Testing and Validation

### Bubblewrap Testing

```bash
# Test network isolation (should fail to resolve external hosts)
maywrap --profile network-isolated -- ping 8.8.8.8

# Test filesystem isolation (should not see host home files)
maywrap --profile network-isolated -- ls $HOME

# Test capability dropping (should fail to bind to low ports)
maywrap --network private -- nc -l -p 80

# Test with required capability (should succeed)
maywrap --network private --cap CAP_NET_BIND_SERVICE -- nc -l -p 80
```

### Flatpak Testing

```bash
# Verify overrides are applied
flatpak info org.example.MyApp | grep -A 10 "Current permissions"

# Test X11 blocking (should fail to open display)
flatpak run --command=xeyes org.example.MyApp

# Test Wayland access (should work if compositor supports it)
flatpak run --command=wayland-info org.example.MyApp
```

### SELinux Testing

```bash
# Check if application runs in correct domain
ps -eZ | grep mayotix_sandbox_t

# Check for denied operations in audit logs
ausearch -m avc -ts recent
```

## Limitations and Considerations

### Known Limitations

1. **Graphics Acceleration**: Some GPU features may be restricted in sandboxed environments
2. **Hardware Access**: Direct access to hardware devices requires explicit configuration
3. **Interoperability**: Some applications expect unrestricted access to certain paths
4. **Performance Overhead**: Namespace creation and tmpfs mounts add minimal overhead

### Configuration Trade-offs

- **Security vs. Functionality**: More restrictive profiles may break some applications
- **Isolation vs. Integration**: Complete isolation limits useful inter-app communication
- **Ease of Use**: Transparent sandboxing requires proper desktop integration

### Future Improvements

1. **Per-Application Profiles**: More granular profile system based on application metadata
2. **Graphical Isolation**: Enhanced GPU sandboxing and container technologies
3. **Wayland Security**: Additional Wayland protocol restrictions and sandboxing
4. **Audit and Monitoring**: Better integration with system audit frameworks
5. **User Controls**: GUI tools for managing application sandboxing preferences

## Files Created

```
sandbox/
├── bubblewrap/
│   ├── mayotix-bwrap.sh          # Main sandboxing wrapper script
│   └── profiles/
│       ├── network-isolated      # Profile for offline tools
│       └── minimal-net           # Profile for minimal network access
├── flatpak/
│   ├── global-overrides.conf     # Hardened Flatpak override configuration
│   └── configure-flatpak.sh      # Script to apply Flatpak overrides
├── desktop/
│   └── apps/                     # Directory for sandboxed .desktop files
└── security/
    └── selinux/
        └── mayotix_sandbox.te    # SELinux policy for sandbox domain
```

## References

- Bubblewrap: https://github.com/containers/bubblewrap
- Flatpak: https://flatpak.org
- SELinux: https://github.com/SELinuxProject/selinux
- Linux Namespaces: https://man7.org/linux/man-pages/man7/namespaces.7
- Linux Capabilities: https://man7.org/linux/man-pages/man7/capabilities.7