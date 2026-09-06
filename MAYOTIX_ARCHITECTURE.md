# MAYOTIX OS — COMPLETE ARCHITECTURE

**Date:** 2026-09-06  
**Status:** Architecture Phase (Phase 0)  
**Scope:** Technical foundation, security model, phased roadmap

---

## TABLE OF CONTENTS

1. Executive Summary
2. Base Distribution Selection
3. Boot & Security Architecture
4. Filesystem & Storage
5. Package Management
6. Update & Release Infrastructure
7. Desktop Environment Architecture
8. Service Architecture
9. CLI Architecture
10. Installer Architecture
11. Lab Environment Architecture
12. Gaming Architecture
13. Developer Environment Architecture
14. Security Threat Model
15. Security Controls Matrix
16. Testing Strategy
17. Repository Structure
18. CI/CD Architecture
19. Reproducible Builds Strategy
20. Phased Implementation Roadmap
21. Critical Dependencies & Risks
22. Technical Decisions & Rationale

---

## 1. EXECUTIVE SUMMARY

MAYOTIX OS is a **security-first, privacy-conscious, modular Linux distribution** combining premium minimalist UX with serious Linux power for security professionals, developers, defenders, gamers, and everyday users.

### Core Pillars

- **Security by Default** — Defense-in-depth: Secure Boot, SELinux, encryption, sandboxing
- **Privacy First** — Minimal telemetry, user control, no default data collection
- **Transparency** — Open architecture, understandable security posture, clear threat model
- **Usability** — Premium desktop experience inspired by but distinct from macOS
- **Modularity** — Optional security/gaming/developer environments
- **Maintainability** — Clean architecture, reproducible builds, comprehensive documentation

### Target First Release

**MAYOTIX OS 1.0** ships with:

- ✅ Bootable, installable distribution on real hardware
- ✅ Secure foundation (Secure Boot, SELinux enforcing, LUKS2 encryption)
- ✅ Premium MAYOTIX desktop with dock, workspaces, search
- ✅ Security Center showing posture & configuration
- ✅ MAYOTIX CLI for system management
- ✅ Sandboxed application model (Flatpak integration)
- ✅ Optional MAYOTIX Labs for isolated security testing
- ✅ Dual-boot safe installer
- ✅ Comprehensive documentation

Later releases add: gaming optimization, advanced developer modes, defender/OSINT tools, reproduction labs.

---

## 2. BASE DISTRIBUTION SELECTION

### Evaluation Criteria

| Criterion | Weight | Fedora | Debian | Ubuntu |
|-----------|--------|--------|--------|--------|
| Security updates | Critical | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ |
| SELinux support | Critical | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ |
| systemd hardening | High | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ |
| Release cycle | High | ⭐⭐⭐⭐ (6mo) | ⭐⭐ (2yr LTS) | ⭐⭐⭐ (2yr LTS) |
| Package freshness | High | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ |
| Gaming support | Medium | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ |
| Container support | Medium | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ |
| Immutable OS | Medium | ⭐⭐⭐⭐ (Silverblue) | ⭐⭐ | ⭐⭐ |
| Documentation | Medium | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| Community ecosystem | Medium | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |

### Recommendation: **FEDORA (with Silverblue reference)**

**Rationale:**

1. **SELinux First-Class Citizen** — Fedora maintains official SELinux policies; perfect for MAYOTIX's defense-in-depth
2. **systemd Hardening** — Red Hat/Fedora leads systemd security features; excellent for service isolation
3. **Fresh Packages** — 6-month release cycle allows modern tooling without sacrificing stability
4. **Gaming Ecosystem** — Strong ProtonGE, gaming driver, and community support
5. **Container/Podman** — Native Podman support for Labs environment
6. **Immutable OS Pattern** — Silverblue/Kinoite demonstrates image-based updates we can adapt
7. **Enterprise Security Mindset** — Red Hat's security culture benefits MAYOTIX architecture

**Not Chosen:**

- **Debian:** Too conservative for gaming/modern tooling, weaker SELinux integration
- **Ubuntu:** Too telemetry-focused, release cycle too long for security features

**Architecture Note:** Build MAYOTIX around Fedora's core (kernel, systemd, dnf) but avoid unnecessary coupling—future base migration should be possible.

---

## 3. BOOT & SECURITY ARCHITECTURE

### Boot Chain (UEFI Secure Boot)

```
Hardware
  ↓
UEFI firmware (checks Secure Boot)
  ↓
Shim bootloader (signed by Microsoft key)
  ↓
GRUB2 (signed by MAYOTIX key)
  ↓
Kernel + initramfs (signed by MAYOTIX key)
  ↓
Dracut initramfs (LUKS2 unlock prompt)
  ↓
systemd (reads SELinux policy)
  ↓
Login manager (GDM hardened)
  ↓
MAYOTIX desktop
```

