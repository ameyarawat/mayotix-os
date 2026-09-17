# MAYOTIX OS Phase 5 Week 1: System-wide Encrypted DNS (DNS-over-TLS)

## Overview

Phase 5 Week 1 eliminates plaintext DNS from MAYOTIX OS entirely. All name resolution is forced through **DNS-over-TLS (DoT)** on port 853 with **DNSSEC validation**, removing the single largest passive-surveillance channel remaining in the hardened workstation: unencrypted UDP/53 queries visible to every intermediate hop.

This milestone establishes the network privacy foundation upon which subsequent Phase 5 weeks (WireGuard tunnelling, Tor routing, kill-switch enforcement) depend.

---

## Threat Model

| Threat | Description | Mitigation |
|--------|-------------|------------|
| **Passive DNS Surveillance** | ISPs, transit providers, and local network operators log plaintext UDP/53 queries to build browsing profiles | TLS 1.2+ encryption of all queries via port 853 |
| **DNS Spoofing / Cache Poisoning** | Attacker injects forged responses to redirect traffic to malicious hosts | DNSSEC cryptographic signature validation (RRSIG chains) |
| **Active MITM Interception** | Transparent DNS proxies rewriting responses at the gateway | Strict `DNSOverTLS=yes` — resolution fails rather than downgrading |
| **Resolver Impersonation** | Attacker presents a valid-but-wrong TLS certificate for the resolver IP | SNI hostname pinning (`IP#hostname` syntax) validates the certificate CN/SAN |
| **Local Network Metadata Leakage** | mDNS/LLMNR broadcast hostname queries across the LAN, exposing device identity | `MulticastDNS=no`, `LLMNR=no` |
| **Split-Horizon DNS Leakage** | Per-interface DHCP-supplied resolvers silently bypass the encrypted path | `Domains=~.` forces all lookups through the global encrypted resolvers |

---

## Components Implemented

### 1. Hardened Resolver Configuration

**File**: `config/network/resolved.conf.d/mayotix-dot.conf`
**Deployed to**: `/etc/systemd/resolved.conf.d/mayotix-dot.conf`

A systemd-resolved drop-in that overrides distribution defaults without modifying the vendor-owned `/etc/systemd/resolved.conf`.

#### Configuration Directives

| Directive | Value | Rationale |
|-----------|-------|-----------|
| `DNSOverTLS` | `yes` | **Strict mode.** Queries fail closed if TLS cannot be established. The alternative (`opportunistic`) silently downgrades to plaintext when a network blocks 853 — exactly the condition an active attacker creates. |
| `DNSSEC` | `allow-downgrade` | Validates signatures for DNSSEC-signed zones while remaining functional on unsigned zones and captive portals. Prevents the total-breakage failure mode of `DNSSEC=yes` on real-world networks. |
| `Domains` | `~.` | Routing-only wildcard domain. Forces *every* lookup through the globally configured resolvers, overriding per-link DHCP resolvers that would otherwise handle unmatched domains. |
| `MulticastDNS` | `no` | Disables mDNS (UDP/5353) LAN broadcast, which leaks hostnames and is unauthenticated. |
| `LLMNR` | `no` | Disables Link-Local Multicast Name Resolution, historically abused for NTLM relay and credential-theft attacks. |
| `DNSCache` | `yes` | Local caching reduces query volume, limiting the metadata surface exposed to the upstream resolver. |
| `CacheFromLocalhost` | `no` | Prevents cache-poisoning attempts originating from a compromised local process. |

#### Trusted Resolver Endpoints

Resolvers are declared using systemd's `IP#hostname` syntax. The hostname is **not** a lookup target — it is the expected TLS certificate identity, which prevents an attacker who controls routing to the IP from presenting an unrelated valid certificate.

**Primary (`DNS=`)**

| Provider | IPv4 | IPv6 | TLS Name | Selection Rationale |
|----------|------|------|----------|---------------------|
| **Quad9** | `9.9.9.9`, `149.112.112.112` | `2620:fe::fe` | `dns.quad9.net` | Swiss jurisdiction, no-log policy, integrated malware-domain blocklist, DNSSEC-validating |
| **Mullvad** | `194.242.2.3` | `2a07:e340::3` | `dns.mullvad.net` | Audited no-log infrastructure, privacy-first operator, no commercial data monetization |
| **Cloudflare** | `1.1.1.1` | `2606:4700:4700::1111` | `cloudflare-dns.com` | Lowest global latency, 24h log retention, high availability |

**Fallback (`FallbackDNS=`)**

