# MAYOTIX OS Phase 5 Week 5: End-to-End Verification Procedures

This document defines the testing, verification, and reproducible build procedures for **MAYOTIX OS Phase 5: Network Security, Encrypted Privacy & Anonymity Routing** (`mayotix-os-5.0-alpha-x86_64.iso`).

---

## 1. Phase 5 Architectural Verification Matrix

Phase 5 introduces four foundational network security subsystems:

| Subsystem | Key Controls Verified | Audit Weight | Verification Target |
|---|---|---|---|
| **Week 1: Encrypted DNS (DoT)** | Strict `DNSOverTLS=yes`, DNSSEC validation, disabled mDNS/LLMNR, Quad9/Mullvad SNI pinning | 15 pts | `scripts/verify-encrypted-dns.sh` (12/12) |
| **Week 2: WireGuard VPN** | Noise_IKpsk2 encryption, 0600 key permissions, `AllowedIPs=0.0.0.0/0`, watchdog daemon | 15 pts | `scripts/verify-wireguard.sh` (20/20) |
| **Week 3: nftables Kill-Switch** | Fail-closed default `DROP`, port 51820 & 853 whitelisting, atomic cleartext leak drop | 15 pts | `scripts/verify-killswitch.sh` (27/27) |
| **Week 4: Tor Anonymity Routing** | SOCKS5 (9050), TransPort (9040), DNSPort (9053), stream isolation, transparent proxying | 10 pts | `scripts/verify-tor.sh` (18/18) |
| **System Security & Base** | Kernel hardening, 6 SELinux modules, sandboxing, rootless container security | 40 pts | Host & static checks |
| **Reproducible Build** | Deterministic ISO generation, `SOURCE_DATE_EPOCH` injection, checksum parity | 5 pts | `scripts/build-iso-phase5.sh` |
| **Total Audit Score** | Comprehensive end-to-end security compliance | **100 pts** | `scripts/conduct-security-audit-phase5.sh` |

---

## 2. Running Individual Milestone Test Suites

Before running the full system audit, each subsystem can be validated independently:

```bash
# 1. Verify Encrypted DNS (DNS-over-TLS via systemd-resolved)
sudo ./scripts/verify-encrypted-dns.sh --dry-run

# 2. Verify Kernel WireGuard VPN & Configuration Templates
sudo ./scripts/verify-wireguard.sh --dry-run

# 3. Verify Fail-Closed nftables Network Kill-Switch
sudo ./scripts/verify-killswitch.sh --dry-run

# 4. Verify Tor Isolation Proxy & Transparent Routing
sudo ./scripts/verify-tor.sh --dry-run
```

All four harnesses report structured status summaries and must achieve 100% compliance.

---

## 3. Running the Comprehensive Phase 5 Security Audit

The comprehensive audit evaluates the entire operating system against the 100-point Phase 5 security standard.

### Usage

```bash
# Comprehensive live audit
sudo ./scripts/conduct-security-audit-phase5.sh

# Simulated / dry-run evaluation
sudo ./scripts/conduct-security-audit-phase5.sh --dry-run

# Report-only mode
sudo ./scripts/conduct-security-audit-phase5.sh --report-only
```

### Audit Categories and Weights

1. **Base Kernel & System Hardening (10 pts)**: ASLR level 2, SMEP, SMAP, NX bit, stack protector, hardened systemd units.
2. **SELinux Policy Confinement (10 pts)**: Confinement across all 6 modules (`mayotix`, `mayotix_desktop`, `mayotix_sandbox`, `mayotix_security_center`, `mayotix_disposable`, `mayotix_container`).
3. **Sandboxing & Security Center (10 pts)**: Bubblewrap profiles, Flatpak overrides, Security Center GUI, ephemeral disposable sessions.
4. **Rootless Containers & Devbox Isolation (10 pts)**: Podman storage & registry hardening, signature policy attestation, devbox recipes.
5. **System-wide Encrypted DNS (15 pts)**: Strict DoT on port 853, DNSSEC enforcement, SNI-pinned privacy resolvers.
6. **Kernel WireGuard VPN & Routing Isolation (15 pts)**: Curve25519 + ChaCha20-Poly1305 + Noise_IKpsk2, full tunnel routing, connection watchdog.
7. **Fail-Closed nftables Network Kill-Switch (15 pts)**: Default drop on all chains, zero cleartext leakage on physical adapters, atomic transitions.
8. **Tor Isolation Proxy & Onion Routing (10 pts)**: SOCKS5 isolation, TransPort transparent redirection, DNSPort .onion routing.
9. **Reproducible Build Verification (5 pts)**: Deterministic ISO creation with `SOURCE_DATE_EPOCH`.

**Target Score**: ≥95/100  
**Compliance Standard**: **100/100 PASS**

---

## 4. Building the Phase 5 Bootable ISO

The unified build script packages all Phase 1–5 subsystems into a bootable ISO.

### Prerequisites

```bash
sudo dnf install -y dracut xorriso checkmodule policycoreutils-python-utils \
    sha256sum podman buildah wireguard-tools nftables tor
```

### Build Commands

```bash
# Standard ISO Build
sudo ./scripts/build-iso-phase5.sh

# Reproducible ISO Build (Recommended)
sudo ./scripts/build-iso-phase5.sh --reproducible

# Test-only mode (Validates staging directory without compiling ISO)
sudo ./scripts/build-iso-phase5.sh --test-only
```

### Generated Artifacts

Upon completion, the following artifacts are placed in `build/`:
- `mayotix-os-5.0-alpha-x86_64.iso`: Bootable ISO image
- `mayotix-os-5.0-alpha-x86_64.iso.sha256`: SHA-256 integrity checksum
- `mayotix-os-5.0-alpha-x86_64.iso.sha512`: SHA-512 integrity checksum
- `PHASE5_BUILD_REPORT.txt`: Detailed build summary and component inventory

---

## 5. Checksum Verification & QEMU Boot Testing

### Integrity Check

```bash
cd build
sha256sum -c mayotix-os-5.0-alpha-x86_64.iso.sha256
sha512sum -c mayotix-os-5.0-alpha-x86_64.iso.sha512
```

### QEMU Boot Test (UEFI Mode)

```bash
qemu-system-x86_64 \
    -enable-kvm \
    -m 4096 \
    -smp 4 \
    -bios /usr/share/OVMF/OVMF_CODE.fd \
    -cdrom build/mayotix-os-5.0-alpha-x86_64.iso \
    -boot d \
    -net nic -net user
```

Ensure the boot menu loads:
- **Default Entry**: `MAYOTIX OS 5.0-alpha (Security Hardened + WireGuard & Tor Privacy)`
- **Fail-Safe Entry**: `MAYOTIX OS 5.0-alpha (Fail-Safe / Network Debugging Mode)`