### Key Management

| Component | Owned By | Storage | Rotation | Revocation |
|-----------|----------|---------|----------|-----------|
| Secure Boot PK | User | TPM/firmware | Manual | Firmware reset |
| Signing key (MAYOTIX) | Release team | CI/CD vault | Per-release | Key revocation list |
| Encryption key (LUKS2) | User | User's passphrase + TPM | On user request | Recovery key |

### Secure Boot Implementation

**NOT hardcoded production keys in Git.**

- User has full control of PK (Platform Key)
- MAYOTIX provides pre-signed components for convenience
- Users can disable Secure Boot if needed (clear choice, not hidden)
- Recovery mode allows key reset

### TPM 2.0 Integration (Optional)

- Measure boot chain into TPM PCRs
- Optional: encrypt LUKS key with TPM (requires specific PCR measurements)
- Fallback: passphrase-only encryption if TPM unavailable

---

## 4. FILESYSTEM & STORAGE ARCHITECTURE

### Partition Layout (UEFI/GPT)

```
/dev/sdX1  (EFI System)          512 MB   FAT32  (Secure Boot, GRUB2)
/dev/sdX2  (BIOS Boot)            1 MB    -      (legacy grub compatibility)
/dev/sdX3  (MAYOTIX Root)   [ENCRYPTED LUKS2]
           ├── /boot               2 GB   ext4   (plain, signed kernel)
           ├── /                  15+ GB  ext4   (root filesystem)
           ├── /var               5+ GB   ext4   (logs, caches)
           ├── /home              [rest]  ext4   (user data, per-mount encryption optional)
           └── /var/lib/...       (systemd, sandboxing data)
/dev/sdX4  (Recovery)            2 GB    ext4   (optional recovery partition)
```

### Encryption Strategy

**Root filesystem:** LUKS2 with:
- Argon2i key derivation
- 512-bit key
- Passphrase + TPM optional
- Recovery keys stored securely by user

**Home directory:** Optional per-user encryption (eCryptfs or fscrypt)

**Sensitive data:** Never logged, never unencrypted during boot

### Filesystem Permissions

```
/root            700  (root only)
/home            755  (user accessible)
/etc             755  (world readable, world-executable)
/etc/shadow      640  (root:shadow, shadow group for auth)
/var/log         755  (world readable by default, sensitive logs 640)
/tmp             1777 (world writable, sticky bit)
/srv             755  (services, restricted)
/var/spool       755  (mail, CUPS, etc. — service-specific)
```

---

## 5. PACKAGE MANAGEMENT ARCHITECTURE

### Package Manager: DNF (Fedora)

**Advantages:**
- Strong dependency resolution
- Excellent security update handling
- Plugin ecosystem
- Good for both system + dev packages

### Security Requirements

1. **Signed Repositories**
   - All official MAYOTIX repos signed with release key
   - Third-party repos warn clearly, require explicit acceptance
   - Repository keys pinned in system configuration

2. **Package Verification**
   - Every package must be GPG-signed
   - dnf verifies before installation
   - Fail-safe: unsigned packages rejected by default

3. **Trusted Sources Only**
   - Default repos: official MAYOTIX + Fedora
   - Community repos clearly labeled
   - RPMFusion (restricted) optional, clearly marked
   - AUR-style third-party repos not default

4. **Flatpak Integration** (for GUI apps)
   - Sandboxed application model
   - Optional, not replacement for system packages
   - Permission model visible to user
   - Portal-based file/device access

### Package Groups

```
base              — minimal bootable system
desktop           — MAYOTIX desktop + core apps
development       — compilers, git, IDEs
security-tools    — optional security env
gaming            — optional gaming support
labs              — optional isolated testing
```

---

## 6. UPDATE & RELEASE INFRASTRUCTURE

### Update Model: Image-Based (Reference: Silverblue)

**Why:** Atomic updates, easy rollback, consistent state

```
System state = Immutable /usr + Mutable /home, /var

Update process:
  1. Download new base image
  2. Verify signature + checksums
  3. Compose with local overrides
  4. Boot new image on next restart
  5. If failed, rollback to previous
```

**Fallback:** Traditional package updates for development/testing installs

### Update Channels

```
stable   → tested, monthly or as-needed
testing  → pre-release, weekly
nightly  → bleeding edge, automatic builds
```

### Signature & Verification

Every release artifact signed with:

```
sha256sum                (checksums)
↓
sha256sum.gpg            (signed checksums)
↓
release-key              (public key pinned in system)
↓
Build metadata (SBOM, version, timestamp)
```

User verification process:

```bash
gpg --verify sha256sum.gpg
sha256sum -c sha256sum
```

### Security Update Prioritization

- Critical: immediate hotfix
- High: within 1 week
- Medium: within 1 month
- Low: next scheduled release

