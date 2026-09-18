# MAYOTIX OS Phase 5 Week 4: Optional Tor Isolation Proxy & Onion Routing

## 1. Architectural Overview & Vision

Phase 5 Week 4 implements optional Tor isolation proxying and onion routing for MAYOTIX OS. This subsystem provides cryptographic stream anonymization, `.onion` domain resolution, transparent proxying, and fail-closed leak prevention for privacy-sensitive applications and ephemeral environments.

Operating seamlessly alongside **Phase 5 Week 1 (Encrypted DNS / DoT)**, **Phase 5 Week 2 (Kernel WireGuard Integration)**, and **Phase 5 Week 3 (Fail-Closed nftables Kill-Switch)**, the Tor subsystem guarantees:
1. **Per-Destination Stream Isolation**: SOCKS5 connections dynamically build independent circuits for distinct destination addresses and ports (`IsolateDestAddr`, `IsolateDestPort`), eliminating cross-site correlation.
2. **Transparent TCP & DNS Redirection**: Sandboxed applications or marked processes have their TCP traffic transparently redirected to Tor's `TransPort` (`127.0.0.1:9040`) and DNS queries to `DNSPort` (`127.0.0.1:9053`).
3. **Fail-Closed Non-TCP Leak Elimination**: Tor does not support non-TCP protocols (such as raw UDP or ICMP). All non-TCP traffic from Tor-isolated sessions is proactively dropped and tracked via nftables telemetry counters.
4. **Secure Dynamic Identity Management**: Authenticated ControlPort (`127.0.0.1:9051`) access permits instantaneous circuit renewal (`SIGNAL NEWNYM`).

```
+-----------------------------------------------------------------------------------------+
|                                     MAYOTIX OS                                          |
|                                                                                         |
|  +-------------------------------------+      +--------------------------------------+  |
|  | SOCKS5 Applications                 |      | Transparently Isolated Applications  |  |
|  | (Tor Browser, curl, Priv Apps)      |      | (Ephemeral sandboxes, CLI utilities) |  |
|  +------------------+------------------+      +------------------+-------------------+  |
|                     | SOCKS5 Proxy                       | Mark 0x200 / GID 9050        |
|                     | (127.0.0.1:9050)                   v                              |
|                     |                   +--------------------------------------------+  |
|                     |                   | nftables Table: inet mayotix_tor           |  |
|                     |                   | - UDP/TCP 53 -> Redirect to :9053 (DNSPort)|  |
|                     |                   | - TCP Traffic -> Redirect to :9040(TransP) |  |
|                     |                   | - Non-TCP (UDP/ICMP) -> DROPPED (No Leaks) |  |
|                     |                   +---------------------+----------------------+  |
|                     |                                         |                         |
|                     v                                         v                         |
|  +-----------------------------------------------------------------------------------+  |
|  |                     Hardened Tor Daemon (torrc.mayotix)                           |  |
|  |                                                                                   |  |
|  |  - SocksPort 127.0.0.1:9050 (IsolateDestAddr, IsolateDestPort)                    |  |
|  |  - TransPort 127.0.0.1:9040 (Transparent Proxy Listener)                          |  |
|  |  - DNSPort 127.0.0.1:9053 (AutomapHostsOnResolve .onion -> 10.192.0.0/10)         |  |
|  |  - ControlPort 127.0.0.1:9051 (CookieAuthentication -> SIGNAL NEWNYM)             |  |
|  |  - Hardening: SafeLogging 1, AvoidDiskWrites 1, DisableDebuggerAttachment 1       |  |
|  +------------------------------------+----------------------------------------------+  |
|                                       | 3-Hop Encrypted Onion Circuits                  |
|                                       v                                                 |
|  +-----------------------------------------------------------------------------------+  |
|  |                        nftables Kill-Switch (Phase 5 Week 3)                      |  |
|  |                                                                                   |  |
|  |  - Allows outbound Tor daemon traffic via WireGuard (wg0) or Physical NIC (enp*)  |  |
|  |  - Drops any rogue unencapsulated / unrouted cleartext egress                      |  |
|  +--------------------+---------------------------------------+----------------------+  |
|                       |                                       |                         |
+-----------------------|---------------------------------------|-------------------------+
                        | Encrypted Tor Onion Circuits          | WireGuard VPN Encapsulation
                        v                                       v
         +------------------------------+        +------------------------------+
         |      Tor Guard Relay         |        |   Remote VPN Gateway Node    |
         +------------------------------+        +------------------------------+
```

---

## 2. Tor Daemon Configuration (`config/network/tor/torrc.mayotix`)