`1.0.0.1#cloudflare-dns.com`, `194.242.2.4#dns.mullvad.net`, `2620:fe::9#dns.quad9.net`, `2606:4700:4700::1001#cloudflare-dns.com`

> **Design note**: Every fallback endpoint is *also* an encrypted DoT resolver. Unlike the Phase 2 configuration — which listed plaintext Google DNS (`8.8.8.8`) as fallback — there is no plaintext escape hatch. If all DoT endpoints are unreachable, resolution fails rather than leaking.

---

### 2. Verification Script

**File**: `scripts/verify-encrypted-dns.sh`

A four-module verification harness that validates configuration correctness, live TLS reachability, DNSSEC enforcement, and plaintext leakage.

#### Usage

```bash
# Full audit (all four modules)
./scripts/verify-encrypted-dns.sh

# Individual modules
./scripts/verify-encrypted-dns.sh --check-config      # Static configuration validation
./scripts/verify-encrypted-dns.sh --test-handshake    # Live TLS handshake on port 853
./scripts/verify-encrypted-dns.sh --test-dnssec       # DNSSEC signature validation
./scripts/verify-encrypted-dns.sh --test-leakage      # Plaintext port 53 leak scan

# CI-safe modes
./scripts/verify-encrypted-dns.sh --dry-run           # No live network traffic
./scripts/verify-encrypted-dns.sh --report-only       # Never returns non-zero exit
```

#### Module 1 — Configuration Validation (5 checks)

Parses the drop-in from the repository (`config/network/...`) or the deployed system path (`/etc/systemd/resolved.conf.d/...`), asserting:

1. `DNSOverTLS=yes` — strict TLS, no opportunistic downgrade
2. `DNSSEC=allow-downgrade` or `yes` — validation active
3. `Domains=~.` — global routing wildcard present
4. `MulticastDNS=no` **and** `LLMNR=no` — LAN protocols disabled
5. Privacy resolvers present with SNI hostname pinning

#### Module 2 — TLS Handshake Verification

Performs a real TLS handshake against each DoT endpoint on port 853:

```bash
echo "Q" | openssl s_client -connect 9.9.9.9:853 -servername dns.quad9.net -brief
```

Falls back to `nc -z -w 3 <ip> 853` for reachability when OpenSSL is unavailable. Fails only when **no** endpoint responds — a single unreachable provider produces a warning, since transient provider outages should not fail the audit.

#### Module 3 — DNSSEC Validation

Two complementary checks:

- **Runtime state**: `resolvectl status` must report `DNSSEC=allow-downgrade` or `yes`
- **Live validation**: `kdig +dnssec` against a known-good domain (`cloudflare.com`, expects RRSIG records) and a deliberately broken-signature domain (`sigfail.verteiltesysteme.net`, expects `SERVFAIL`)

Degrades gracefully to `dig` and finally to structural configuration verification when neither tool is installed.

#### Module 4 — Port 53 Leakage Detection

Three assertions that no plaintext DNS escapes the host:

1. **Outbound socket scan** — `ss -tupn` filtered for non-loopback `:53` connections. Any match is a hard failure indicating an application bypassing systemd-resolved.
2. **Stub listener binding** — `127.0.0.53:53` must be bound to loopback only, confirming the resolved stub is the sole local DNS entry point.
3. **`/etc/resolv.conf` integrity** — must symlink to the systemd-resolved stub (or contain `127.0.0.53`), proving no NetworkManager or DHCP client has overwritten it with raw upstream resolvers.

#### Output

Results are written to `build/PHASE5_WEEK1_DNS_VERIFICATION_REPORT.txt` with pass/fail/warning counts and a compliance determination. The script exits non-zero on any failure unless `--report-only` is set.

---

## Deployment

```bash
# 1. Install the drop-in
sudo mkdir -p /etc/systemd/resolved.conf.d
sudo cp config/network/resolved.conf.d/mayotix-dot.conf /etc/systemd/resolved.conf.d/

# 2. Ensure resolv.conf points at the resolved stub
sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

# 3. Apply
sudo systemctl enable --now systemd-resolved
sudo systemctl restart systemd-resolved

# 4. Verify
./scripts/verify-encrypted-dns.sh
```

### Firewall Interaction

The Phase 2 firewall (`scripts/configure-firewall-phase2.sh`) permits the `dns` service on port 53. Under Phase 5, outbound TCP/853 must be reachable:

```bash
sudo firewall-cmd --permanent --zone=public --add-port=853/tcp
sudo firewall-cmd --reload
```

