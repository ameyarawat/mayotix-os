# MAYOTIX OS Phase 5 Week 2: Kernel WireGuard VPN Integration & Profile Management

## 1. Architectural Overview & Vision

Phase 5 Week 2 introduces kernel-native WireGuard Virtual Private Network (VPN) integration and profile management into MAYOTIX OS. Operating directly within kernel space via the Noise Protocol Framework, MAYOTIX OS achieves state-of-the-art cryptographic tunnel encapsulation, minimal latency overhead, strict multi-interface routing isolation, and total immunity from plaintext traffic leaks.

By pairing kernel WireGuard with Phase 5 Week 1's System-wide Encrypted DNS (DNS-over-TLS on port 853), MAYOTIX OS guarantees that all application network traffic—including DNS resolution—is authenticated, encrypted, and anchored to secure egress nodes.

```
+-----------------------------------------------------------------------------------+
|                                  MAYOTIX OS                                       |
|                                                                                   |
|  +-----------------------+                    +--------------------------------+  |
|  | User Applications     |                    | systemd-resolved               |  |
|  | (Firefox, Dev, Tools) |                    | (DNS-over-TLS Stub 127.0.0.53) |  |
|  +-----------+-----------+                    +---------------+----------------+  |
|              |                                                |                   |
|              +-----------------------+------------------------+                   |
|                                      | Encrypted Packets                          |
|                                      v                                            |
|  +-----------------------------------------------------------------------------+  |
|  |                     Kernel WireGuard Interface (wg0)                        |  |
|  |  - Cryptographic Cryptokey Routing (AllowedIPs = 0.0.0.0/0, ::/0)           |  |
|  |  - Curve25519 ECDH + ChaCha20-Poly1305 + BLAKE2s                           |  |
|  |  - Noise_IKpsk2 Symmetric Post-Quantum Overlay                             |  |
|  +-----------------------------------+-----------------------------------------+  |
|                                      |                                            |
|                                      | FwMark = 0x51820 (Encapsulated UDP/51820) |  |
|                                      v                                            |
|  +-----------------------------------------------------------------------------+  |
|  |                 nftables / iptables Kill-Switch Firewall                    |  |
|  |  - Rejects all un-marked egress traffic on physical interfaces              |  |
|  |  - Enforces persistent interface pinning to physical network card           |  |
|  +-----------------------------------+-----------------------------------------+  |
|                                      |                                            |
+--------------------------------------|--------------------------------------------+
                                       | Encrypted WireGuard Tunnel
                                       v
                        +------------------------------+
                        |  Remote VPN Gateway Node     |
                        |  (Quad9/Mullvad/Custom)      |
                        +------------------------------+
```

---

## 2. Cryptographic Protocol & Noise Framework Specification

MAYOTIX OS WireGuard implementation is based on the **Noise_IKpsk2** 1-RTT (One Round Trip Time) handshake protocol built into the Linux kernel module:

- **Key Exchange (DH)**: Curve25519 Elliptic-Curve Diffie-Hellman (ECDH) key agreement for mutual authentication and session key derivation.
- **Symmetric Encryption (AEAD)**: ChaCha20 cipher paired with Poly1305 Authenticated Encryption with Associated Data (AEAD) per RFC 7539.
- **Hashing**: BLAKE2s-256 for key derivation (HKDF) and cookie calculation.
- **Pre-Shared Key (PSK) Overlay**: Mixes a 256-bit symmetric key (`wg genpsk`) into the Noise protocol state to provide post-quantum resilience against future quantum decryption threats.
- **Cryptokey Routing**: In-kernel association of public keys directly with allowed IP addresses/subnets (`AllowedIPs`), preventing IP spoofing and illegitimate interface injections.

---

## 3. Configuration Framework & Profile Templates

MAYOTIX OS ships three standardized, hardened WireGuard profile templates located under `config/network/wireguard/`:

### 3.1 Standard Client Template (`wg0-client.conf.template`)
Designed for standard workstation VPN tunneling with DNS leak protection:
```ini
[Interface]
PrivateKey = {{CLIENT_PRIVATE_KEY}}
Address = {{CLIENT_IPV4_ADDRESS}}/32, {{CLIENT_IPV6_ADDRESS}}/128
DNS = 127.0.0.53
MTU = 1420

[Peer]
PublicKey = {{SERVER_PUBLIC_KEY}}
Endpoint = {{SERVER_ENDPOINT_IP}}:{{SERVER_ENDPOINT_PORT}}
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
```

### 3.2 Pre-Shared Key (PSK) Enhanced Template (`wg0-psk.conf.template`)
Incorporates 256-bit symmetric key overlay for high-security environments:
```ini
[Interface]
PrivateKey = {{CLIENT_PRIVATE_KEY}}
Address = {{CLIENT_IPV4_ADDRESS}}/32, {{CLIENT_IPV6_ADDRESS}}/128
DNS = 127.0.0.53
MTU = 1420
Table = auto

[Peer]
PublicKey = {{SERVER_PUBLIC_KEY}}
PresharedKey = {{PRESHARED_KEY}}
Endpoint = {{SERVER_ENDPOINT_IP}}:{{SERVER_ENDPOINT_PORT}}
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
```