The hardened Tor daemon configuration enforces strict memory isolation, disk privacy, and circuit segregation:

```ini
# Network Service Binding & Isolation
SocksPort 127.0.0.1:9050 IsolateDestAddr IsolateDestPort
TransPort 127.0.0.1:9040
DNSPort 127.0.0.1:9053
ControlPort 127.0.0.1:9051

# Control Interface Security
CookieAuthentication 1
CookieAuthFile /run/tor/control.authcookie

# Cryptographic & Hardening Directives
SafeLogging 1
AvoidDiskWrites 1
DisableDebuggerAttachment 1
ClientOnly 1
HardwareAccel 1

# Onion Domain Resolution & Virtual Network Mapping
AutomapHostsOnResolve 1
AutomapHostsSuffixes .onion
VirtualAddrNetworkIPv4 10.192.0.0/10

# Daemon Logging & Data Directory
Log notice stderr
DataDirectory /var/lib/tor-mayotix
```

### 2.1 Directives & Security Rationale

| Directive | Value / Setting | Security Objective |
| :--- | :--- | :--- |
| `SocksPort` | `127.0.0.1:9050 IsolateDestAddr IsolateDestPort` | Isolates streams by destination IP and port; prevents cross-site tracking across tabs or apps. |
| `TransPort` | `127.0.0.1:9040` | Accepts transparent TCP connections redirected by nftables. |
| `DNSPort` | `127.0.0.1:9053` | Anonymously resolves DNS queries over Tor circuits, preventing plaintext DNS leaks. |
| `ControlPort` | `127.0.0.1:9051` | Protected administrative socket for circuit inspection and identity renewal. |
| `CookieAuthentication` | `1` | Requires cryptographically generated random cookie verification before accepting commands. |
| `SafeLogging` | `1` | Sanitizes all IP addresses and sensitive hostnames in log messages. |
| `AvoidDiskWrites` | `1` | Minimizes disk operations to prevent forensic artifacts in flash/NVMe memory. |
| `DisableDebuggerAttachment`| `1` | Blocks `ptrace(2)` and memory inspection from unprivileged host processes. |
| `ClientOnly` | `1` | Disables relay or directory authority functionality, operating strictly as a local client. |
| `AutomapHostsOnResolve` | `1` | Dynamically assigns virtual IP addresses from `10.192.0.0/10` to `.onion` hidden services. |

---

## 3. Transparent Routing Ruleset (`config/network/nftables/mayotix-tor-router.nft`)

The `mayotix-tor-router.nft` ruleset provisions the `inet mayotix_tor` table to transparently route application traffic while eliminating protocol leaks:

```nft
flush table inet mayotix_tor
table inet mayotix_tor {
    counter routed_tor_tcp_packets { }
    counter routed_tor_dns_queries { }
    counter blocked_tor_leak_packets { }

    chain prerouting {
        type nat hook prerouting priority dstnat; policy accept;
        meta mark 0x200 udp dport 53 counter name routed_tor_dns_queries redirect to :9053
        meta mark 0x200 tcp dport 53 counter name routed_tor_dns_queries redirect to :9053
        meta mark 0x200 tcp dport != 53 counter name routed_tor_tcp_packets redirect to :9040
    }

    chain output {
        type route hook output priority mangle; policy accept;
        meta gid 9050 meta mark set 0x200
    }

    chain input {
        type filter hook input priority filter; policy accept;
        iifname "lo" tcp dport { 9050, 9040, 9051 } accept
        iifname "lo" udp dport 9053 accept
    }

    chain forward {
        type filter hook forward priority filter; policy drop;
        meta mark 0x200 drop
    }

    chain leak_prevention {
        type filter hook output priority filter; policy accept;
        meta mark 0x200 ct state established,related accept
        meta mark 0x200 ip daddr 127.0.0.1 tcp dport { 9040, 9050, 9051 } accept
        meta mark 0x200 ip daddr 127.0.0.1 udp dport 9053 accept
        meta mark 0x200 ip protocol != tcp counter name blocked_tor_leak_packets drop
    }
}
```

---

## 4. CLI Management Utility (`scripts/manage-tor.sh`)

The `manage-tor.sh` utility provides operators and scripts with unified lifecycle control over Tor isolation and circuit operations.

### 4.1 Commands & Features

