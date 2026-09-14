# MAYOTIX OS Phase 4 Release Notes
## Version: 4.0-alpha
## Release Date: September 2026

This release marks the completion of Phase 4 of the MAYOTIX OS project, focusing on Developer Tooling & Container Security.

## Overview

MAYOTIX OS 4.0-alpha introduces a secure, isolated development workstation with:
- Hardened rootless container engine (Podman/Buildah)
- Cryptographic supply chain security (Cosign, Trivy, signature policy)
- Isolated, ephemeral development environments (Devbox)
- Integrated security linting and policy verification (pre-commit hooks, SELinux linters)

## Key Features

### Week 1: Hardened Rootless Container Engine
- Podman & Buildah configured for unprivileged user namespaces
- SubUID/SubGID mapping automation
- Strict seccomp filters
- Registry restrictions (no HTTP, signed registries only)
- Dedicated SELinux policy for container runtime (`mayotix_container.te`)

### Week 2: Container Image Integrity & Attestation
- Native Cosign integration for image signature verification
- Signature attestation policy (`/etc/containers/policy.json`) blocking unsigned images
- Automated Trivy vulnerability scanning
- CI/CD gating scripts preventing vulnerable base layers

### Week 3: Isolated Ephemeral Dev Environments
- Hardened Devbox wrapper (`mayotix-devbox.sh`) with restricted host mounts
- Base developer image (Fedora 40, non-root, security linters pre-installed)
- Rust/Go variant image
- Container lifecycle audit hook (`devbox-audit-hook.sh`) logging to journald

### Week 4: Security-Focused Local CI/CD & Policy Linters
- Git pre-commit hooks: secret detection, ShellCheck, Hadolint
- SELinux policy linter & verifier (static analysis + compilation check)
- Local Phase 4 compliance test suite
- Comprehensive documentation

### Week 5: Phase 4 ISO Build & End-to-End Verification
- Unified ISO build script (`scripts/build-iso-phase4.sh`) with reproducible build support
- Comprehensive security audit framework (`scripts/conduct-security-audit-phase4.sh`)
- Release notes and verification documentation
- Updated CI workflow for Phase 4 validation

## Security Improvements

- **Rootless by Default**: All container engines run as unprivileged users
- **Supply Chain Security**: Cryptographic verification of all container images
- **Environment Isolation**: Development workspaces confined to containers with no persistent host changes
- **Policy as Code**: SELinux policies and compliance checks integrated into build process
- **Shift-Left Security**: Pre-commit hooks prevent unsafe code from entering the repository

## Known Limitations

- The ISO build process currently generates a placeholder kernel/initramfs; in production these would be built from source.
- SELinux policy compilation requires host-based SELinux development tools.
- Some checks in the compliance suite rely on host configuration that may not be present in containerized build environments.

## Getting Started

See `docs/PHASE4_WEEK5_VERIFICATION.md` for build and test procedures.

## References

- MAYOTIX OS Roadmap: `docs/PHASE4_ROADMAP.md`
- Phase 4 Week 1: `docs/PHASE4_WEEK1_CONTAINERS.md`
- Phase 4 Week 2: `docs/PHASE4_WEEK2_ATTESTATION.md`
- Phase 4 Week 3: `docs/PHASE4_WEEK3_DEV_ENVIRONMENTS.md`
- Phase 4 Week 4: `docs/PHASE4_WEEK4_POLICY_LINTERS.md`
- Phase 4 Week 5: `docs/PHASE4_WEEK5_VERIFICATION.md`

---
*MAYOTIX OS Engineering Team*