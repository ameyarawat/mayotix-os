# MAYOTIX OS Phase 5 Release Notes
## Version: 5.0-alpha
## Release Date: September 2026

MAYOTIX OS 5.0-alpha marks the successful completion of **Phase 5: Network Security, Encrypted Privacy & Anonymity Routing**.

Building upon the hardened base, Wayland desktop, application sandboxing, and rootless container virtualization of earlier releases, Phase 5 provides comprehensive protection against network eavesdropping, metadata surveillance, cleartext traffic leaks, and DNS tampering.

---

## 1. Key Subsystems Introduced in Phase 5

### Week 1: System-Wide Encrypted DNS (DNS-over-TLS)
- **Hardened `systemd-resolved` Configuration**: Deployed under `/etc/systemd/resolved.conf.d/mayotix-dot.conf`.
- **Strict TLS 1.3 Transport on Port 853**: Enforces `DNSOverTLS=yes`, rejecting fallback to plaintext port 53.
- **DNSSEC Validation**: Cryptographically validates authoritative signatures (`DNSSEC=allow-downgrade`).
- **SNI Pinned Privacy Resolvers**: Quad9, Mullvad, and Cloudflare resolvers pinned by IP and TLS hostname.
- **Protocol Lockdown**: Disabled vulnerable legacy protocols (`MulticastDNS=no`, `LLMNR=no`).

### Week 2: Kernel WireGuard VPN & Watchdog Service
- **In-Kernel Cryptographic Tunneling**: State-of-the-art Noise_IKpsk2 framework utilizing Curve25519, ChaCha20-Poly1305, and BLAKE2s.
- **Post-Quantum Resilient Layer**: Pre-shared symmetric keys (PSK) mixed into Noise protocol state.
- **Full Tunnel Routing**: Enforces cryptokey routing (`AllowedIPs = 0.0.0.0/0, ::/0`).
- **Automated CLI Manager (`manage-wireguard`)**: Handles 0600 key generation, connection lifecycle, and interface setup.
- **Persistent Connection Watchdog (`mayotix-wg-watchdog.service/timer`)**: Periodically inspects handshake latency and automatically reconnects stale tunnels.

### Week 3: Fail-Closed `nftables` Network Kill-Switch
- **Atomic Packet Filtering**: Implemented via `config/network/nftables/mayotix-killswitch.nft`.
- **Default DROP Policy**: Fail-closed stance across `INPUT`, `FORWARD`, and `OUTPUT` hooks.
- **Egress Leak Prevention**: Drops all plaintext traffic traversing physical network interfaces (`enp*`, `wlan*`) whenever `wg0` is inactive.
- **Strict Protocol Whitelisting**: Allows only loopback (`lo`), local DHCP negotiation (UDP 67/68), encrypted DoT (port 853), and WireGuard UDP (port 51820).
- **Early-Boot Service**: `mayotix-killswitch.service` enforces the kill-switch prior to network initialization (`Before=network-pre.target`).

### Week 4: Optional Tor Isolation Proxy & Onion Routing
- **Hardened Tor Daemon (`torrc.mayotix`)**:
  - SOCKS5 proxy on `127.0.0.1:9050` with per-connection stream isolation (`IsolateDestAddr`, `IsolateDestPort`).
  - Transparent proxy (`TransPort 127.0.0.1:9040`) for zero-configuration application routing.
  - DNS proxy (`DNSPort 127.0.0.1:9053`) for `.onion` and anonymized domain queries.
  - Anti-forensic directives: `SafeLogging 1`, `AvoidDiskWrites 1`, and `DisableDebuggerAttachment 1`.
- **Transparent `nftables` Redirection (`mayotix-tor-router.nft`)**: Safely captures designated application or namespace packets, redirecting TCP to port 9040 while dropping UDP/ICMP leakage.
- **CLI Utility (`manage-tor`)**: Provides circuit health inspection, NEWNYM identity rotation, and `route-app` namespace isolation.

### Week 5: Unified Audit, Verification & ISO Build
- **Unified Security Audit Script (`conduct-security-audit-phase5.sh`)**: Evaluates all 9 security categories with a maximum score of 100/100.
- **Reproducible ISO Generator (`build-iso-phase5.sh`)**: Produces `mayotix-os-5.0-alpha-x86_64.iso` with deterministic `SOURCE_DATE_EPOCH` injection.
- **Complete Verification Harness Suite**: Automated verification scripts for DNS, WireGuard, Kill-Switch, and Tor.

---

## 2. Security Architecture Summary

```
                      +------------------------------------------+
                      |         User Applications / GUI          |
                      +--------------------+---------------------+
                                           |
                    +----------------------+----------------------+
                    |                                             |
                    v (Standard Egress)                           v (Tor Isolated Sessions)
      +-----------------------------+              +------------------------------+
      |  systemd-resolved (DoT:853) |              | Tor SOCKS5 / TransPort:9040  |
      +--------------+--------------+              +--------------+---------------+
                     |                                            |
                     v                                            v
      +-----------------------------+              +------------------------------+
      | Kernel WireGuard (wg0)      |              | Onion Anonymity Network      |
      | - Curve25519 + ChaCha20     |              | - 3-hop circuit routing      |
      | - Noise_IKpsk2 Post-Quantum |              | - Stream isolation           |
      +--------------+--------------+              +--------------+---------------+
                     |                                            |
                     +---------------------+----------------------+
                                           |
                                           v
             +----------------------------------------------------------+
             |         nftables Fail-Closed Network Kill-Switch         |
             |  - Default DROP policy on all chains                     |
             |  - Unmarked plaintext egress on physical NICs blocked    |
             |  - Only WireGuard UDP/51820 & DoT/853 permitted to wire  |
             +-----------------------------+----------------------------+
                                           |
                                           v
                             Physical Network Interface
```

---

## 3. Getting Started

Refer to `docs/PHASE5_WEEK5_VERIFICATION.md` for complete testing and ISO build instructions.

```bash
# Verify Phase 5 compliance
sudo ./scripts/conduct-security-audit-phase5.sh

# Build the Phase 5 bootable ISO
sudo ./scripts/build-iso-phase5.sh --reproducible
```

---
*MAYOTIX OS Engineering Team — September 2026*