> **Note**: Port 53 is retained inbound only for the loopback stub. A later Phase 5 milestone introduces an egress kill-switch that drops outbound UDP/53 entirely at the nftables layer.

---

## Manual Verification

### Confirm DoT is active

```bash
resolvectl status
```

Expected output includes:

```
+DNSOverTLS +DNSSEC/supported
DNS Servers: 9.9.9.9#dns.quad9.net 149.112.112.112#dns.quad9.net ...
```

### Confirm encrypted transport on the wire

```bash
# Should show TLS traffic to port 853, and NO plaintext port 53 traffic
sudo tcpdump -i any -n 'port 853 or port 53'
```

While running a lookup in another terminal (`resolvectl query example.com`), only `:853` packets should appear.

### Confirm DNSSEC rejection

```bash
resolvectl query sigfail.verteiltesysteme.net
# Expected: resolution failure / DNSSEC validation failed
```

### Confirm no leakage

```bash
ss -tupn | grep ':53'
# Expected: only 127.0.0.53:53 (the local stub)
```

---

## Security Properties Achieved

| Property | Implementation | Result |
|----------|----------------|--------|
| **Query Confidentiality** | TLS 1.2+ on port 853 | Query contents invisible to ISP and transit network |
| **Response Integrity** | DNSSEC RRSIG validation | Forged or tampered responses rejected |
| **Resolver Authenticity** | SNI hostname certificate pinning | Resolver impersonation prevented |
| **Fail-Closed Behaviour** | `DNSOverTLS=yes` (strict) | No silent plaintext downgrade under attack |
| **No Plaintext Fallback** | All `FallbackDNS` entries are DoT | Zero plaintext escape path |
| **LAN Metadata Suppression** | mDNS and LLMNR disabled | Hostname not broadcast; NTLM relay surface removed |
| **Uniform Routing** | `Domains=~.` | DHCP-supplied resolvers cannot bypass encryption |
| **Continuous Assurance** | `verify-encrypted-dns.sh` | Regressions detected in CI and on-host |

---

## Troubleshooting

### All resolution fails after applying the configuration

**Cause**: The network blocks outbound TCP/853 (common on captive portals and some corporate networks). With `DNSOverTLS=yes`, this correctly fails closed rather than leaking.

**Diagnosis**:
```bash
./scripts/verify-encrypted-dns.sh --test-handshake
```

**Resolution**: Complete captive-portal authentication on a separate network, or open TCP/853 egress on the local firewall. Do **not** downgrade to `opportunistic` — that reintroduces the plaintext leak this milestone eliminates.

### `resolvectl status` shows `-DNSOverTLS`

**Cause**: The drop-in was not loaded, or an earlier drop-in (e.g. the Phase 2 `mayotix.conf` with `DNSOverTLS=opportunistic`) sorts later alphabetically and overrides it.

**Resolution**:
```bash
ls /etc/systemd/resolved.conf.d/
# Remove or reconcile the Phase 2 drop-in
sudo rm /etc/systemd/resolved.conf.d/mayotix.conf
sudo systemctl restart systemd-resolved
```

### Plaintext port 53 traffic still visible

**Cause**: An application is using its own resolver stack rather than the system stub — commonly browsers with built-in DNS-over-HTTPS disabled, or containers with an injected `/etc/resolv.conf`.

**Diagnosis**:
```bash
sudo ss -tupn | grep ':53'   # identifies the offending process
```

**Resolution**: Point the application at `127.0.0.53`, or rely on the nftables egress kill-switch introduced later in Phase 5.

### Some domains fail to resolve

**Cause**: A DNSSEC-misconfigured upstream zone.

**Diagnosis**:
```bash
kdig +dnssec <domain>
```

`allow-downgrade` already tolerates *unsigned* zones — a failure here indicates a genuinely broken signature chain at the domain operator, not a local misconfiguration.

---

## Integration with Phase 5

| Week | Milestone | Dependency on Week 1 |
|------|-----------|----------------------|
| **Week 2** | WireGuard VPN Integration | Encrypted DNS prevents DNS leaks outside the tunnel during connect/disconnect transitions |
| **Week 3** | Tor Transparent Routing | `Domains=~.` routing model extends to `.onion` resolution via the Tor resolver |
| **Week 4** | Kill-Switch & Leak Prevention | nftables rules drop outbound UDP/53 entirely, enforcing what this configuration establishes by policy |
| **Week 5** | Phase 5 ISO & Audit | `verify-encrypted-dns.sh` contributes to the Phase 5 security audit score |

---

*MAYOTIX OS Engineering Team*
*Phase 5 Week 1 — September 2026*
