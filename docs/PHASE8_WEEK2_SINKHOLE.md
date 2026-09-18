# MAYOTIX OS Phase 8 Week 2: Virtual Bridge Network Controller & Dynamic Traffic Sinkhole

## 1. Architectural Overview & Vision

Phase 8 Week 2 establishes network virtualization, automated traffic sinkholing, and containment firewall controls for the MAYOTIX Labs subsystem.

When analyzing untrusted code or executing dynamic malware analysis in a sandbox, preventing accidental breakout into production networks or the external internet is vital. Phase 8 Week 2 delivers:
1. **Virtual Bridge Network Controller (`desktop/labs/lab-network.sh`)**:
   - Manages dedicated virtual bridge interface `mayotix-br0` with gateway IP `10.99.0.1/24`.
   - Kernel-level `nftables` containment firewall dropping all forward traffic from `mayotix-br0` to physical network adapters (`enp*`, `wlan*`, `eth*`) and private host subnets (`192.168.0.0/16`, `10.0.0.0/8`, `172.16.0.0/12`).
2. **Dynamic Malware Traffic Sinkhole & DNS Blackhole (`desktop/labs/sinkhole.py`)**:
   - **UDP DNS Blackhole**: Intercepts outbound DNS lookups from sandbox containers and resolves all domains to `10.99.0.1`.
   - **HTTP/HTTPS C2 Simulator**: Listens on ports 80/443, returns `200 OK` (simulated C2 acknowledgments), and logs request paths, headers, and payloads to `/var/log/mayotix/labs/sinkhole.log`.
3. **SELinux Policy Port Confinement (`security/selinux/mayotix_labs.te`)**:
   - Explicitly grants `dns_port_t` and `http_port_t` `name_bind` permissions to `mayotix_labs_t` while strictly maintaining the host user home directory airgap.
4. **Privileged IPC Daemon & Unified CLI Integration**:
   - Extended `daemon/mayotix-daemon.py` with `lab.network_*` and `lab.sinkhole_*` endpoints.
   - Integrated into unified CLI: `mayotix lab network` and `mayotix lab sinkhole`.

```
+-------------------------------------------------------------------------------+
|                      ISOLATED LAB SANDBOX CONTAINER                           |
|                                                                               |
|   - DNS Request: "attacker-c2.evil"                                           |
|   - HTTP Request: POST /beacon HTTP/1.1 (Payload: Base64 Host Telemetry)      |
+-----------------------------------+-------------------------------------------+
                                    |
                                    v (mayotix-br0: 10.99.0.0/24)
+-------------------------------------------------------------------------------+
|                 FAIL-CLOSED CONTAINMENT FIREWALL (nftables)                   |
|                                                                               |
|   - Forward to enp*/wlan*/eth*                : STRICT DROP                   |
|   - Forward to RFC1918 LAN (192.168.0.0/16)   : STRICT DROP                   |
|   - Ingress to 10.99.0.1 (Ports 53, 80, 443)  : ACCEPT (Sinkhole Only)        |
+-----------------------------------+-------------------------------------------+
                                    |
                                    v
+-------------------------------------------------------------------------------+
|             DYNAMIC MALWARE TRAFFIC SINKHOLE (sinkhole.py)                    |
|                                                                               |
|   1. DNS Blackhole (Port 53/UDP):                                             |
|      - Resolves ANY requested hostname -> 10.99.0.1                           |
|   2. Simulated C2 Webserver (Port 80/TCP):                                    |
|      - Returns HTTP 200 OK ({"status": "ok", "sinkhole": true})               |
|   3. Forensics Telemetry Logger:                                              |
|      - Appends structured JSON to /var/log/mayotix/labs/sinkhole.log          |
+-------------------------------------------------------------------------------+
```

---

## 2. Firewall Containment Policy (`mayotix_lab_isolation`)

The firewall rules are loaded into the kernel `nftables` table `inet mayotix_lab_isolation`:

```text
table inet mayotix_lab_isolation {
    chain forward {
        type filter hook forward priority -100; policy drop;
        iifname "mayotix-br0" oifname "lo" accept
        iifname "mayotix-br0" drop
    }
    chain input {
        type filter hook input priority -100; policy drop;
        iifname "mayotix-br0" ip daddr 10.99.0.1 tcp dport { 80, 443 } accept
        iifname "mayotix-br0" ip daddr 10.99.0.1 udp dport 53 accept
        iifname "mayotix-br0" drop
    }
}
```

---

## 3. Sinkhole Telemetry Specifications

All DNS lookups and HTTP beaconing attempts are written in JSON Lines format to `/var/log/mayotix/labs/sinkhole.log`:

```json
{
  "timestamp": 1789723000.12,
  "utc_time": "2026-09-18T14:50:00Z",
  "event_type": "HTTP_C2_INTERCEPT",
  "details": {
    "client_ip": "10.99.0.42",
    "client_port": 49210,
    "method": "POST",
    "path": "/api/v1/heartbeat",
    "headers": {
      "Host": "api.c2network.com",
      "User-Agent": "MalwareDropper/2.0"
    },
    "body_snippet": "data=dGhpcyBpcyBhIHRlc3Q="
  }
}
```

---

## 4. Verification & Usage Guide

```bash
# Initialize the virtual bridge and containment firewall (dry-run)
mayotix lab network start --dry-run

# Inspect virtual bridge posture and active policy
mayotix lab network status --dry-run --json

# Test dynamic sinkhole service initialization
mayotix lab sinkhole start --dry-run --json

# Query captured malware C2 and DNS events
mayotix lab sinkhole logs --dry-run

# Execute automated Phase 8 Week 2 verification suite
sudo ./scripts/verify-labs-week2.sh --dry-run
```
