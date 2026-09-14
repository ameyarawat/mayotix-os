# MAYOTIX OS Phase 4 Roadmap: Developer Tooling & Container Security

## Vision
Phase 4 elevates MAYOTIX OS from a secure, hardened desktop platform to a production-ready, secure development workstation. This phase focuses on isolation, integrity, and compliance across development workflows, emphasizing rootless containers, cryptographic attestation, reproducible development environments, and automated policy verification.

---

## 5-Week Milestone Breakdown

### Week 1: Hardened Rootless Container Engine
- **Focus**: Zero-root execution for container runtimes.
- **Deliverables**:
  - Podman & Buildah configuration for unprivileged user namespaces.
  - SubUID and SubGID mapping automation (`/etc/subuid`, `/etc/subgid`).
  - Strict seccomp filters for rootless container execution.
  - Registry restrictions via `/etc/containers/registries.conf` (disallow unencrypted HTTP, restrict to signed registries).
  - Dedicated SELinux policy module (`mayotix_container.te`) confining the rootless container domain.
  - System-level hardening script (`scripts/configure-container-hardening.sh`).

### Week 2: Container Image Integrity & Attestation
- **Focus**: Cryptographic verification of container supply chain.
- **Deliverables**:
  - Native integration with Cosign for image signature verification.
  - Policy enforcement via `/etc/containers/policy.json` rejecting unsigned/untrusted images.
  - Automated local image scanning via Trivy for CVE identification.
  - Build pipeline gating scripts blocking vulnerable base layers.

### Week 3: Isolated Ephemeral Dev Environments
- **Focus**: Workstation immutability preserved via disposable tooling containers.
- **Deliverables**:
  - Hardened Distrobox / Toolbx integrations with restricted host filesystem mounts.
  - Granular `/dev` and `/tmp` passthrough configurations.
  - Zero-remanence ephemeral development workspace recipes.
  - Audit logging for dev container lifecycle events.

### Week 4: Security-Focused Local CI/CD & Policy Linters
- **Focus**: Pre-commit policy verification and static analysis.
- **Deliverables**:
  - Git pre-commit security hooks (secret detection, ShellCheck, format checks).
  - Custom SELinux policy linters and compilation verification.
  - Containerfile/Dockerfile static analysis integrating `hadolint`.
  - Local security test suite for Phase 4 compliance validation.

### Week 5: Phase 4 ISO Build & End-to-End Verification
- **Focus**: Packaging, automated testing, and distribution.
- **Deliverables**:
  - Unified build script (`scripts/build-iso-phase4.sh`) generating `mayotix-os-4.0-alpha-x86_64.iso`.
  - Comprehensive Phase 4 Security Audit script (`scripts/conduct-security-audit-phase4.sh`) targeting 100/100 score.
  - Release documentation: `docs/PHASE4_RELEASE_NOTES.md` and `docs/PHASE4_WEEK5_VERIFICATION.md`.
  - CI/CD workflow updates for Phase 4 validation.

---

## Acceptance Criteria
- 100% rootless container execution with no root daemon dependencies.
- Strict signature attestation enforced on container image pull/run.
- Complete isolation of dev environments with read-only host fallbacks.
- Automated security linting blocking commits/builds with known risks.
- Comprehensive security audit score exceeding ≥95/100.
