# MAYOTIX OS Phase 2 Week 1: Kernel & SELinux Foundation

**Status**: In Progress  
**Week**: 1/6  
**Date**: September 7, 2026  
**Focus**: Custom kernel compilation and SELinux policy refinement

---

## Objectives

1. **Kernel Compilation** — Build Fedora kernel with MAYOTIX hardening options
2. **Verify Hardening** — Confirm ASLR, SMEP, SMAP, DEP/NX, strict RWX in running kernel
3. **SELinux Policy** — Finalize and compile custom MAYOTIX SELinux policy
4. **Policy Testing** — Validate policy in permissive mode, then enforcing
5. **Documentation** — Record hardening options and SELinux rules

---

## Current Status

### ✅ Completed (Phase 1)
- Base ISO with Phase 1 bootable system
- SELinux infrastructure and tools installed
- Kernel configuration template created (`kernel/config`)
- SELinux policy files created (`.te`, `.fc`, `.if`)
- SELinux compilation script ready (`scripts/compile-selinux.sh`)

### ⏳ In Progress (Week 1)
- [ ] Test Phase 1 ISO build on Linux system
- [ ] Validate Phase 1 bootability (UEFI + BIOS)
- [ ] Review kernel hardening options
- [ ] Refine SELinux policy based on audit logs
- [ ] Create Phase 2 build script

---

## Week 1 Deliverables

### 1. Kernel Hardening Validation

**Objective**: Verify that hardening options are correctly enabled in the running kernel.

**Current Kernel Config** (`kernel/config`):
```
CONFIG_RANDOMIZE_BASE=y              # ASLR: kernel base address randomization
CONFIG_RANDOMIZE_MEMORY=y            # ASLR: memory layout randomization
CONFIG_STRICT_KERNEL_RWX=y           # Strict RWX: enforce read/write/execute separation
CONFIG_STRICT_MODULE_RWX=y           # Strict RWX for kernel modules
CONFIG_CC_STACKPROTECTOR_STRONG=y    # Stack canaries
CONFIG_CFI_CLANG=y                   # Control Flow Guard
CONFIG_SHADOW_CALL_STACK=y           # Return-Oriented Programming (ROP) protection
CONFIG_HARDENED_USERCOPY=y           # Usercopy hardening
CONFIG_AUDIT=y                       # Audit daemon
CONFIG_SECURITY_SELINUX=y            # SELinux mandatory
```

**Validation Script** (to run on Phase 1 ISO):
```bash
#!/bin/bash
# Verify kernel hardening options

echo "=== Kernel Hardening Verification ==="

# ASLR check
echo "ASLR Status:"
cat /proc/sys/kernel/randomize_va_space

# Stack canaries
echo "Stack Protection:"
grep -o CONFIG_STACKPROTECTOR_STRONG /proc/config.gz | gunzip

# NX bit (DEP)
echo "NX Bit Support:"
grep nx /proc/cpuinfo | head -1

# SMEP/SMAP
echo "SMEP/SMAP:"
grep -E "smep|smap" /proc/cpuinfo | head -2

# SELinux status
echo "SELinux Status:"
getenforce

# Strict RWX
echo "Strict RWX:"
dmesg | grep -i "strict" | head -3
```

**Success Criteria**:
- [ ] ASLR randomization enabled (value: 2)
- [ ] Stack protection enabled
- [ ] NX bit supported by CPU
- [ ] SMEP and SMAP present in CPU flags
- [ ] SELinux running in enforcing mode
- [ ] Strict RWX enforcement active

---

### 2. SELinux Policy Refinement

**Current Policy Status** (`security/selinux/mayotix.te`):
- 107 lines of policy rules
- Covers: mayotix domain, execution, file access, processes, capabilities
- Includes: audit logging, network sockets, device access

**Next Steps**:
1. Review Phase 1 audit logs for policy violations
2. Refine `.te` rules based on actual service behavior
3. Recompile and test in permissive mode
4. Enable enforcing mode

**Key Policy Rules**:
```
# Domain transition
type_transition unconfined_t mayotix_exec_t:process mayotix_t;
type_transition init_t mayotix_exec_t:process mayotix_t;

# File access
allow mayotix_t mayotix_var_lib_t:file { create read write open unlink };
allow mayotix_t mayotix_log_t:file { create write open append };

# Capabilities
allow mayotix_t self:capability { sys_admin sys_tty_config sys_resource };

# Audit logging
allow mayotix_t auditd_t:fd { use };
```

**Test Commands**:
```bash
# Compile policy
./scripts/compile-selinux.sh mayotix

# Load in permissive mode (if not in enforcing)
sudo setenforce 0
sudo ./scripts/compile-selinux.sh mayotix --install

# Monitor violations
sudo ausearch -m avc | audit2allow -a

# Switch to enforcing
sudo setenforce 1
```

---

### 3. Hardening Options Analysis

**Required Kernel Options for Phase 2**:

| Option | Current | Purpose | Priority |
|--------|---------|---------|----------|
| `CONFIG_RANDOMIZE_BASE` | y | Kernel ASLR | Critical |
| `CONFIG_RANDOMIZE_MEMORY` | y | Memory layout ASLR | Critical |
| `CONFIG_STRICT_KERNEL_RWX` | y | Strict W^X enforcement | Critical |
| `CONFIG_CC_STACKPROTECTOR_STRONG` | y | Stack canaries | Critical |
| `CONFIG_CFI_CLANG` | y | Control Flow Integrity | High |
| `CONFIG_SHADOW_CALL_STACK` | y | ROP protection | High |
| `CONFIG_HARDENED_USERCOPY` | y | Usercopy hardening | High |
| `CONFIG_HAVE_EBPF_JIT` | y | eBPF JIT support | Medium |
| `CONFIG_BPF_JIT` | y | Enable eBPF JIT | Medium |
| `CONFIG_KEXEC` | n | Disable kexec | High |
| `CONFIG_DEBUG_FS` | n | Disable debugfs | High |

**Additional Hardening Considerations**:
- Disable ptrace scope for now (debugging support)
- Enable audit logging for security events
- Configure SELinux to enforcing mode
- Validate module signing is enabled

---

### 4. Phase 1 ISO Testing Checklist

Before proceeding with Phase 2 kernel compilation:

- [ ] **Build Phase 1 ISO** on Linux system with dependencies
  ```bash
  cd mayotix-os
  sudo apt-get install dracut grub-common grub-efi-amd64 xorriso mtools dosfstools
  ./scripts/build-iso-phase1.sh --reproducible
  ```

- [ ] **Run Phase 1 acceptance tests**
  ```bash
  ./scripts/test-phase1.sh
  ```

- [ ] **Test bootability in QEMU**
  ```bash
  ./scripts/test-boot.sh build/mayotix-os-1.0-alpha-x86_64.iso --both
  ```

- [ ] **Verify checksums**
  ```bash
  sha256sum -c build/mayotix-os-1.0-alpha-x86_64.iso.sha256
  ```

- [ ] **Boot into Phase 1 system, verify kernel hardening** using validation script above

---

## Implementation Plan

### Phase 1: Immediate (This Week)
1. Execute Phase 1 ISO build on Linux system
2. Validate Phase 1 bootability and hardening
3. Collect audit logs from Phase 1 boot
4. Review SELinux violations from logs

### Phase 2: Refinement (Days 3-4)
1. Update SELinux policy based on audit logs
2. Recompile and test in permissive mode
3. Enable enforcing mode and validate boot

### Phase 3: Documentation (Days 5-7)
1. Document kernel hardening options
2. Create Phase 2 build script (`build-iso-phase2.sh`)
3. Update CI/CD pipelines for Phase 2 builds
4. Begin Week 2 work (systemd hardening)

---

## Key Files & Scripts

| File | Purpose | Status |
|------|---------|--------|
| `kernel/config` | Kernel configuration | ✓ Ready |
| `security/selinux/mayotix.te` | SELinux type enforcement | ✓ Ready |
| `security/selinux/mayotix.fc` | File contexts | ✓ Ready |
| `security/selinux/mayotix.if` | Policy interfaces | ✓ Ready |
| `scripts/compile-selinux.sh` | SELinux compiler | ✓ Production-ready |
| `scripts/build-iso-phase1.sh` | Phase 1 ISO builder | ✓ Production-ready |
| `scripts/test-phase1.sh` | Phase 1 validator | ✓ Production-ready |
| `scripts/security-audit.sh` | Security audit | ✓ Production-ready |

---

## Success Criteria for Week 1

- [ ] Phase 1 ISO boots successfully on Linux system
- [ ] All Phase 1 acceptance criteria tests pass
- [ ] Kernel hardening options verified in running system
- [ ] SELinux policy compiles without errors
- [ ] SELinux policy loads in permissive mode
- [ ] SELinux audit logs collected and reviewed
- [ ] Policy refined based on audit logs
- [ ] SELinux enabled in enforcing mode
- [ ] System boots successfully in enforcing mode
- [ ] Phase 2 build script created

---

## Next Week (Week 2)

**Focus**: Systemd Service Hardening
- Apply 27+ hardening directives per service
- Create base hardened service template
- Harden core services (network, audit, udev)
- Harden GUI services (GDM, compositor)
- Validate with systemd-analyze security

---

## References

- **MAYOTIX Architecture**: `MAYOTIX_ARCHITECTURE.md` (39KB, sections 3 & 14)
- **Build Instructions**: `BUILD.md`
- **Security Model**: `SECURITY.md`
- **Kernel Hardening**: https://kernsec.org/wiki/index.php/Kernel_Self_Protection_Project
- **SELinux Policies**: `security/selinux/` directory

---

**Last Updated**: September 7, 2026  
**Next Review**: September 14, 2026 (End of Week 1)