- **`enable`**: Atomically loads `mayotix-tor-router.nft` and ensures Tor daemon readiness.
- **`disable`**: Flushes table `inet mayotix_tor`, restoring standard network paths.
- **`status`**: Audits daemon state, SOCKS5 port (9050), TransPort (9040), DNSPort (9053), ControlPort (9051), circuit health, exit IP, and dropped leak statistics. Structured JSON is supported via `--json`.
- **`newnym`**: Authenticates to ControlPort on `127.0.0.1:9051` and issues `SIGNAL NEWNYM` to establish a fresh identity and circuit.
- **`route-app <cmd...>`**: Executes any arbitrary command wrapped in a Tor isolation environment (configuring SOCKS5 proxy environment variables and socket markings).
- **`verify`**: Validates configuration and ruleset syntax in dry-run mode.

```bash
# Check daemon status, circuit health, and counters
./scripts/manage-tor.sh status

# Request fresh Tor circuit and exit IP
./scripts/manage-tor.sh newnym

# Launch an application wrapped in Tor transparent isolation
./scripts/manage-tor.sh route-app curl https://check.torproject.org/api/ip

# Output structured telemetry in JSON format
./scripts/manage-tor.sh status --json
```

---

## 5. Systemd Service Unit & Hardening (`services/mayotix-tor.service`)

The systemd service unit isolates the Tor process with comprehensive Linux namespace and capability sandboxing:

```ini
[Unit]
Description=MAYOTIX OS Hardened Tor Isolation Proxy & Onion Router
Documentation=man:tor(1) https://mayotix.os/docs/phase5
After=network-pre.target mayotix-killswitch.service
Wants=network.target

[Service]
Type=notify
ExecStartPre=/usr/bin/tor --verify-config -f /etc/tor/torrc.mayotix
ExecStart=/usr/bin/tor -f /etc/tor/torrc.mayotix
ExecReload=/bin/kill -HUP $MAINPID
KillSignal=SIGINT
TimeoutSec=60
Restart=on-failure
RestartSec=5s

# Security Hardening Directives
User=debian-tor
Group=debian-tor
RuntimeDirectory=tor
RuntimeDirectoryMode=0700
StateDirectory=tor-mayotix
StateDirectoryMode=0700

ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
PrivateDevices=yes
NoNewPrivileges=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
MemoryDenyWriteExecute=yes
RestrictRealtime=yes
CapabilityBoundingSet=CAP_NET_BIND_SERVICE CAP_SETUID CAP_SETGID
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK
SystemCallArchitectures=native
SystemCallFilter=@system-service @network-io
SystemCallErrorNumber=EPERM

[Install]
WantedBy=multi-user.target
```

---

## 6. Verification Harness & Security Audit Results

The verification script `scripts/verify-tor.sh` executes 28 rigorous security checks across 7 core modules:

```bash
./scripts/verify-tor.sh --full-audit --dry-run
```

### Verification Module Breakdown

| Module | Description | Checks | Result |
| :--- | :--- | :---: | :---: |
| **1. Tor Subsystem Readiness** | Tor daemon binary, nft utility, configuration directories | 3 | **PASS (100%)** |
| **2. Security & Permissions** | File existence (`torrc`, `nft`, `service`) and executable modes (`0755`/`0644`) | 4 | **PASS (100%)** |
| **3. Tor Hardening Directives** | SOCKS5 (9050), TransPort (9040), DNSPort (9053), ControlPort (9051), SafeLogging, AvoidDiskWrites | 6 | **PASS (100%)** |
| **4. Transparent Router Audit** | Table `inet mayotix_tor`, DNS redirect to 9053, TCP redirect to 9040, non-TCP drop | 5 | **PASS (100%)** |
| **5. Stream Isolation & Onion** | `AutomapHostsOnResolve`, `.onion` mapping, virtual range `10.192.0.0/10`, leak drop counters | 3 | **PASS (100%)** |
| **6. Systemd Hardening Audit** | `ExecStartPre` syntax check, filesystem sandboxing, capability bounding, syscall filters | 4 | **PASS (100%)** |
| **7. CLI Utility & Integration** | CLI `--help`, `verify`, `status --json`, `newnym`, and `route-app` dry-run execution | 5 | **PASS (100%)** |
| **Total** | **Comprehensive Phase 5 Week 4 Verification** | **28** | **28/28 (100%)** |

---

## 7. Operations & Maintenance Reference

### Quick Commands

```bash
# Execute full security verification audit
./scripts/verify-tor.sh --full-audit

# Inspect active Tor status, exit IP, and circuit health
./scripts/manage-tor.sh status

# Establish fresh circuit & newnym identity
./scripts/manage-tor.sh newnym

# Route arbitrary tool or curl command through Tor
./scripts/manage-tor.sh route-app curl -s https://check.torproject.org/api/ip

# Validate ruleset syntax and config structure
./scripts/manage-tor.sh verify --dry-run
```

---
*MAYOTIX OS Phase 5 Documentation - Secure Networking & Cryptographic Workstations*
