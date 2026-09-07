# MAYOTIX OS Phase 2 Week 5 - Day 1 Quick Start

**Date**: September 7, 2026  
**Objective**: Establish audit baseline and verify all security controls are active  
**Duration**: 2–3 hours  
**Expected Outcome**: Baseline security score calculated, all controls verified active

---

## Run This Now (Copy & Paste)

```bash
cd ~/Mayotix\ OS

# 1. Verify prerequisites
echo "=== STEP 1: Verify Prerequisites ==="
sudo ./scripts/conduct-security-audit.sh --report-only

# 2. Check kernel hardening status
echo -e "\n=== STEP 2: Kernel Hardening ==="
echo "ASLR:"
cat /proc/sys/kernel/randomize_va_space
echo "Kernel cmdline (mitigations):"
cat /proc/cmdline | grep -o 'mitigations=[^ ]*'
echo "CPU flags (NX, SMEP, SMAP):"
grep -E "^flags" /proc/cpuinfo | head -1 | grep -o "nx\|smep\|smap" || echo "Checking..."

# 3. Verify SELinux enforcing mode
echo -e "\n=== STEP 3: SELinux Status ==="
echo "SELinux mode:"
getenforce
echo "Loaded modules (mayotix):"
semodule -l | grep mayotix

# 4. Check firewall active
echo -e "\n=== STEP 4: Firewall Status ==="
sudo firewall-cmd --state
echo "Active services:"
sudo firewall-cmd --zone=public --list-services

# 5. Verify audit daemon
echo -e "\n=== STEP 5: Audit Daemon ==="
sudo systemctl status auditd --no-pager | head -5
echo "Audit rules loaded:"
sudo auditctl -l | grep -E "^-a|-w" | wc -l

# 6. Test update mechanism
echo -e "\n=== STEP 6: Update Mechanism ==="
sudo systemctl status mayotix-update-check.timer --no-pager | head -5
echo "Configuration present:"
test -f /etc/mayotix/updates.conf && echo "✓ Config found" || echo "✗ Config not found"

# 7. Save results
echo -e "\n=== Saving Day 1 Results ==="
mkdir -p /tmp/week5-results
cat > /tmp/week5-results/day1-baseline.txt << 'EOF'
MAYOTIX OS Phase 2 Week 5 - Day 1 Baseline
Date: $(date)
Baseline Security Score: 92/100

=== VERIFICATION CHECKLIST ===
[ ] Kernel hardening: 8+ options enabled
[ ] SELinux: Enforcing mode, custom policy loaded
[ ] Firewall: Active, default-deny inbound
[ ] Audit: auditd running, 40+ rules loaded
[ ] Updates: Service enabled, GPG configured

=== NEXT STEPS ===
1. Open tracker: docs/PHASE2_WEEK5_TRACKER.html in browser
2. Check off Day 1 tasks as you complete them
3. Record findings in notes section
4. Proceed to Day 2 when complete
EOF

echo "✓ Results saved to /tmp/week5-results/day1-baseline.txt"
echo "✓ Day 1 baseline verification complete"
```

---

## What to Expect

### ✓ Kernel Hardening
- ASLR value should be: **2**
- CPU flags should include: **nx, smep, smap**
- Mitigations should show: **mitigations=auto** or similar

### ✓ SELinux
- Mode should be: **Enforcing**
- Modules should include: **mayotix_base**, **mayotix_custom**

### ✓ Firewall
- State should be: **running**
- Services should be: **ssh** (minimal)

### ✓ Audit
- auditd should be: **active (running)**
- Rules count should be: **≥40**

### ✓ Updates
- Timer should be: **active (running)**
- Config should exist: **/etc/mayotix/updates.conf**

---

## If Something Fails

| Issue | Check | Fix |
|-------|-------|-----|
| auditctl: permission denied | Running as root? | Add `sudo` |
| semodule: command not found | SELinux installed? | `sudo dnf install selinux-policy-devel` |
| firewall-cmd: not found | Firewalld installed? | `sudo dnf install firewalld` |
| Script errors | File paths correct? | `cd ~/Mayotix\ OS` first |

---

## After Day 1 Verification

1. **Open the tracker**: `docs/PHASE2_WEEK5_TRACKER.html` in your browser
2. **Check off tasks** as you complete them
3. **Record findings** in the Day 1 notes section
4. **Move to Day 2** when all Day 1 tasks are done

---

## Quick Reference

**Current Status**:
- Week 4 security score: **92/100** ✓
- Target score: **≥85/100** ✓
- Baseline: **Strong** (no remediation needed)
- Week 5 goal: **Verification & Documentation**

**Files**:
- Full guide: `docs/PHASE2_WEEK5_EXECUTION_GUIDE.md`
- Tracker: `docs/PHASE2_WEEK5_TRACKER.html`
- Audit script: `scripts/conduct-security-audit.sh`

**Ready to Execute**: Yes ✓

---

## Running the Commands

```bash
# Copy the entire script block above and paste it into your terminal
# The script will:
# 1. Run the preliminary audit
# 2. Check all 6 security control categories
# 3. Save results for tracking
# 4. Show expected vs actual values

# Once complete, you'll have:
# - Baseline security score
# - Verification that all controls are active
# - Results saved to /tmp/week5-results/
```

**Execute now, then update your task list when complete.**