---

## 7. DESKTOP ENVIRONMENT ARCHITECTURE

### Display Server

**Wayland** (GNOME 46+)

- Modern, secure protocol
- Better per-window permissions
- Excellent touchpad/HiDPI support
- Easier application sandboxing

Fallback: Xwayland for legacy apps (with warning)

### Desktop Components

| Component | Technology | Purpose |
|-----------|-----------|---------|
| Session | GNOME (customized) | Core desktop |
| Window manager | Mutter | Compositing, animations |
| Shell | GNOME Shell (custom theme) | Overview, search, activities |
| Applications | GTK4 | Modern, consistent UI |
| Dock | Custom GTK widget | Application launcher |
| Control Center | Settings (forked) | System configuration |
| Search | Custom GNOME Search plugin | Global search |
| Notifications | Native system | Desktop alerts |

### Visual Identity

**NOT copying macOS/iOS.**

Create **original** MAYOTIX design language:

- **Color Palette:** Dark: Deep blues/grays + accent; Light: Soft whites + accent
- **Typography:** System font (Liberation Sans), careful hierarchy
- **Spacing:** 4px/8px/16px grid, breathing room
- **Icons:** Custom SVG icon set (created, not Apple's)
- **Wallpaper:** Original abstract geometric designs
- **Animations:** Subtle (300ms easing), not flashy

### Key Features

1. **Centered Floating Dock**
   - 50 pixel tall, centered at bottom
   - Pinned apps + running indicators
   - Application menu available in Activities

2. **Workspace Management**
   - Default 6 workspaces: Everyday, Development, Security, Defense, Labs, Gaming
   - User-customizable
   - Super+Ctrl+Left/Right to switch
   - Workspace overview via Super+W

3. **Global Search** (Super+Space)
   - Search apps, files, settings, commands
   - Do NOT execute arbitrary shell commands
   - Safe search results only

4. **Control Center**
   - Wi-Fi, Bluetooth, VPN quick toggles
   - Audio, brightness, battery
   - Dark/light mode
   - Firewall status (read-only here, settings app for changes)

5. **Multi-Monitor Support**
   - Per-monitor scaling
   - Dock follows primary monitor
   - Application window spanning

---

## 8. SERVICE ARCHITECTURE

### Systemd Hardening Strategy

Every MAYOTIX service uses maximal appropriate hardening:

```ini
[Service]
Type=simple
Restart=on-failure
RestartSec=10s

# Security
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
PrivateDevices=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
LockPersonality=yes
RestrictRealtime=yes

# Capabilities
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=

# SystemCalls (when application supports)
SystemCallFilter=~@clock @debug @module @mount @obsolete @privileged @raw-io @reboot @swap
```

### Core Services

```
graphical-session      — User login + desktop
network-manager        — Network connectivity
systemd-resolved       — DNS resolution (with DoH option)
audit                  — SELinux audit logging
udev                   — Device management
cups                   — Printing (sandboxed)
avahi                  — mDNS (optional)
bluetooth              — Bluetooth (disabled by default)
wpa_supplicant         — WiFi security
firewalld              — Firewall
timedatectl            — NTP time sync
udisks2                — Mount management
polkit                 — Authorization
GDM                    — Login manager (hardened)
```

### Privilege Separation Model

```
User apps           → run as user, sandboxed
System services     → minimal required privileges
Root services       → only: boot, device mgmt, firewall
Privileged daemon   → policykit bridge for GUI elevation
```

---

## 9. CLI ARCHITECTURE

### Command: `mayotix`

Located: `/usr/bin/mayotix` (setuid NOT required)

Uses: polkit for privileged operations, safe IPC to systemd

#### Primary Commands

```bash
mayotix status              # System status overview
mayotix security            # Security posture (score, recommendations)
mayotix security audit      # Detailed security audit log
mayotix update              # Check/apply updates
mayotix doctor              # System diagnostics
mayotix network             # Network status, firewall config
mayotix firewall            # Firewall management
mayotix sandbox             # Application sandbox status
mayotix lab                 # Lab management
mayotix tools               # Security/dev tools available
mayotix mode                # Switch workspace mode
mayotix system              # System configuration
mayotix logs                # View important logs
mayotix recovery            # Recovery mode options
mayotix config              # Configuration management
```

### Safety Principles

- **No shell execution:** All arguments passed safely (no `shell=True`)
- **Input validation:** Strict allowlist for commands
- **Output encoding:** JSON/structured output safe for parsing
- **IPC security:** Authenticated, authorized message passing
- **Audit logging:** Privileged operations logged via audit daemon

---

## 10. INSTALLER ARCHITECTURE

### MAYOTIX Installer (Anaconda-based or custom)

**Requirements:**

1. Detect existing operating systems
2. Show disk/partition layout clearly
3. Support multiple installation types:
   - Fresh install (erase disk)
   - Alongside existing OS (dual boot)
   - Custom partitioning
   - Encrypted installation

4. Never automatically format without confirmation
5. Verify installation afterward
6. Handle interrupted installation gracefully

### Installer Workflow

```
1. Welcome screen → language, timezone
2. Storage configuration
   a. Automatic (partition disk automatically)
   b. Manual (expert partitioning)
   c. Existing OS detection + dual-boot option
3. Confirm destructive operations
   → Show exactly what will be written
   → Require explicit user confirmation
4. User account setup
5. Installation progress
6. Verify system boots
7. First-run configuration (optional Security Center onboarding)
```

### Safety Checks

- Disk space validation
- Filesystem integrity pre-check
- Boot loader verification post-install
- Bootloader configuration validation

---

## 11. LAB ENVIRONMENT ARCHITECTURE

### MAYOTIX Labs

Isolated virtualization environment for security testing.

**Technology:** libvirt + QEMU/KVM (Podman for containers)

### Lab Features

```bash
mayotix lab create          # Create new lab environment
mayotix lab start [name]    # Boot lab VMs
mayotix lab stop [name]     # Shut down lab
mayotix lab destroy [name]  # Delete lab (with confirmation)
mayotix lab status          # List running labs
```

### Lab Networks

```
Host system (MAYOTIX)
  ↓
Isolated virtual network (192.168.200.0/24)
  ├── Attacker VM (optional Kali/MAYOTIX)
  ├── Target VM (Linux/Windows)
  ├── Database server
  └── Web server
```

**Safety:**

- Labs isolated from host network by default
- User must explicitly bridge/expose
- Network interfaces clearly labeled
- No automatic external access

### Labs Possible Scenarios

- Web security labs
- Network analysis
- Incident response
- Malware analysis (safe sandbox)
- CTF environments
- Vulnerability research

---

## 12. GAMING ARCHITECTURE

### Gaming Mode (Optional)

Provides optimization for gaming while maintaining security.

**Does NOT disable security controls.**

### Components

- **Proton/Proton-GE** — Windows game compatibility layer
- **GameMode** — CPU scheduling optimization
- **MangoHUD** — Performance monitoring
- **Vulkan drivers** — GPU support
- **Steam** — Primary gaming platform

### Gaming Workspace

Dedicated workspace optimized for:
- GPU performance
- Input latency
- CPU scheduling
- Memory management

**Security maintained:**
- SELinux still enforces sandbox
- Firewall still active
- Updates still applied
- Encryption still active

Game-specific exceptions documented clearly.

---

## 13. DEVELOPER ENVIRONMENT ARCHITECTURE

### Development Tools (Default Install)

- Git, SSH, GPG
- Python 3.11+
- Node.js / npm
- Rust
- Go
- Java/Maven
- C/C++ (gcc, llvm)
- Docker/Podman
- IDEs (VS Code, JetBrains via Software center)

### Development Container Support

- Podman (native, daemon-less)
- Docker compatibility layer optional
- Development containers (devcontainers) supported

### Virtual Environment Management

- Python: venv, pyenv
- Node: nvm, fnm
- Rust: rustup
- Go: no special requirements

---

## 14. SECURITY THREAT MODEL

### Assets Protected

1. **User data** (documents, media, credentials, SSH keys)
2. **System integrity** (kernel, boot, config)
3. **Network communication** (traffic encryption, DNS)
4. **User privacy** (minimal collection, user control)
5. **Authentication** (user accounts, sudo/polkit)
6. **Physical device** (theft, unauthorized access)

### Threat Actors

- **Casual attacker** — script kiddie, malware user
- **Determined attacker** — targeted exploitation, privilege escalation
- **Insider threat** — compromised application, supply chain
- **Physical attacker** — device theft, lab access

### Threat Classes

| Threat | Attack Surface | Control | Residual Risk |
|--------|---------------|---------|----|
| Malware injection | Package repository | Signed packages, SBOM scanning, sandboxing | Supply chain compromise, zero-day |
| Privilege escalation | systemd, sudoers, polkit | Hardened systemd, LSM (SELinux), capability bounding | Kernel vulnerability, buggy policy |
| Boot tampering | Bootloader, kernel | Secure Boot, signature verification | Firmware vulnerability, key compromise |
| Data theft | Disk access, network | LUKS2 encryption, firewall, TLS | Key compromise, cold-boot attack |
| Malicious app | Application sandbox | Flatpak, SELinux, seccomp | Sandbox escape, excessive permissions granted |
| Network snooping | Network interfaces | Firewall, VPN support | User misconfiguration, weak protocols |
| Persistence | System services | SELinux confinement, audit logging | Undetected rootkit, privilege escalation |
| USB attacks | Removable media | Mount policies, no autorun | User override, firmware attack |

### Security Not Claimed

MAYOTIX does NOT claim to:
- Protect against quantum computing attacks
- Protect against sophisticated JTAG/hardware attacks
- Provide perfect anonymity (use Tor separately)
- Survive sophisticated forensics (depends on encryption strength)
- Protect against compromised firmware or hardware

---

## 15. SECURITY CONTROLS MATRIX

### Implementation Checklist

| Layer | Control | Implementation | Status |
|-------|---------|-----------------|--------|
| **Boot** | Secure Boot | Signed bootloader + kernel | Phase 1 |
| **Boot** | TPM integration | Optional PCR measurement | Phase 2 |
| **Storage** | Disk encryption | LUKS2 on root + swap | Phase 1 |
| **Kernel** | SELinux | Enforcing mode | Phase 1 |
| **Kernel** | AppArmor | Secondary (optional) | Phase 3 |
| **Services** | systemd hardening | Maximal per service | Phase 1 |
| **Services** | No root services | Run least-privilege | Phase 1 |
| **Network** | Firewall | nftables + firewalld | Phase 1 |
| **Network** | DNS over HTTPS | systemd-resolved + DoH | Phase 2 |
| **Applications** | Sandboxing | Flatpak by default | Phase 2 |
| **Applications** | Permissions model | Portal-based access | Phase 2 |
| **Updates** | Signed updates | GPG + checksums | Phase 1 |
| **Updates** | Atomic updates | Image-based | Phase 2 |
| **Logs** | Audit logging | auditd + journald | Phase 1 |
| **Logs** | No credential leakage | Strict log filtering | Phase 1 |
| **Access control** | Polkit | GUI elevation via polkit | Phase 1 |
| **Access control** | Sudo hardening | Minimal sudoers | Phase 1 |
| **Accounts** | Minimal users | No unnecessary accounts | Phase 0 |

---

## 16. TESTING STRATEGY

### Test Categories

1. **Unit Tests** (per-component)
   - CLI argument parsing
   - Configuration validation
   - Permission checks
   - Encryption functions

2. **Integration Tests** (component interaction)
   - Boot → login → desktop
   - Update download + verification
   - Installer → bootable system
   - Lab VM creation + networking

3. **Boot Tests** (VM + physical)
   - UEFI boot path
   - Secure Boot validation
   - LUKS unlock prompt
   - systemd startup sequence
   - SELinux enforcement

4. **Security Tests**
   - Permission model (capabilities, umask)
   - Privilege escalation attempts
   - Sandbox escape attempts
   - IPC message validation
   - Command injection prevention
   - Path traversal prevention

5. **Compatibility Tests**
   - VirtualBox, QEMU/KVM, VMware
   - NVIDIA/AMD GPU drivers
   - Common WiFi adapters
   - Dual-boot scenarios

6. **Upgrade Tests**
   - Update successful, boots
   - Rollback to previous version
   - Interrupted update recovery
   - Version schema validation

### Automated Testing

```
Commit → Unit tests → Integration tests → Build ISO 
        → Boot test in VM → Security scan → Dependency check 
        → SBOM generation → Sign artifacts → Release candidate
```

---

## 17. REPOSITORY STRUCTURE

```
mayotix/
│
├── SECURITY.md                    # Responsible disclosure
├── THREAT_MODEL.md                # This document (expanded)
├── SECURITY_ARCHITECTURE.md       # Security design deep-dive
├── BUILD.md                       # Build instructions
├── REPRODUCIBLE_BUILDS.md         # Reproducibility guide
├── RELEASE.md                     # Release process
├── DEVELOPMENT.md                 # Development workflow
├── CONTRIBUTING.md                # Contribution guidelines
├── CODE_OF_CONDUCT.md             # Community standards
├── PRIVACY.md                     # Privacy policy
├── LICENSE                        # GPL-3.0 (recommended)
│
├── boot/
│   ├── grub2/                     # GRUB2 configuration
│   ├── shim/                      # Shim bootloader
│   ├── kernel/                    # Kernel config options
│   └── dracut/                    # Initramfs modules
│
├── kernel/
│   ├── config/                    # Kernel config
│   ├── patches/                   # Custom patches
│   └── modules/                   # Custom kernel modules
│
├── desktop/
│   ├── gnome-shell/               # Shell customization
│   ├── mutter/                    # Window manager tweaks
│   ├── gsettings/                 # GNOME settings
│   ├── dock/                      # Custom dock widget
│   ├── control-center/            # Custom controls
│   ├── theme/                     # GTK theme + icons
│   ├── wallpaper/                 # Default artwork
│   └── css/                       # Custom styles
│
├── services/
│   ├── mayotix-security.service   # Security daemon
│   ├── mayotix-firewall.service   # Firewall manager
│   ├── mayotix-audit.service      # Audit daemon
│   ├── mayotix-update.service     # Update manager
│   └── *.service                  # Other services
│
├── cli/
│   ├── mayotix/                   # Main CLI tool
│   ├── commands/                  # Subcommands
│   ├── lib/                       # CLI library
│   └── tests/                     # CLI tests
│
├── installer/
│   ├── anaconda/                  # Installer config (if using Anaconda)
│   ├── custom/                    # Custom installer (if building from scratch)
│   ├── partitioning/              # Partition logic
│   ├── bootloader/                # Bootloader installation
│   └── validation/                # Post-install verification
│
├── labs/
│   ├── libvirt/                   # Lab VM definitions
│   ├── networks/                  # Virtual network configs
│   ├── templates/                 # VM templates
│   └── playbooks/                 # Lab scenarios
│
├── gaming/
│   ├── proton/                    # Proton configuration
│   ├── gamemode/                  # GameMode config
│   └── drivers/                   # GPU driver selection
│
├── developer/
│   ├── containers/                # Devcontainer templates
│   ├── environments/              # Development profiles
│   └── scripts/                   # Developer utilities
│
├── packages/
│   ├── specs/                     # RPM spec files
│   ├── patches/                   # Package patches
│   └── builds/                    # Build scripts
│
├── security/
│   ├── selinux/                   # SELinux policies
│   ├── apparmor/                  # AppArmor profiles
│   ├── seccomp/                   # seccomp filters
│   ├── audit/                     # Audit rules
│   └── policies/                  # Security policies
│
├── tests/
│   ├── unit/                      # Unit tests
│   ├── integration/               # Integration tests
│   ├── boot/                      # Boot tests
│   ├── security/                  # Security tests
│   ├── compatibility/             # Compatibility tests
│   └── scripts/                   # Test runners
│
├── tools/
│   ├── build/                     # Build automation
│   ├── ci/                        # CI/CD pipelines
│   ├── release/                   # Release automation
│   ├── sign/                      # Code signing
│   └── verify/                    # Verification tools
│
├── ci/
│   ├── .github/workflows/         # GitHub Actions
│   ├── .gitlab-ci.yml             # GitLab CI (if used)
│   ├── Jenkinsfile                # Jenkins (if used)
│   └── scripts/                   # CI helper scripts
│
└── docs/
    ├── architecture/              # Architecture docs
    ├── security/                  # Security documentation
    ├── installation/              # Installation guide
    ├── usage/                     # Usage guides
    ├── development/               # Development guides
    ├── api/                       # API documentation
    └── images/                    # Diagrams, screenshots
```

---

## 18. CI/CD ARCHITECTURE

### Build Pipeline

```
GitHub/GitLab Push
        ↓
Secret scan (detect API keys, etc.)
        ↓
Code style check (lint)
        ↓
Unit tests (cargo test, pytest, etc.)
        ↓
Build system packages (RPM specs)
        ↓
Static analysis (clippy, shellcheck, etc.)
        ↓
Dependency audit (cargo audit, pip audit, etc.)
        ↓
SBOM generation
        ↓
Build ISO
        ↓
Boot test in QEMU
        ↓
Security scan on artifacts
        ↓
Generate checksums
        ↓
Sign artifacts (GPG)
        ↓
Create release
        ↓
Publish artifacts
```

### Artifact Storage

```
s3://mayotix-releases/
├── mayotix-os-1.0.iso
├── mayotix-os-1.0.iso.sha256
├── mayotix-os-1.0.iso.sha256.gpg
├── mayotix-os-1.0.sbom.json
├── mayotix-os-1.0.sbom.json.gpg
├── mayotix-os-1.0.build.json
└── ...
```

### Code Review Requirements

- Minimum 2 approvals before merge
- All tests must pass
- No security findings marked "critical"
- Documentation updated
- CHANGELOG.md updated

### Release Gating

- Stable release: requires manual approval + sign-off
- Testing release: automatic on merged PR (to testing branch)
- Nightly: automatic rebuild daily

---

## 19. REPRODUCIBLE BUILDS STRATEGY

### Goal

An independent builder can reproduce the MAYOTIX ISO with identical checksum.

### Requirements

1. **Deterministic timestamps** — build date fixed in GRUB
2. **Pinned dependencies** — exact package versions
3. **Reproducible toolchain** — container-based build environment
4. **Known compiler flags** — reproducible optimization
5. **Documented process** — step-by-step build instructions
6. **Build metadata** — stored with each artifact

### Build Container

```dockerfile
FROM fedora:40
RUN dnf install -y \
    rpm-build \
    mock \
    dracut \
    grub2-tools \
    git \
    openssh-clients \
    gpg
```

### Build Verification

```bash
./scripts/reproduce-build.sh mayotix-os-1.0

# Output:
# Built: mayotix-os-1.0-local.iso
# Expected: 7c4d2a...
# Actual:   7c4d2a...
# ✓ VERIFIED
```

---

## 20. PHASED IMPLEMENTATION ROADMAP

### PHASE 0: Architecture ✓ (Current)

**Deliverables:**
- ✓ This architecture document
- Technical decisions documented
- Threat model established
- Team alignment

**Duration:** 1 week

---

### PHASE 1: Minimal Bootable OS (2 weeks)

**Deliverables:**
- Bootable ISO from Fedora 40
- UEFI + BIOS boot support
- Dracut initramfs + dracut LUKS2 module
- GRUB2 bootloader
- Basic systemd startup
- VT console terminal

**Acceptance Criteria:**
- ISO boots in QEMU
- ISO boots on physical hardware (test machine)
- Can unlock LUKS2 partition
- Reaches root shell
- `uname -a` shows kernel version

**Security Gates:**
- ✓ Signed grub2
- ✓ LUKS2 encryption functional
- ✓ SELinux basic policies
- ✓ Minimal running services

---

### PHASE 2: Secure Base System (2 weeks)

**Deliverables:**
- SELinux enforcing
- Systemd hardening applied to all services
- Firewall (firewalld) configured
- Package signing infrastructure
- Audit daemon running
- Security Center CLI tool (read-only)

**Acceptance Criteria:**
- SELinux shows 0 AVCs on clean boot
- Firewall blocks unexpected inbound
- All packages verified signed
- `mayotix security` shows status
- System boots deterministically

**Security Gates:**
- ✓ SELinux policy reviewed
- ✓ Service hardening verified
- ✓ Firewall rules tested
- ✓ Audit logging working

---

### PHASE 3: Package & Update Infrastructure (1 week)

**Deliverables:**
- RPM package building system
- Package repository setup
- Update checking mechanism
- Rollback capability

**Acceptance Criteria:**
- Can build custom RPM
- Package signatures verify
- Update check detects new versions
- Rollback restores previous system

---

### PHASE 4: MAYOTIX Desktop (3 weeks)

**Deliverables:**
- GNOME 46 customization
- MAYOTIX theme + icons
- Custom dock widget
- Workspace management
- Global search integration
- Control Center customization

**Acceptance Criteria:**
- Desktop boots with GDM login
- Dock displays applications
- Workspaces switch smoothly
- Search finds applications
- Visual identity consistent

---

### PHASE 5: Security Center (1 week)

**Deliverables:**
- GTK application
- Shows security posture
- Configuration score
- Recommendations display
- Action triggering

**Acceptance Criteria:**
- App launches from dock
- Shows accurate posture
- Score calculation transparent
- Recommendations actionable

---

### PHASE 6: MAYOTIX CLI (1 week)

**Deliverables:**
- `mayotix` command
- Subcommands: status, security, network, firewall, update
- JSON output format
- IPC to privileged daemon

**Acceptance Criteria:**
- All commands execute safely
- No command injection possible
- JSON output parseable
- Help text complete

---

### PHASE 7: Developer Environment (1 week)

**Deliverables:**
- Dev tools installed
- Container support (Podman)
- Development workspace
- IDE availability

**Acceptance Criteria:**
- Languages compile/run
- Containers work
- Development smooth

---

### PHASE 8: Defender / Security Environment (2 weeks)

**Deliverables:**
- Security tools available
- Lab environment setup
- Network analysis tools
- Incident response templates

---

### PHASE 9: MAYOTIX Labs (2 weeks)

**Deliverables:**
- Lab VM management
- Network isolation
- Lab templates

---

### PHASE 10: Gaming Support (1 week)

**Deliverables:**
- Steam installed
- Proton configured
- GameMode active
- GPU drivers

---

### PHASE 11: Installer (2 weeks)

**Deliverables:**
- Anaconda installer integration
- Dual-boot support
- Encrypted installation
- Partition validation

---

### PHASE 12: Hardening & Penetration Testing (2 weeks)

**Deliverables:**
- Privilege escalation tests
- Sandbox escape attempts
- Command injection tests
- Network exposure tests

---

### PHASE 13: Reproducible Signed Releases (1 week)

**Deliverables:**
- Signed ISOs
- Checksums + signatures
- Build reproducibility verified

---

### PHASE 14: Beta Release (1 week)

**Deliverables:**
- Public beta ISO
- Beta documentation
- Issue tracking

---

### PHASE 15: Production Release (Ongoing)

**Deliverables:**
- MAYOTIX OS 1.0
- Documentation complete
- Support channels
- Release notes

---

## 21. CRITICAL DEPENDENCIES & RISKS

### Critical Dependencies

| Dependency | Version | Risk | Mitigation |
|-----------|---------|------|-----------|
| Fedora | 40+ | Security update cycle, EOL | Pin major version, test upgrades |
| GNOME | 46+ | API stability | Pin version in CI |
| systemd | 255+ | Security features | Test hardening thoroughly |
| SELinux | 3.6+ | Policy complexity | Careful testing, monitoring |
| LUKS2 | cryptsetup 2.6+ | Encryption safety | Use stable, tested versions |
| Dracut | 059+ | Boot reliability | Extensive boot testing |
| Shim | 15+ | Secure Boot chain | Keep updated for key compromises |

### Technical Risks

| Risk | Probability | Impact | Mitigation |
|------|-----------|--------|-----------|
| SELinux breaks application | Medium | High | Extensive testing, policy refinement |
| Update fails, unbootable | Low | Critical | Atomic updates, rollback, recovery |
| Secure Boot breaks | Low | Critical | Hardware testing, key rotation plan |
| Performance degradation | Medium | Medium | Benchmarking, optimization passes |
| Installer corrupts disk | Low | Critical | Extensive validation, dry-run mode |
| Security vulnerability discovered | High | High | Rapid response, signed patches, disclosure |

### Mitigation Strategies

1. **Extensive automated testing** — catch issues before release
2. **Staged rollouts** — testing → early adopters → general release
3. **Rollback capability** — always maintain previous version
4. **Communication** — clear documentation, transparent disclosure
5. **Community testing** — beta program before 1.0

---

## 22. TECHNICAL DECISIONS & RATIONALE

### Decision: Fedora as Base

**Why not Debian?**
- Slower release cycle (2 years LTS)
- Weaker SELinux integration
- Conservative package versions

**Why not Ubuntu?**
- Telemetry concerns (Ubuntu Advantage, snap defaults)
- Canonical's business model more consumer-focused
- Less security-focused culture

**Fedora advantages:**
- Cutting-edge without sacrificing stability
- Red Hat's enterprise security mindset
- Best-in-class SELinux support
- Strong systemd hardening
- Gaming-friendly community

---

### Decision: Wayland over X11

**Why Wayland?**
- Modern, secure protocol (no single global input event)
- Better high-DPI/touchpad support
- Per-window permissions easier
- Eliminates X11 input injection vulnerabilities

**Fallback:** Xwayland for legacy apps (with user notification)

---

### Decision: systemd-resolved for DNS

**Why?**
- DNSSEC validation
- DNS-over-HTTPS support
- Better security posture
- Integrated with systemd ecosystem

---

### Decision: nftables + firewalld

**Why?**
- Modern packet filter
- Dynamic rule updates
- Zones abstraction
- Familiar firewall management

---

### Decision: No Default Snap Store

**Why?**
- Privacy concerns (Ubuntu telemetry)
- Slower package discovery
- Prefer native RPM + Flatpak

**Rationale:** Fedora doesn't default to snap; aligns with philosophy.

---

### Decision: Flatpak for GUI Applications

**Why?**
- Sandbox isolation
- Permission model transparent
- Platform-independent
- Strong community ecosystem

---

### Decision: Polkit for Privilege Escalation

**Why?**
- GUI-friendly authorization
- Fine-grained policy rules
- Standard across Linux desktops
- Security-auditable

---

### Decision: LUKS2 over LUKS1

**Why?**
- PBKDF2 → Argon2i (memory-hard)
- Better resistance to brute force
- Modern standard
- GRUB2 + dracut support mature

---

### Decision: Image-Based Updates (Reference: Silverblue)

**Why?**
- Atomic updates (all or nothing)
- Easy rollback
- Consistent system state
- Inspired by mobile OS reliability

**Implementation:** Compose base layers with immutable `/usr` + mutable `/home`, `/var`

---

### Decision: GPG for Package Signing

**Why?**
- Mature, proven standard
- Available everywhere
- User can independently verify
- No central authority required

---

### Decision: Audit Daemon for Security Logging

**Why?**
- Comprehensive system call logging
- SELinux integration
- Forensic capability
- Standard on enterprise Linux

---

## CONCLUSION

This architecture provides a **solid foundation** for MAYOTIX OS development. Key principles:

1. **Security by default** — not an afterthought
2. **Transparency** — threat model, architecture, decisions all documented
3. **Modularity** — security + gaming + developer features are optional overlays
4. **Incrementalism** — each phase produces bootable, testable result
5. **Defense-in-depth** — multiple layers of security, never single control

**Next Steps:**

1. ✅ Architecture review (internal team validation)
2. Start Phase 1 (minimal bootable OS)
3. Establish CI/CD pipeline
4. Create repository structure
5. Begin kernel/bootloader customization

---

**Document Version:** 1.0  
**Last Updated:** 2026-09-06  
**Owner:** MAYOTIX Architecture Team  
**Status:** Architecture Phase Complete → Ready for Phase 1
