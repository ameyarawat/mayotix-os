# Security Policy

## Reporting Security Vulnerabilities

**DO NOT** open a GitHub issue for security vulnerabilities.

Email security reports to: **security@mayotix.os**

### Reporting Process

1. **Email your report** to security@mayotix.os with:
   - Vulnerability description
   - Affected component(s)
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if you have one)

2. **What to include:**
   - Your name and contact info (optional, you may report anonymously)
   - CVSS score or severity assessment (if possible)
   - Timeline constraints (if any)

3. **What NOT to include:**
   - Publicly disclosed exploit code
   - Proof-of-concept against production systems
   - Customer data or PII

### Response Timeline

| Severity | Response | Fix | Disclosure |
|----------|----------|-----|-----------|
| Critical | 24 hours | 48 hours | 7 days |
| High | 48 hours | 7 days | 30 days |
| Medium | 1 week | 30 days | 90 days |
| Low | 2 weeks | 90 days | 180 days |

### Our Commitment

- We will acknowledge receipt of your report within 24 hours
- We will work with you to understand and fix the issue
- We will not publicly disclose the vulnerability without your consent (unless you have already disclosed it)
- We will credit you in security advisories (unless you prefer anonymity)
- We will provide security fixes as soon as possible

### Supported Versions

Only the latest stable release receives security updates.

```
MAYOTIX OS 1.0.x     — Active security support
MAYOTIX OS 0.x       — Not supported
```

### Security Advisories

Security advisories are published at: https://github.com/mayotix/mayotix-os/security/advisories

Subscribe to release notifications to be notified of security updates.

### Threat Model

See [MAYOTIX_ARCHITECTURE.md](MAYOTIX_ARCHITECTURE.md#14-security-threat-model) for MAYOTIX's threat model and security assumptions.

### PGP Key

For encrypted communications:

```
-----BEGIN PGP PUBLIC KEY BLOCK-----
[PGP key to be generated and placed here]
-----END PGP PUBLIC KEY BLOCK-----
```

---

## Security Updates

### Patch Releases

Patch releases (x.y.Z) contain only security fixes and critical bug fixes.

Example: 1.0.0 → 1.0.1 (security fix)

### Minor Releases

Minor releases (x.Y.z) may contain new features and security updates.

Example: 1.0.0 → 1.1.0 (new features + fixes)

### Major Releases

Major releases (X.y.z) represent significant changes or breaking changes.

Example: 1.0.0 → 2.0.0 (new architecture)

### Update Verification

All releases are signed with GPG. Verify before installation:

```bash
gpg --verify mayotix-os-1.0.0.iso.gpg mayotix-os-1.0.0.iso
```

### Known Limitations

MAYOTIX's security model assumes:

- User keeps their passphrase/password secret
- User keeps their device physically secure
- User applies security updates promptly
- User does not disable SELinux (except in recovery)
- User does not install untrusted software
- User has a recent CPU with trusted hardware (TPM)

MAYOTIX does NOT provide:

- Protection against quantum computing attacks (no cryptosystem does today)
- Protection against sophisticated hardware attacks (JTAG, microprobes)
- Perfect anonymity (use Tor separately if needed)
- Protection after device seizure and extended forensic analysis
- Protection against compromised firmware or bootloader

---

## Questions?

Contact: security@mayotix.os

---

**Last Updated:** 2026-09-06  
**MAYOTIX OS Security Team**
