# MAYOTIX OS Phase 2 Week 5: Execution Guide

**Status**: Ready for Linux Execution  
**Date**: September 7, 2026  
**Target**: Security Score ≥85/100 (Current: 92/100)  
**Deadline**: September 21, 2026  
**Total Duration**: 13–16 hours

---

## Quick Start

You are about to execute a comprehensive 5-day security verification of MAYOTIX OS Phase 2. The goal is to validate all security controls are functioning correctly and generate a final audit report.

### Prerequisites

**System Requirements**:
- Linux distribution (Fedora, Ubuntu, or compatible)
- Root access (sudo)
- 4GB RAM minimum
- 20GB free disk space (for ISO builds)
- Network access

**Required Tools**:
```bash
systemctl, auditctl, firewall-cmd, getenforce, resolvectl, sha256sum, git
```

**Verify your environment**:
```bash
# Run this first to check all tools are available
for tool in systemctl auditctl firewall-cmd getenforce resolvectl sha256sum; do
  command -v $tool &>/dev/null && echo "✓ $tool" || echo "✗ $tool MISSING"
done
```

---

## Execution Timeline

| Day | Task | Duration | Status | Completion Date |
|-----|------|----------|--------|-----------------|
| 1 | Security Audit Setup & Baseline | 2–3h | Planned | — |
| 2 | Service Hardening Verification | 2–3h | Planned | — |
| 3 | Firewall & Audit Rule Verification | 2–3h | Planned | — |
| 4 | Update Mechanism & Reproducibility | 3–4h | Planned | — |
| 5 | Full Security Suite & Report | 2–3h | Planned | — |
| **Total** | **Security Verification** | **13–16h** | **Planned** | **Sep 21** |

---

## Day 1: Security Audit Setup & Baseline (2–3 hours)

### Objective
Establish audit baseline and verify all security controls are active.

### Tasks

#### 1. Verify Prerequisites
```bash
cd ~/Mayotix\ OS
sudo ./scripts/conduct-security-audit.sh --report-only
```

**Expected**: Audit framework runs, baseline score calculated.

#### 2. Check Kernel Hardening Status
```bash
# ASLR (Address Space Layout Randomization)
cat /proc/sys/kernel/randomize_va_space
# Expected: 2

# CPU Mitigations
cat /proc/cmdline | grep -o 'mitigations=[^ ]*'
# Expected: mitigations=auto or similar

# Hardware features (NX, SMEP, SMAP)
grep -E "^flags" /proc/cpuinfo | head -1
# Expected: contains nx, smep, smap
```

#### 3. Verify SELinux Enforcing Mode
```bash
# Check enforcement status
getenforce
# Expected: Enforcing

# List loaded modules
semodule -l | grep mayotix
# Expected: mayotix_base, mayotix_custom policies listed

# Check for unconfined users
seinfo -u | grep unconfined
# Expected: minimal unconfined contexts
```

#### 4. Check Firewall Active
```bash
# Firewall status
sudo firewall-cmd --state
# Expected: running

# List active zones and rules
sudo firewall-cmd --zone=public --list-all
# Expected: default-deny, SSH open
```

#### 5. Verify Audit Daemon
```bash
# Service status
sudo systemctl status auditd
# Expected: active (running)

# Rule count
sudo auditctl -l | wc -l
# Expected: 40+ rules loaded
```

#### 6. Test Update Mechanism
```bash
# Timer status
sudo systemctl status mayotix-update-check.timer
# Expected: active (running)

# Configuration
cat /etc/mayotix/updates.conf
# Expected: GPG configured, check interval set
```

### Expected Results ✓
- [ ] Kernel hardening: 8+ options enabled
- [ ] SELinux: Enforcing mode, custom policy loaded
- [ ] Firewall: Active, default-deny inbound
- [ ] Audit: auditd running, 40+ rules loaded
- [ ] Updates: Service enabled, GPG configured

### Recording Day 1 Results

After completing all tasks, record findings:

```bash
# Save Day 1 baseline
cat > /tmp/day1-results.txt << 'EOF'
Date: $(date)
ASLR: $(cat /proc/sys/kernel/randomize_va_space)
SELinux: $(getenforce)
Firewall State: $(sudo firewall-cmd --state)
Audit Rules: $(sudo auditctl -l | wc -l)
Update Timer: $(sudo systemctl is-active mayotix-update-check.timer)
EOF

echo "Day 1 results saved to /tmp/day1-results.txt"
```

---

## Day 2: Service Hardening Verification (2–3 hours)

### Objective
Validate systemd service security hardening is complete.

### Tasks

#### 1. Run Systemd Security Analyzer
```bash
# Overall system security score
sudo systemd-analyze security
# Expected: High overall security score (75%+)
```

#### 2. Check Individual Service Scores
```bash
# MAYOTIX services
sudo systemd-analyze security mayotix-security
sudo systemd-analyze security mayotix-firewall
sudo systemd-analyze security mayotix-audit

# SSH service
sudo systemd-analyze security sshd
# Expected: All services ≥60% security score
```

#### 3. Verify Service Hardening Directives
```bash
# Check mayotix-security service
sudo systemctl cat mayotix-security | grep -E "^[A-Z].*="

# Check SSH hardening
sudo systemctl cat sshd | grep -E "PrivateTmp|NoNewPrivileges|ProtectSystem|ReadOnlyPaths"
# Expected: ≥20 hardening directives per service
```

#### 4. Check for Unconfined Processes
```bash
# List unconfined processes
ps -eZ | grep unconfined

# Count unconfined processes
ps -eZ | grep unconfined | wc -l
# Expected: 0 (none) or minimal count
```

### Expected Results ✓
- [ ] All core services: security score ≥60%
- [ ] Hardening directives: ≥20 per service
- [ ] No unconfined processes running
- [ ] SSH: PrivateTmp enabled, NoNewPrivileges active

### Recording Day 2 Results

```bash
# Save Day 2 service scores
sudo systemd-analyze security > /tmp/day2-systemd-security.txt
sudo systemd-analyze security mayotix-security >> /tmp/day2-service-scores.txt
sudo systemd-analyze security sshd >> /tmp/day2-service-scores.txt

echo "Day 2 service analysis saved"
```

---

## Day 3: Firewall & Audit Rule Verification (2–3 hours)

### Objective
Validate firewall rules and audit logging completeness.

### Tasks

#### 1. Verify Firewall Rules
```bash
# Open ports
sudo firewall-cmd --zone=public --list-ports

# Open services
sudo firewall-cmd --zone=public --list-services
# Expected: SSH only, or minimal services

# Inspect nftables rules
sudo nft list ruleset | head -50
```

#### 2. Test Connection Rules
```bash
# Query SSH service rule
sudo firewall-cmd --zone=public --query-service=ssh
# Expected: yes (SSH is allowed)

# Query SSH port
sudo firewall-cmd --zone=public --query-port=22/tcp
# Expected: yes (port 22/tcp is allowed)
```

#### 3. Verify Audit Rules
```bash
# Count audit rules
sudo auditctl -l | grep -E "^-a|-w" | wc -l
# Expected: ≥40 rules

# Show all audit rules
sudo auditctl -l
```

#### 4. Test Audit Logging
```bash
# Search for recent audit events
sudo ausearch -m INTEGRITY_DATA | head -5

# Check audit log size
ls -lh /var/log/audit/audit.log
```

#### 5. Verify Log Rotation
```bash
# Check logrotate config
cat /etc/logrotate.d/auditd

# List audit logs
ls -lh /var/log/audit/
# Expected: Multiple rotated log files
```

#### 6. Test DoH/DNSSEC
```bash
# Check DNS configuration
resolvectl status

# Show resolved.conf
grep -E "DoH|DNSSEC" /etc/systemd/resolved.conf
# Expected: DoH and DNSSEC configured
```

