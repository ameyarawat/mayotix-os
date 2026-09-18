#!/usr/bin/env bash
# MAYOTIX OS Phase 8 Week 1: Automated Incident Response Triage Snapshot Engine
#
# Collects high-fidelity host triage telemetry during security incidents:
#   - Active network connections and listening sockets (ss, ip route, ip addr)
#   - Full process execution tree and parent-child lineage (ps auxf)
#   - Kernel taint status, security mitigations, and loaded module manifests (lsmod)
#   - Recent SELinux MAC policy AVC denials and audit log events
#   - Failed systemd units and unexpected services
#
# Generates a tamper-evident, SHA-256 hashed tarball archive in /var/log/mayotix/incident/
#
# Usage:
#   triage-snapshot.sh [--output <path>] [--dry-run] [--json]

set -euo pipefail

PROGNAME="triage-snapshot"
INCIDENT_DIR="/var/log/mayotix/incident"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DEFAULT_ARCHIVE="${INCIDENT_DIR}/triage_${TIMESTAMP}.tar.gz"

# Terminal Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

OUTPUT_PATH=""
DRY_RUN=0
JSON_OUT=0

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        -o|--output) OUTPUT_PATH="$2"; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        --json) JSON_OUT=1; shift ;;
        --help|-h)
            echo "Usage: $PROGNAME [options]"
            echo ""
            echo "Options:"
            echo "  -o, --output <path>   Destination path for triage tarball"
            echo "  --dry-run             Simulate host triage collection without writing files"
            echo "  --json                Output triage manifest and checksums as JSON"
            exit 0
            ;;
        *) log_warn "Unknown option: $1"; shift ;;
    esac
done

if [[ -z "$OUTPUT_PATH" ]]; then
    OUTPUT_PATH="$DEFAULT_ARCHIVE"
fi

if [[ $DRY_RUN -eq 1 ]]; then
    MOCK_HASH="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    if [[ $JSON_OUT -eq 1 ]]; then
        cat <<EOF
{
  "triage_session": "simulated_triage_${TIMESTAMP}",
  "timestamp": $(date +%s),
  "archive_file": "$OUTPUT_PATH",
  "sha256_checksum": "$MOCK_HASH",
  "status": "COMPLETED",
  "collected_artifacts": [
    "network_sockets.txt",
    "process_tree.txt",
    "kernel_state.txt",
    "selinux_avc_denials.txt",
    "systemd_failed_units.txt",
    "manifest.json"
  ],
  "metrics": {
    "active_sockets_captured": 42,
    "processes_enumerated": 128,
    "kernel_taint_value": 0,
    "avc_denials_found": 0
  }
}
EOF
    else
        echo -e "${BOLD}${CYAN}================================================================${NC}"
        echo -e "${BOLD}${CYAN}      MAYOTIX OS Incident Response: Automated Triage Snapshot   ${NC}"
        echo -e "${BOLD}${CYAN}================================================================${NC}"
        echo -e "  [DRY-RUN] Simulating Full Host Triage Collection:"
        echo -e "    - Network Sockets & Routing   : ${GREEN}Captured (ss, ip route, ip addr)${NC}"
        echo -e "    - Process Hierarchy & Trees   : ${GREEN}Captured (ps auxf)${NC}"
        echo -e "    - Kernel Taint & Modules      : ${GREEN}Captured (/proc/sys/kernel/tainted, lsmod)${NC}"
        echo -e "    - SELinux AVC Audit Events    : ${GREEN}Captured (ausearch / audit.log)${NC}"
        echo -e "    - Systemd Health & Services   : ${GREEN}Captured (systemctl --failed)${NC}"
        echo -e "  Target Archive  : $OUTPUT_PATH"
        echo -e "  SHA-256 Hash    : $MOCK_HASH"
        echo -e "${BOLD}${CYAN}================================================================${NC}"
        log_success "Incident response triage simulation completed successfully."
    fi
    exit 0
fi

# Live execution
mkdir -p "$INCIDENT_DIR"
chmod 0750 "$INCIDENT_DIR" 2>/dev/null || true

WORK_DIR=$(mktemp -d "/tmp/mayotix_triage_${TIMESTAMP}.XXXXXX")
cleanup() {
    rm -rf "$WORK_DIR" 2>/dev/null || true
}
trap cleanup EXIT

log_info "Collecting live incident response telemetry..."

# 1. Network sockets & routing
{
    echo "=== Network Interfaces ==="
    ip -br addr 2>/dev/null || ifconfig -a 2>/dev/null || echo "N/A"
    echo ""
    echo "=== Routing Table ==="
    ip route 2>/dev/null || netstat -rn 2>/dev/null || echo "N/A"
    echo ""
    echo "=== Open & Listening Sockets ==="
    ss -tulpn 2>/dev/null || netstat -tulpen 2>/dev/null || echo "N/A"
} > "${WORK_DIR}/network_sockets.txt"

# 2. Process hierarchy
{
    echo "=== Process Hierarchy Tree ==="
    ps auxf 2>/dev/null || ps -ef 2>/dev/null || echo "N/A"
} > "${WORK_DIR}/process_tree.txt"

# 3. Kernel state & taint
{
    echo "=== Kernel Version & Taint ==="
    uname -a
    echo "Taint Status: $(cat /proc/sys/kernel/tainted 2>/dev/null || echo '0')"
    echo ""
    echo "=== Loaded Kernel Modules ==="
    lsmod 2>/dev/null || echo "N/A"
} > "${WORK_DIR}/kernel_state.txt"

# 4. SELinux AVC denials
{
    echo "=== SELinux Status ==="
    getenforce 2>/dev/null || echo "N/A"
    echo ""
    echo "=== Recent AVC Denials ==="
    if command -v ausearch &>/dev/null; then
        ausearch -m avc -ts recent 2>/dev/null || echo "No recent AVC denials."
    elif [[ -f /var/log/audit/audit.log ]]; then
        grep -i "avc:.*denied" /var/log/audit/audit.log 2>/dev/null | tail -n 50 || echo "No AVC denials found."
    else
        echo "Audit logs not accessible."
    fi
} > "${WORK_DIR}/selinux_avc_denials.txt"

# 5. Failed systemd services
{
    echo "=== Failed Systemd Units ==="
    systemctl --failed --no-legend 2>/dev/null || echo "None"
} > "${WORK_DIR}/systemd_failed_units.txt"

# 6. Manifest
cat > "${WORK_DIR}/manifest.json" <<EOF
{
  "triage_id": "triage_${TIMESTAMP}",
  "timestamp": $(date +%s),
  "os": "MAYOTIX OS 5.0-alpha",
  "kernel": "$(uname -r)",
  "collector": "triage-snapshot.sh"
}
EOF

# Package archive
tar -czf "$OUTPUT_PATH" -C "$WORK_DIR" .
chmod 0640 "$OUTPUT_PATH"

# Compute SHA-256
SHA256=$(sha256sum "$OUTPUT_PATH" | awk '{print $1}')
echo "$SHA256  $(basename "$OUTPUT_PATH")" > "${OUTPUT_PATH}.sha256"

if [[ $JSON_OUT -eq 1 ]]; then
    cat <<EOF
{
  "triage_session": "triage_${TIMESTAMP}",
  "timestamp": $(date +%s),
  "archive_file": "$OUTPUT_PATH",
  "sha256_checksum": "$SHA256",
  "status": "COMPLETED"
}
EOF
else
    log_success "Incident triage archive generated: $OUTPUT_PATH"
    log_info "  SHA-256 Checksum: $SHA256"
fi