### 3.3 Interface Pinned & Kill-Switch Enabled Template (`wg0-pinned.conf.template`)
Implements strict firewall hooks blocking unencrypted egress if the tunnel collapses:
```ini
[Interface]
PrivateKey = {{CLIENT_PRIVATE_KEY}}
Address = {{CLIENT_IPV4_ADDRESS}}/32, {{CLIENT_IPV6_ADDRESS}}/128
DNS = 127.0.0.53
MTU = 1420
FwMark = 0x51820
Table = auto

PostUp = iptables -I OUTPUT ! -o %i -m mark ! --mark 0x51820 -m addrtype ! --dst-type LOCAL -j REJECT; ip6tables -I OUTPUT ! -o %i -m mark ! --mark 0x51820 -m addrtype ! --dst-type LOCAL -j REJECT
PostDown = iptables -D OUTPUT ! -o %i -m mark ! --mark 0x51820 -m addrtype ! --dst-type LOCAL -j REJECT; ip6tables -D OUTPUT ! -o %i -m mark ! --mark 0x51820 -m addrtype ! --dst-type LOCAL -j REJECT

[Peer]
PublicKey = {{SERVER_PUBLIC_KEY}}
Endpoint = {{SERVER_ENDPOINT_IP}}:{{SERVER_ENDPOINT_PORT}}
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
```

---

## 4. CLI Management Utility (`scripts/manage-wireguard.sh`)

The `manage-wireguard.sh` utility provides unified management of key generation, profile instantiation, connection lifecycle, and active health monitoring:

### 4.1 Keypair Generation
Generates Curve25519 keypairs and PSKs under strict `umask 077` and `0600` file permissions:
```bash
./scripts/manage-wireguard.sh generate-keys
```

### 4.2 Profile Instantiation
Generates a complete `/etc/wireguard/wg0.conf` from a specified template:
```bash
./scripts/manage-wireguard.sh create-profile --template pinned --interface wg0
```

### 4.3 Connection Lifecycle Commands
```bash
./scripts/manage-wireguard.sh up --interface wg0       # Bring tunnel interface up
./scripts/manage-wireguard.sh down --interface wg0     # Bring tunnel interface down
./scripts/manage-wireguard.sh restart --interface wg0  # Restart tunnel interface
./scripts/manage-wireguard.sh status --interface wg0   # Inspect interface, handshakes & routes
```

### 4.4 Tunnel Watchdog Health Check
Inspects peer handshakes and auto-reconnects if handshake age exceeds threshold (default: 180 seconds):
```bash
./scripts/manage-wireguard.sh watchdog --interface wg0 --threshold 180
```

---

## 5. Systemd Health Watchdog & Hardening Integration

MAYOTIX OS provides background health automation via systemd unit files located in `services/`:

- **`services/mayotix-wg-watchdog.service`**: Systemd service executing `manage-wireguard.sh watchdog` under strict security sandboxing:
  - `ProtectSystem=strict`, `ProtectHome=yes`, `PrivateTmp=yes`, `PrivateDevices=yes`
  - `CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW`
  - `RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK`
- **`services/mayotix-wg-watchdog.timer`**: Systemd timer executing the watchdog service every 60 seconds starting 1 minute after boot (`OnUnitActiveSec=60s`).

---

## 6. Security Permissions & Verification Audit

The verification harness `scripts/verify-wireguard.sh` evaluates 7 core security modules to guarantee 100% compliance:

```bash
./scripts/verify-wireguard.sh --full-audit
```

### Audit Module Breakdown
1. **Kernel Support**: Verifies kernel module `wireguard` state or `wg` utility availability.
2. **Security Permissions**: Audits `/etc/wireguard` directory mode (`0700`) and key file permissions (`0600`/`0400`).
3. **Template Syntax**: Validates INI headers, cryptographic placeholders, and structure.
4. **Cryptographic Mechanics**: Validates Curve25519 key generation under `umask 077` (44 base64 characters).
5. **Routing Integrity**: Validates `AllowedIPs = 0.0.0.0/0, ::/0` default routing, systemd-resolved DoT pointers (`127.0.0.53`), and kill-switch rules.
6. **Watchdog Unit Audit**: Audits systemd unit file syntax and security hardening directives.
7. **CLI Utility Validation**: Audits `scripts/manage-wireguard.sh` dry-run execution.

---

## 7. Operations & Maintenance Reference

### Quick Commands

```bash
# Test WireGuard readiness & security compliance
./scripts/verify-wireguard.sh

# Generate key material
./scripts/manage-wireguard.sh generate-keys

# Dry-run watchdog evaluation
./scripts/manage-wireguard.sh watchdog --dry-run
```

---
*MAYOTIX OS Phase 5 Documentation - Secure Networking & Cryptographic Workstations*
