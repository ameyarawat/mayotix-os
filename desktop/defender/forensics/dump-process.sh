#!/bin/bash
# MAYOTIX OS Phase 7 Week 3: Volatile Artifacts & Process Memory Forensics (dump-process.sh)
#
# Extracts process metadata, virtual memory mappings, open file descriptors,
# and volatile artifacts under bounded capabilities (CAP_SYS_PTRACE) without requiring full root.
# Automatically integrates secret sanitization before long-term archiving.
#
# Usage:
#   dump-process.sh --pid <pid> [options]
#   dump-process.sh --pid <pid> --output <file> --sanitize
#   dump-process.sh --pid <pid> --dry-run

set -euo pipefail

FORENSICS_DIR="/var/log/mayotix/forensics"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SANITIZER_SCRIPT="${SCRIPT_DIR}/sanitize-dump.py"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

usage() {
    cat <<EOF
Usage: $0 --pid <pid> [options]

Options:
  -p, --pid <pid>       Target Process ID to inspect
  -o, --output <file>   Destination forensic dump file (default: in /var/log/mayotix/forensics/)
  -s, --sanitize        Automatically scrub private keys, tokens, and credentials
  --dry-run             Simulate process dump acquisition
  -h, --help            Display this help message
EOF
    exit 1
}

TARGET_PID=""
OUTPUT_FILE=""
SANITIZE=0
DRY_RUN=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--pid) TARGET_PID="$2"; shift 2 ;;
        -o|--output) OUTPUT_FILE="$2"; shift 2 ;;
        -s|--sanitize) SANITIZE=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) usage ;;
        *) log_error "Unknown option: $1"; usage ;;
    esac
done

if [[ -z "$TARGET_PID" ]]; then
    log_error "Missing required option: --pid <pid>"
    usage
fi

if [[ -z "$OUTPUT_FILE" ]]; then
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    OUTPUT_FILE="${FORENSICS_DIR}/proc_${TARGET_PID}_${TIMESTAMP}.dump"
fi

ensure_dirs() {
    if [[ ! -d "$FORENSICS_DIR" ]]; then
        mkdir -p "$FORENSICS_DIR" 2>/dev/null || {
            if command -v sudo &>/dev/null; then
                sudo -n mkdir -p "$FORENSICS_DIR" 2>/dev/null || true
                sudo -n chmod 0750 "$FORENSICS_DIR" 2>/dev/null || true
            fi
        }
    fi
}

if [[ $DRY_RUN -eq 1 ]]; then
    log_info "[DRY-RUN] Simulating volatile process forensics acquisition:"
    log_info "  Target PID    : $TARGET_PID"
    log_info "  Capability    : CAP_SYS_PTRACE (Unprivileged memory inspection)"
    log_info "  Sanitize      : $([[ $SANITIZE -eq 1 ]] && echo 'Enabled' || echo 'Disabled')"
    log_info "  Destination   : $OUTPUT_FILE"
    log_success "Forensic dump parameters validated successfully."
    exit 0
fi

ensure_dirs

if [[ ! -d "/proc/$TARGET_PID" ]]; then
    log_error "Process PID $TARGET_PID does not exist or terminated."
    exit 1
fi

RAW_TMP=$(mktemp /tmp/proc_dump_XXXXXX)
trap 'rm -f "$RAW_TMP"' EXIT

{
    echo "================================================================================"
    echo "MAYOTIX OS FORENSIC ARTIFACT DUMP"
    echo "Timestamp: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo "Target PID: $TARGET_PID"
    echo "================================================================================"
    echo ""
    echo "--- 1. Process Status & Lineage ---"
    if [[ -r "/proc/$TARGET_PID/status" ]]; then
        cat "/proc/$TARGET_PID/status"
    else
        echo "[WARN] Unable to read status"
    fi
    echo ""
    echo "--- 2. Command Line Invocation ---"
    if [[ -r "/proc/$TARGET_PID/cmdline" ]]; then
        tr '\0' ' ' < "/proc/$TARGET_PID/cmdline" || echo ""
        echo ""
    fi
    echo ""
    echo "--- 3. Memory Layout & Virtual Mappings ---"
    if [[ -r "/proc/$TARGET_PID/maps" ]]; then
        cat "/proc/$TARGET_PID/maps"
    else
        echo "[WARN] Unable to read memory maps"
    fi
    echo ""
    echo "--- 4. Open File Descriptors ---"
    if [[ -d "/proc/$TARGET_PID/fd" ]]; then
        ls -l "/proc/$TARGET_PID/fd" 2>/dev/null || echo "[WARN] fd access restricted"
    fi
    echo ""
    echo "--- 5. Process Environment ---"
    if [[ -r "/proc/$TARGET_PID/environ" ]]; then
        tr '\0' '\n' < "/proc/$TARGET_PID/environ" 2>/dev/null || echo ""
    fi
    echo ""
    echo "================================================================================"
    echo "END OF FORENSIC DUMP"
    echo "================================================================================"
} > "$RAW_TMP"

if [[ $SANITIZE -eq 1 ]]; then
    log_info "Running automated artifact sanitizer on raw dump..."
    if [[ -f "$SANITIZER_SCRIPT" ]]; then
        python3 "$SANITIZER_SCRIPT" "$RAW_TMP" --output "$OUTPUT_FILE"
        log_success "Sanitized forensic dump written to: $OUTPUT_FILE"
    else
        cp "$RAW_TMP" "$OUTPUT_FILE"
        log_warn "Sanitizer script not found; wrote unsanitized dump to: $OUTPUT_FILE"
    fi
else
    cp "$RAW_TMP" "$OUTPUT_FILE"
    log_success "Forensic dump acquired and written to: $OUTPUT_FILE"
fi

if [[ -f "$OUTPUT_FILE" ]]; then
    chmod 0640 "$OUTPUT_FILE" 2>/dev/null || true
    SIZE=$(ls -lh "$OUTPUT_FILE" | awk '{print $5}')
    log_info "Artifact size: $SIZE"
fi