### Expected Results ✓
- [ ] Firewall: Default-deny, SSH only open service
- [ ] Audit rules: ≥40 rules loaded and active
- [ ] Logs: Rotating, persistent, accessible
- [ ] DNS: DoH/DNSSEC configured and active

### Recording Day 3 Results

```bash
# Save firewall and audit rules
sudo firewall-cmd --zone=public --list-all > /tmp/day3-firewall-rules.txt
sudo auditctl -l > /tmp/day3-audit-rules.txt
sudo ausearch -m INTEGRITY_DATA | head -20 > /tmp/day3-audit-events.txt

echo "Day 3 firewall and audit verification saved"
```

---

## Day 4: Update Mechanism & Reproducibility Testing (3–4 hours)

### Objective
Verify atomic updates and reproducible builds are functioning.

### Tasks

#### 1. Verify Update Framework
```bash
# Check update timer
systemctl status mayotix-update-check.timer

# Check update service
systemctl status mayotix-update-check.service

# Review logs
cat /var/log/mayotix-update-check.log
```

#### 2. Test Dry-Run Update
```bash
# Run dry-run (no actual update)
sudo /usr/libexec/mayotix-update-check --dry-run --status
# Expected: Completes without errors
```

#### 3. Verify Rollback Capability
```bash
# Check rollback directory
ls -la /var/lib/mayotix/rollback/
# Expected: 3 previous versions available

# Check rollback tool
sudo /usr/libexec/mayotix-rollback --status
```

#### 4. Test Build Reproducibility
```bash
# Set reproducible build environment
export SOURCE_DATE_EPOCH=1694678400

# Build reproducible ISO
sudo ./scripts/build-iso-phase2.sh --reproducible
# Expected: ISO builds successfully
```

#### 5. Verify Checksums
```bash
# Verify checksum file
sha256sum -c build/*.sha256
# Expected: All OK

# Show checksum
cat build/*.sha256
```

#### 6. Compare ISOs for Reproducibility
```bash
# Run reproducibility verification
./scripts/verify-reproducible-builds.sh --verbose
# Expected: Identical checksums across builds
```

#### 7. Validate Build Manifest
```bash
# Show build manifest
cat build/BUILD_MANIFEST.json | jq '.' | head -30
# Expected: Complete component tracking, all hashes present
```

### Expected Results ✓
- [ ] Update timer: Scheduled for 3 AM daily
- [ ] Dry-run: Completes without errors
- [ ] Rollback: 3 previous versions available
- [ ] ISO: Reproducible across builds
- [ ] Checksums: All valid
- [ ] Manifest: Complete component tracking

### Recording Day 4 Results

```bash
# Save update and build results
systemctl status mayotix-update-check.timer > /tmp/day4-update-status.txt
sha256sum -c build/*.sha256 > /tmp/day4-checksums.txt 2>&1
cat build/BUILD_MANIFEST.json | jq '.' > /tmp/day4-manifest.json

echo "Day 4 update mechanism and reproducibility saved"
```

---

## Day 5: Comprehensive Security Test & Report (2–3 hours)

### Objective
Run full security suite and generate final audit report.

### Tasks

#### 1. Run Comprehensive Security Tests
```bash
# Full security test suite
sudo ./scripts/test-security-phase2.sh --verbose
# Expected: All tests PASS
```

#### 2. Generate Full Security Audit Report
```bash
# Generate audit report (creates build/SECURITY_AUDIT_REPORT.txt)
sudo ./scripts/conduct-security-audit.sh
# Expected: Report generated with final score
```

#### 3. Review Audit Findings
```bash
# Display audit report
cat build/SECURITY_AUDIT_REPORT.txt
# Record the FINAL SECURITY SCORE
```

