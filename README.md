# MAYOTIX OS

**Beautiful by design. Secure by default. Powerful by choice.**

A security-first, privacy-conscious Linux distribution combining premium minimalist UX with serious Linux power for cybersecurity professionals, developers, defenders, gamers, and everyday users.

## Quick Start

### Development

```bash
# Read the architecture
cat MAYOTIX_ARCHITECTURE.md

# Build the ISO
./scripts/build-iso.sh

# Test in VM
qemu-system-x86_64 -cdrom mayotix-os-*.iso -m 4G -enable-kvm

# Run security checks
./scripts/security-check.sh
```

### Installation

```bash
# Write to USB (Linux/macOS)
sudo dd if=mayotix-os-*.iso of=/dev/sdX bs=4M status=progress
sync

# Or use Etcher
etcher mayotix-os-*.iso
```

## Documentation

- **[MAYOTIX_ARCHITECTURE.md](MAYOTIX_ARCHITECTURE.md)** — Complete technical architecture, threat model, phased roadmap
- **[SECURITY.md](SECURITY.md)** — Security model, threat model, responsible disclosure
- **[BUILD.md](BUILD.md)** — Build from source, reproducible builds
- **[DEVELOPMENT.md](DEVELOPMENT.md)** — Development workflow, environment setup
- **[CONTRIBUTING.md](CONTRIBUTING.md)** — Contribution guidelines, code standards

## Project Status

**Phase:** 0 ✓ → **1 (In Progress)**

- ✓ Architecture complete
- 🔄 Minimal bootable OS (2 weeks)
- ⏳ Secure base system
- ⏳ Desktop environment
- ⏳ Security tooling
- ⏳ Production release

## Key Features (1.0 Target)

- ✅ UEFI Secure Boot + BIOS support
- ✅ LUKS2 disk encryption
- ✅ SELinux enforcing
- ✅ Systemd hardened services
- ✅ Firewall (firewalld)
- ✅ MAYOTIX desktop (GNOME/Wayland)
- ✅ MAYOTIX CLI
- ✅ Security Center
- ✅ Optional Labs environment
- ✅ Dual-boot safe installer

## Security

MAYOTIX follows defense-in-depth security principles:

```
Hardware → UEFI → Secure Boot → Verified boot chain
  ↓
Hardened kernel (SELinux enforcing)
  ↓
Systemd service isolation
  ↓
Least privilege model
  ↓
Firewall + network security
  ↓
Application sandboxing (Flatpak)
  ↓
Audit logging & Security Center
```

**See [SECURITY.md](SECURITY.md) for complete threat model and controls matrix.**

### Reporting Security Issues

⚠️ **DO NOT** open security issues on GitHub.

See **[SECURITY.md](SECURITY.md)** for responsible disclosure process.

## License

GPL-3.0 — See LICENSE

## Community

- 📖 Documentation: https://mayotix.os/docs (coming soon)
- 🐛 Issues: https://github.com/mayotix/mayotix-os/issues
- 💬 Discussions: https://github.com/mayotix/mayotix-os/discussions
- 🔒 Security: See SECURITY.md

---

**MAYOTIX OS** — Built for security professionals, loved by everyday users.
