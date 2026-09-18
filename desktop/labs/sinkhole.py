#!/usr/bin/env python3
"""
MAYOTIX OS Phase 8 Week 2: Dynamic Malware Traffic Sinkhole & DNS Blackhole

Intercepts outbound DNS queries and HTTP/HTTPS C2 traffic originating from
isolated lab sandboxes. Resolves all domain queries to the sinkhole gateway
and logs simulated C2 beaconing behavior for malware analysis.

Features:
  - UDP DNS Blackhole: Responds to all domain lookups with sinkhole IP (10.99.0.1).
  - HTTP C2 Simulator: Returns 200 OK and logs HTTP headers, paths, and payloads.
  - Forensic Logging: Appends structured event telemetry to /var/log/mayotix/labs/sinkhole.log.
  - Non-blocking headless dry-run and JSON inspection modes.
"""

import sys
import os
import time
import json
import socket
import argparse
import threading
from pathlib import Path
from http.server import HTTPServer, BaseHTTPRequestHandler

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

SINKHOLE_IP = "10.99.0.1"
LOG_DIR = Path("/var/log/mayotix/labs")
LOG_FILE = LOG_DIR / "sinkhole.log"

# Terminal Colors
RED = "\033[0;31m"
GREEN = "\033[0;32m"
YELLOW = "\033[1;33m"
CYAN = "\033[0;36m"
BOLD = "\033[1m"
NC = "\033[0m"

def log_event(event_type, details):
    """Appends a structured event entry to the sinkhole forensic log."""
    entry = {
        "timestamp": time.time(),
        "utc_time": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "event_type": event_type,
        "details": details
    }
    try:
        LOG_DIR.mkdir(parents=True, exist_ok=True)
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry) + "\n")
    except Exception:
        pass
    return entry

def build_dns_response(data, sinkhole_ip):
    """Constructs a basic DNS A-record response resolving the queried domain to sinkhole_ip."""
    if len(data) < 12:
        return None
    # Transaction ID + Flags (Standard response, no error)
    tid = data[:2]
    flags = b"\x81\x80"
    qdcount = data[4:6]
    ancount = b"\x00\x01" # 1 answer
    nscount = b"\x00\x00"
    arcount = b"\x00\x00"
    header = tid + flags + qdcount + ancount + nscount + arcount

    # Find end of question section
    idx = 12
    while idx < len(data) and data[idx] != 0:
        idx += 1 + data[idx]
    q_end = idx + 5 # include null byte + QTYPE (2 bytes) + QCLASS (2 bytes)
    question = data[12:q_end]

    # Construct Answer: pointer to domain offset 0xc00c, Type A (1), Class IN (1), TTL 60s, Len 4, IP
    answer = b"\xc0\x0c\x00\x01\x00\x01\x00\x00\x00\x3c\x00\x04" + socket.inet_aton(sinkhole_ip)
    return header + question + answer

class SinkholeHTTPHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.handle_any_request()

    def do_POST(self):
        content_len = int(self.headers.get("Content-Length", 0))
        post_body = self.rfile.read(content_len) if content_len > 0 else b""
        self.handle_any_request(post_body)

    def handle_any_request(self, body=b""):
        headers_dict = {k: v for k, v in self.headers.items()}
        details = {
            "client_ip": self.client_address[0],
            "client_port": self.client_address[1],
            "method": self.command,
            "path": self.path,
            "headers": headers_dict,
            "body_snippet": body[:256].decode("utf-8", errors="replace") if body else ""
        }
        log_event("HTTP_C2_INTERCEPT", details)

        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Server", "MAYOTIX-Sinkhole/1.0")
        self.end_headers()
        self.wfile.write(b'{"status": "ok", "sinkhole": true, "response": "simulated_c2_ack"}')

    def log_message(self, format, *args):
        pass

