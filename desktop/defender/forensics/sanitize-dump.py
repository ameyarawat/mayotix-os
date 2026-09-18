#!/usr/bin/env python3
"""
MAYOTIX OS Phase 7 Week 3: Forensic Dump Sanitizer (sanitize-dump.py)

Redacts cryptographic private keys, authentication tokens, API keys, passwords,
and sensitive environment variables from process memory dumps and crash artifacts.

Usage:
  sanitize-dump.py <input_dump> [--output <output_file>] [--json]
  sanitize-dump.py --dry-run [--json]
"""

import sys
import os
import re
import json
import argparse
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

# Terminal Colors
CYAN = "\033[0;36m"
GREEN = "\033[0;32m"
YELLOW = "\033[1;33m"
RED = "\033[0;31m"
BOLD = "\033[1m"
NC = "\033[0m"

# Regex Patterns for Sensitive Secrets
SECRET_PATTERNS = [
    # PEM Private Keys
    (r"-----BEGIN (?:RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----[\s\S]*?-----END (?:RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----", "[REDACTED_PRIVATE_KEY]"),
    # JWT Tokens
    (r"eyJ[a-zA-Z0-9_-]{10,}\.eyJ[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9_-]{10,}", "[REDACTED_JWT_TOKEN]"),
    # Bearer Tokens
    (r"(?i)bearer\s+[a-zA-Z0-9_\-\.]{16,}", "Bearer [REDACTED_BEARER_TOKEN]"),
    # GitHub / GitLab Personal Access Tokens
    (r"ghp_[a-zA-Z0-9]{36}", "[REDACTED_GITHUB_TOKEN]"),
    (r"glpat-[a-zA-Z0-9_-]{20,}", "[REDACTED_GITLAB_TOKEN]"),
    # AWS Access Key IDs
    (r"AKIA[0-9A-Z]{16}", "[REDACTED_AWS_KEY]"),
    # WireGuard base64 private keys (44 chars ending in =) in configs or memory
    (r"(?i)(?:PrivateKey|PresharedKey)\s*=\s*[A-Za-z0-9+/]{43}=", r"\1 = [REDACTED_WIREGUARD_KEY]"),
    # Generic password / secret / token environment variables and config lines
    (r"(?i)(password|passwd|secret|api_key|access_token|auth_token)\s*([=:])\s*['\"]?[^\s'\"]{6,}['\"]?", r"\1\2[REDACTED_CREDENTIAL]")
]

def sanitize_content(content):
    """Applies all secret redaction patterns to the given text."""
    redacted_content = content
    redaction_counts = {}

    for pattern, replacement in SECRET_PATTERNS:
        matches = re.findall(pattern, redacted_content)
        if matches:
            count = len(matches)
            redaction_counts[replacement] = redaction_counts.get(replacement, 0) + count
            redacted_content = re.sub(pattern, replacement, redacted_content)

    return redacted_content, redaction_counts

def main():
    parser = argparse.ArgumentParser(description="MAYOTIX Forensic Artifact & Memory Dump Sanitizer")
    parser.add_argument("input_file", nargs="?", default="", help="Path to raw dump file to sanitize")
    parser.add_argument("-o", "--output", default="", help="Destination sanitized dump file (default: overwrite or stdout)")
    parser.add_argument("--json", action="store_true", help="Output summary report formatted as JSON")
    parser.add_argument("--dry-run", action="store_true", help="Simulate redaction on mock artifact")

    args = parser.parse_args()

    if args.dry_run:
        sample_text = (
            "Environment:\n"
            "USER=oggy\n"
            "API_KEY=sample_mock_api_secret_key_12345\n"
            "PASSWORD=supersecretpassword123\n"
            "Authorization: Bearer secret_bearer_token_value_9876543210\n"
            "-----BEGIN PRIVATE KEY-----\nMIIEvgIBADANBgkqhkiG9w0BAQEFAASC...\n-----END PRIVATE KEY-----\n"
        )
        redacted, counts = sanitize_content(sample_text)
        res = {
            "dry_run": True,
            "total_redactions": sum(counts.values()),
            "details": counts,
            "sample_redacted_preview": redacted
        }
        if args.json:
            print(json.dumps(res, indent=2))
        else:
            print(f"{BOLD}{GREEN}[✓] Sanitizer Simulation Completed Successfully:{NC}")
            print(f"    Total Secrets Redacted: {res['total_redactions']}")
            for k, v in counts.items():
                print(f"      - {k}: {v}")
            print(f"\n{BOLD}Sanitized Output Preview:{NC}\n{redacted}")
        return 0

    if not args.input_file:
        parser.print_help()
        return 1

    if not os.path.exists(args.input_file):
        sys.stderr.write(f"{RED}Error:{NC} Input file not found: {args.input_file}\n")
        return 1

    with open(args.input_file, "r", encoding="utf-8", errors="replace") as f:
        raw_content = f.read()

    sanitized, counts = sanitize_content(raw_content)
    total_redacted = sum(counts.values())

    output_path = args.output if args.output else args.input_file
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(sanitized)

    if args.json:
        print(json.dumps({
            "input_file": args.input_file,
            "output_file": output_path,
            "total_redactions": total_redacted,
            "redactions_breakdown": counts
        }, indent=2))
    else:
        print(f"{GREEN}[✓]{NC} Sanitized '{args.input_file}' -> '{output_path}'")
        print(f"    Scrubbed {total_redacted} sensitive secrets.")
        for secret_type, count in counts.items():
            print(f"      - {secret_type}: {count}")

    return 0

if __name__ == "__main__":
    sys.exit(main())