#### 4. Execute Full Verification Sequence
```bash
# Run all verification checks in sequence
echo "=== KERNEL HARDENING ===" && \
  cat /proc/sys/kernel/randomize_va_space && \
  dmesg | grep "stack-protector" && \
echo "=== SELinux ===" && \
  getenforce && \
echo "=== FIREWALL ===" && \
  sudo firewall-cmd --state && \
echo "=== AUDIT ===" && \
  sudo auditctl -l | wc -l && \
echo "=== UPDATES ===" && \
  sudo systemctl is-active mayotix-update-check.timer && \
echo "=== REPRODUCIBLE ===" && \
  test -f build/BUILD_MANIFEST.json && echo "PASS" || echo "FAIL"
```

#### 5. Extract Final Security Score
```bash
# Extract and display final score
grep -A 8 "TOTAL SCORE" build/SECURITY_AUDIT_REPORT.txt

# Save final score to file
grep "TOTAL SCORE" build/SECURITY_AUDIT_REPORT.txt > /tmp/final-score.txt
cat /tmp/final-score.txt
```

### Expected Results ✓
- [ ] All security tests: PASS
- [ ] Security score: ≥85/100 (expected: 92/100)
- [ ] No critical vulnerabilities
- [ ] All components functioning
- [ ] Ready for Phase 2 release

### Recording Day 5 Results

```bash
# Copy final report
cp build/SECURITY_AUDIT_REPORT.txt /tmp/day5-final-audit-report.txt

# Extract score
grep "TOTAL SCORE" /tmp/day5-final-audit-report.txt > /tmp/final-security-score.txt

echo "=== FINAL SECURITY AUDIT COMPLETE ==="
cat /tmp/final-security-score.txt
```

---

## Go/No-Go Decision Matrix

### GO Criteria (Proceed to Week 6) ✓

All of the following must be true:
- [ ] Security score: ≥85/100
- [ ] All acceptance criteria: Met (8/8)
- [ ] All tests: Passing
- [ ] No critical vulnerabilities
- [ ] Build reproducibility: Verified
- [ ] Update mechanism: Functional
- [ ] Audit report: Generated and reviewed

### NO-GO Criteria (Continue Week 5) ✗

If any of these are true, address gaps and re-test:
- [ ] Security score: <85/100
- [ ] Any critical vulnerabilities found
- [ ] Tests failing
- [ ] Acceptance criteria not met
- [ ] Build reproducibility issues
- [ ] Update mechanism problems
- [ ] Audit report generation failed

---

## Security Audit Score Breakdown

| Category | Points | Status |
|----------|--------|--------|
| **Kernel Hardening** | 15 | — |
| **SELinux Enforcing** | 20 | — |
| **Systemd Security** | 15 | — |
| **Firewall Security** | 15 | — |
| **Audit Logging** | 10 | — |
| **Update Mechanism** | 5 | — |
| **Reproducible Builds** | 3 | — |
| **Security Controls** | 2 | — |
| **TOTAL SCORE** | **100** | — |

### Scoring Notes

- **Current Baseline** (Week 4): 92/100
- **Target Score** (Week 5): ≥85/100
- **Expected Result**: 92/100 (maintained from Week 4)
- **Pass Threshold**: 85/100 (for go/no-go decision)

---

## If Score < 85/100: Remediation Path

If your final score is below 85/100:

1. **Review the audit report** — Identify which categories have gaps
2. **Review recommendations** — Audit report will suggest fixes
3. **Address failing controls** — Follow recommendations to strengthen security
4. **Re-run specific tests** — Test only the affected categories
5. **Re-generate audit report** — Confirm score improvement
6. **Repeat until score ≥85/100** — May take additional days

### Common Issues & Fixes

| Issue | Fix |
|-------|-----|
| Low kernel hardening score | Check bootloader parameters, verify CPU supports features |
| SELinux not enforcing | Set `setenforce 1`, verify policy is loaded |
| Audit rules not loaded | Restart auditd: `sudo systemctl restart auditd` |
| Firewall not default-deny | Reconfigure with `sudo firewall-cmd --zone=public --set-target=DROP` |
| Update mechanism not active | Check timer: `sudo systemctl restart mayotix-update-check.timer` |
| Build not reproducible | Verify SOURCE_DATE_EPOCH is set, check for timestamps in build |