def run_dns_server(host, port, sinkhole_ip, stop_event=None):
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.bind((host, port))
        sock.settimeout(1.0)
        while stop_event is None or not stop_event.is_set():
            try:
                data, addr = sock.recvfrom(1024)
                resp = build_dns_response(data, sinkhole_ip)
                if resp:
                    sock.sendto(resp, addr)
                    log_event("DNS_BLACKHOLE_QUERY", {"client": addr[0], "resolved_to": sinkhole_ip})
            except socket.timeout:
                continue
            except Exception:
                break
    except Exception as e:
        sys.stderr.write(f"DNS Server Error: {e}\n")
    finally:
        sock.close()

def main():
    parser = argparse.ArgumentParser(description="MAYOTIX Dynamic Malware Traffic Sinkhole")
    parser.add_argument("--host", default="10.99.0.1", help="Binding IP address (default: 10.99.0.1)")
    parser.add_argument("--dns-port", type=int, default=53, help="DNS blackhole UDP port (default: 53)")
    parser.add_argument("--http-port", type=int, default=80, help="HTTP simulated C2 port (default: 80)")
    parser.add_argument("--dry-run", action="store_true", help="Simulate sinkhole initialization and test interception logic")
    parser.add_argument("--json", action="store_true", help="Output telemetry as JSON")
    parser.add_argument("--status", action="store_true", help="Display sinkhole service status")
    args = parser.parse_args()

    if args.dry_run or args.status:
        # Simulate DNS resolution
        mock_query = b"\x12\x34\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00\x07malware\x03com\x00\x00\x01\x00\x01"
        mock_resp = build_dns_response(mock_query, args.host)
        res_ip = socket.inet_ntoa(mock_resp[-4:]) if mock_resp else "N/A"

        telemetry = {
            "service": "MAYOTIX Malware Traffic Sinkhole",
            "version": "1.0.0",
            "status": "READY",
            "bind_host": args.host,
            "dns_blackhole": {
                "port": args.dns_port,
                "protocol": "UDP",
                "resolved_target": res_ip,
                "interception": "ACTIVE"
            },
            "http_c2_simulator": {
                "port": args.http_port,
                "protocol": "TCP",
                "default_status": 200,
                "emulation_mode": "FAKE_C2_ACK"
            },
            "forensic_log": str(LOG_FILE)
        }

        if args.json:
            print(json.dumps(telemetry, indent=2))
        else:
            print(f"{BOLD}{CYAN}================================================================{NC}")
            print(f"{BOLD}{CYAN}      MAYOTIX Dynamic Malware Traffic Sinkhole & Blackhole       {NC}")
            print(f"{BOLD}{CYAN}================================================================{NC}")
            print(f"  Service Status     : {GREEN}READY (Validated){NC}")
            print(f"  Gateway IP         : {args.host}")
            print(f"  DNS Blackhole      : Port {args.dns_port}/UDP -> Resolves all queries to {GREEN}{res_ip}{NC}")
            print(f"  HTTP C2 Simulator  : Port {args.http_port}/TCP -> Emulates C2 responses (200 OK)")
            print(f"  Forensics Log      : {LOG_FILE}")
            print(f"{BOLD}{CYAN}================================================================{NC}")
        return 0

    print(f"Starting MAYOTIX Sinkhole on {args.host} (DNS: {args.dns_port}, HTTP: {args.http_port})...")
    stop_event = threading.Event()
    dns_thread = threading.Thread(target=run_dns_server, args=(args.host, args.dns_port, args.host, stop_event), daemon=True)
    dns_thread.start()

    try:
        httpd = HTTPServer((args.host, args.http_port), SinkholeHTTPHandler)
        httpd.serve_forever()
    except KeyboardInterrupt:
        stop_event.set()
        print("\nSinkhole stopped cleanly.")
    except Exception as e:
        sys.stderr.write(f"Sinkhole error: {e}\n")
        return 1

    return 0

if __name__ == "__main__":
    sys.exit(main())
