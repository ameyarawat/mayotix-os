# MAYOTIX OS Changelog

All notable changes to MAYOTIX OS are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Phase 1: Minimal Bootable OS (In Progress)

- Initial repository structure
- Boot and security architecture documentation
- Kernel configuration with security hardening
- GRUB2 bootloader configuration with UEFI + BIOS support
- Dracut initramfs configuration for LUKS2 encryption
- MAYOTIX Security daemon service template
- Systemd hardening template with security best practices
- System configuration baseline
- Security check automation scripts
- Build system and ISO generation framework
- Development environment setup
- Contributing guidelines and code of conduct

### Architecture

- Complete technical architecture (MAYOTIX_ARCHITECTURE.md)
- Threat model and security controls matrix
- 15-phase implementation roadmap
- Base distribution selection (Fedora 40+)
- Package management strategy
- Update and release infrastructure design

### Security

- Secure Boot architecture documented
- LUKS2 encryption configuration
- SELinux enforcing mode policy framework
- Systemd service hardening standards
- Firewall architecture (nftables/firewalld)
- Audit logging infrastructure
- Pre-commit secret scanning hooks
- Security disclosure policy

### Documentation

- README with quick start guide
- SECURITY.md for vulnerability reporting
- BUILD.md with comprehensive build instructions
- DEVELOPMENT.md for development workflow
- CONTRIBUTING.md with contribution guidelines
- .gitignore with security-focused patterns

### Tools & Infrastructure

- build-iso.sh for ISO creation with reproducibility support
- security-check.sh for security verification
- init-dev.sh for environment setup
- Git pre-commit hooks for secret detection

---

## [1.0-alpha] — 2026-09-06

### Initial Release

First alpha release of MAYOTIX OS architecture and Phase 1 foundation.

**Status:** ⏳ In Development

- Architecture validated
- Repository initialized
- Build infrastructure ready
- Security framework in place
- Documentation complete

**Known Limitations:**

- Phase 1: Bootable ISO not yet functional (placeholder implementation)
- Desktop environment not included (Phase 4)
- Security Center not included (Phase 5)
- CLI tool not implemented (Phase 6)
- Installer not implemented (Phase 11)
- No production release yet

**Next Milestone:**

- Functional bootable ISO
- UEFI + BIOS boot support
- LUKS2 encryption working
- SELinux basic policies
- Dracut initramfs generation

---

## Release Notes

### For Phase 1 (Current)

#### Acceptance Criteria

- [ ] ISO boots in QEMU (both UEFI and BIOS)
- [ ] ISO boots on physical hardware
- [ ] Can unlock LUKS2 partition
- [ ] Reaches root shell
- [ ] SELinux shows 0 AVCs
- [ ] All security checks pass
- [ ] Reproducible builds verified

#### Known Issues

- Build system currently placeholder
- Dracut integration incomplete
- SELinux policies not compiled
- No actual boot testing yet

#### Testing

Run security checks before each commit:

```bash
./scripts/security-check.sh
```

---

## How to Read This File

- **Added** for new features
- **Changed** for changes in existing functionality
- **Deprecated** for soon-to-be removed features
- **Removed** for now removed features
- **Fixed** for any bug fixes
- **Security** for security improvements and fixes

---

**Last Updated:** 2026-09-06  
**Maintainer:** MAYOTIX OS Project