---

## If Score ≥ 85/100: Proceed to Week 6

1. **Document test results** — Save all Day 1-5 findings
2. **Review audit report with team** — Presentation-ready
3. **Approve go/no-go decision** — ✓ GO for Phase 2 release
4. **Proceed to Week 6** — Release & Documentation phase

### Week 6 Deliverables

Upon go decision, Week 6 will include:
- Phase 2 ISO finalization
- Release notes and documentation
- CI/CD pipeline updates
- Go/no-go decision for Phase 3

### Phase 2 Release Package

Your final deliverable will include:
- Bootable Phase 2 ISO image
- Checksums and signatures
- Build manifest and reproducibility proof
- Complete security audit report
- Installation and deployment guide
- Rollback and recovery procedures

---

## Useful Commands Reference

### Quick Status Check
```bash
# One-liner to check all systems
echo "Kernel: $(cat /proc/sys/kernel/randomize_va_space)" && \
echo "SELinux: $(getenforce)" && \
echo "Firewall: $(sudo firewall-cmd --state)" && \
echo "Audit Rules: $(sudo auditctl -l | wc -l)" && \
echo "Update Timer: $(sudo systemctl is-active mayotix-update-check.timer)"
```

### View All Audit Rules
```bash
sudo auditctl -l
```

### View Firewall Rules (nftables)
```bash
sudo nft list ruleset
```

### Check Service Security Scores
```bash
for svc in mayotix-security mayotix-firewall mayotix-audit sshd; do
  echo "=== $svc ===" 
  sudo systemd-analyze security "$svc" 2>/dev/null | head -5
done
```

### Generate Full Report Stack
```bash
# Run all verification in one go
sudo ./scripts/test-security-phase2.sh --verbose && \
sudo ./scripts/conduct-security-audit.sh && \
echo "✓ All tests and audits complete"
```

---

## Timeline & Checkpoints

**Week 5 Execution Timeline**:
- **Sept 7–9** (Days 1–2): Baseline & Service Verification
- **Sept 10–12** (Days 3–4): Firewall & Update Mechanism
- **Sept 13–14** (Day 5): Full Suite & Final Report
- **Sept 15–21**: Address any gaps or finalize go/no-go

**Checkpoint dates**:
- [ ] Sept 9: Day 1–2 baseline established
- [ ] Sept 12: Days 3–4 verification complete
- [ ] Sept 14: Day 5 final report & score decision
- [ ] Sept 21: Week 5 complete (go/no-go finalized)

---

## Support & Documentation

### Key Files
- Execution guide: `docs/PHASE2_WEEK5_EXECUTION_GUIDE.md` (this file)
- Original plan: `docs/PHASE2_WEEK5_SECURITY_VERIFICATION.md`
- Dashboard: `docs/PHASE2_WEEK5_DASHBOARD.html`
- Status: `docs/PHASE2_STATUS.md`

### Scripts Location
- Security audit: `scripts/conduct-security-audit.sh`
- Security tests: `scripts/test-security-phase2.sh`
- Reproducibility check: `scripts/verify-reproducible-builds.sh`
- ISO builder: `scripts/build-iso-phase2.sh`

### Output Locations
- Audit report: `build/SECURITY_AUDIT_REPORT.txt`
- Build manifest: `build/BUILD_MANIFEST.json`
- ISO image: `build/mayotix-os-2.0-alpha-x86_64.iso`
- Checksums: `build/mayotix-os-2.0-alpha-x86_64.iso.sha256`

---

## Next Steps

1. **Print or bookmark this guide** — Reference it throughout Week 5
2. **Verify your environment** — Run the prerequisite check
3. **Start Day 1** — Begin with the baseline audit
4. **Record findings** — Keep notes as you progress
5. **Track progress** — Update the dashboard as tasks complete

---

**Status**: Execution Guide Ready  
**Last Updated**: September 7, 2026  
**Ready to Execute**: Yes (requires Linux system with root access)  
**Estimated Completion**: September 21, 2026
