# MAYOTIX OS Phase 4 Week 2: Container Image Integrity & Attestation

## Overview
This document outlines the implementation of a secure container supply chain foundation for MAYOTIX OS. We enforce image integrity via cryptographic signatures and proactive vulnerability scanning to prevent the deployment of compromised or known-vulnerable software artifacts.

---

## Technical Implementation

### 1. Unified Container Signature Policy (`config/containers/policy.json`)
The container runtime (Podman/Buildah) uses `policy.json` to decide whether to trust an image based on its source transport and signature.

- **Strict Enforcement**:
  - The `default` policy for all transports is `reject` (implicit block).
  - Images from `docker.io`, `quay.io`, and `ghcr.io` *must* be signed by our trusted signature authority using `signedBy` with a provided public key.
- **Key Validation**:
  - The signature must be verifiable against `/etc/containers/keys/sigstore/public.key`.

### 2. Signature Verification Workflow (`scripts/verify-container-image.sh`)
This script acts as a wrapper around [Cosign](https://github.com/sigstore/cosign) and Podman to verify images prior to pull/run.

- **Function**: Validates if an image has a valid signature matching our public key.
- **Usage**:
  ```bash
  sudo ./scripts/verify-container-image.sh --image <image-name>
  ```
- **Exit Codes**:
  - Returns `0` if verified successfully.
  - Returns `1` and aborts if verification fails.

### 3. Automated Vulnerability Scanning (`scripts/scan-container-vulnerabilities.sh`)
Integrates [Trivy](https://github.com/aquasecurity/trivy) for CVE scanning.

- **Strict Thresholds**: Blocks any image containing `CRITICAL` or `HIGH` severity vulnerabilities.
- **Usage**:
  ```bash
  sudo ./scripts/scan-container-vulnerabilities.sh --image <image-name>
  ```
- **Exit Codes**:
  - Returns `0` if no `CRITICAL`/`HIGH` vulnerabilities are detected.
  - Returns `1` if known threats match the threshold.

### 4. CI/CD Pipeline Gating (`scripts/gate-container-build.sh`)
Unified gate ensuring both signature validation and scan compliance are met.

- **Pipeline Flow**:
  1. Signature verification → 2. Vulnerability scan.
- **Enforcement**: If *either* fails, the pipeline *must* fail and stop the deployment.

---

## Maintenance & Key Management

### Key Management (Sigstore)
- **Public Key Location**: `/etc/containers/keys/sigstore/public.key`
- **Signing Authority**: The MAYOTIX OS build server possesses the corresponding `private.key` (protected via HSM/KMS) to sign all official base images and internal applications.
- **Key Rotation**: Public keys should be rotated periodically. Ensure all systems are updated with the new public key before rotating the private signing key.

### Scanner Updates (Trivy)
- The Trivy scanner periodically updates its database. The CI/CD pipeline ensures the local database is updated before each scan by calling `trivy image --download-db-only`.

---

## Verification Procedures

1. **Verify Signature Policy**:
   Check if Podman honors the policy by pulling an unsigned test image:
   ```bash
   podman pull docker.io/library/unsigned-image:latest
   # Expected: Error (rejection by policy)
   ```

2. **Verify Vulnerability Gate**:
   Scan an intentionally vulnerable image:
   ```bash
   sudo ./scripts/scan-container-vulnerabilities.sh --image docker.io/library/alpine:3.10
   # Expected: Exit code 1 (blocking high-priority vulnerabilities)
   ```

3. **Verify Deployment Gate**:
   Execute the gate script across the complete pipeline:
   ```bash
   sudo ./scripts/gate-container-build.sh --image docker.io/library/alpine:latest
   # Expected: Success (if image is verified and safe)
   ```

---

*MAYOTIX OS Engineering Team*  
*Phase 4 Week 2 — September 2026*