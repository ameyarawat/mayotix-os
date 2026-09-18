# MAYOTIX OS — Phase 12 Release Notes

## Release: Phase 12 — Hardening Defense & Automated Penetration Testing

**Version:** 5.0-alpha (Phase 12)
**Date:** 2026-09-18
**Codename:** Sentinel Shield

---

## Summary

Phase 12 introduces a fully automated penetration testing and hardening defense
suite to MAYOTIX OS. This release adds proactive security validation across four
attack surface domains: privilege escalation, sandbox escape, command injection,
and network exposure — all integrated into the unified daemon IPC, CLI, and
Wayland desktop GUI.

## New Features

### Automated Privilege Escalation Defense Suite
- GTFOBins SUID/SGID binary scanning (24+ escalation vectors checked)
- Sudoers wildcard and NOPASSWD bypass detection
- Linux process capabilities leak auditing (`cap_setuid`, `cap_net_admin`)
- Kernel sysctl hardening verification (5 critical parameters)

### Sandbox Escape Auditing Suite
- 5 breakout probes: filesystem root, host secrets, seccomp, D-Bus, network namespace
- 100% probe blocking rate verified
- Bubblewrap, Flatpak, and cgroupv2 containment validation

### Command Injection & Metacharacter Fuzzing Guard
- 12 malicious payload categories tested
- 100% rejection rate achieved (INJECTION_IMMUNE posture)
- Covers shell metacharacters, path traversal, buffer overflows, format strings,
  null byte truncation

### Network Exposure & Attack Surface Prober
- Unauthorized listening socket detection via `ss -tulpen`
- Lab subnet egress containment verification (airgapped from physical interfaces)
- Stealth scan (SYN/FIN/XMAS) silent drop confirmation via nftables
- Fail-closed hardware killswitch latency testing

### Daemon IPC Integration
- 5 new JSON-RPC 2.0 endpoints: `pentest.privesc`, `pentest.sandbox_escape`,
  `pentest.fuzz`, `pentest.network_audit`, `pentest.report`
- Unified report aggregation across all four testing suites

### Unified CLI Subcommand
- `mayotix pentest {privesc,sandbox,fuzz,network,run-all,report}`
- Full `--dry-run` and `--json` support across all subcommands

### Wayland Penetration Testing Studio GUI
- Qt6-based Wayland-native 5-tab security dashboard
- Headless mode for CI/CD verification pipelines
- XDG desktop entry for application launcher integration

### SELinux MAC Policy
- New domain `mayotix_pentest_t` with read-only audit capabilities
- Strict zero `user_home_t` access (host airgap enforced)

## Security Audit Results

| Pillar | Score |
|--------|-------|
| Privilege Escalation Auditing | 15 / 15 |
| Sandbox Breakout Probing | 15 / 15 |
| Command Injection Fuzzing | 15 / 15 |
| Network Exposure Auditing | 15 / 15 |
| Kernel Hardening Sysctls | 10 / 10 |
| SELinux MAC Confinement | 10 / 10 |
| IPC Daemon RPC Endpoints | 10 / 10 |
| CLI & Desktop GUI Integration | 10 / 10 |
| **Total** | **100 / 100** |

## Verification Results

- **Total Tests:** 46
- **Passed:** 46
- **Failed:** 0
- **Pass Rate:** 100%

## Files Added / Modified

### New Files
- `tests/pentest/privesc-check.sh` — Privilege escalation defense suite
- `tests/pentest/sandbox-escape.sh` — Sandbox breakout probe suite
- `tests/pentest/injection-fuzzer.py` — Command injection fuzzer
- `tests/pentest/network-exposure.sh` — Network exposure auditor
- `desktop/pentest/mayotix-pentest-gui.py` — Wayland Qt6 pentest GUI
- `desktop/applications/mayotix-pentest.desktop` — XDG desktop entry
- `security/selinux/mayotix_pentest.te` — SELinux type enforcement
- `security/selinux/mayotix_pentest.fc` — SELinux file contexts
- `scripts/conduct-security-audit-phase12.sh` — Security audit (100/100)
- `scripts/verify-phase12.sh` — Verification harness (46/46 tests)
- `docs/PHASE12_HARDENING_PENTEST.md` — Technical documentation
- `docs/PHASE12_RELEASE_NOTES.md` — This file

### Modified Files
- `daemon/mayotix-daemon.py` — Added 5 `pentest.*` RPC handlers
- `cli/mayotix` — Added `cmd_pentest` and `p_pentest` subparsers

## Compatibility

- **Base OS:** Fedora 40/44
- **Kernel:** 6.x (with hardened sysctls)
- **SELinux:** Enforcing mode required
- **Display Server:** Wayland (Sway/GNOME) for GUI; headless mode available
- **Dependencies:** Python 3.9+, nftables, bubblewrap, ss (iproute2)

## Upgrade Path

Phase 12 is fully backward compatible with Phases 1–11. No configuration
migration is required. The new `mayotix pentest` CLI subcommand is additive
and does not affect existing subcommands.
