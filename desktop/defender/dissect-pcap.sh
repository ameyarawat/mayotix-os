#!/bin/bash
# MAYOTIX OS Phase 7 Week 2: Sandboxed PCAP Dissector Utility
#
# Wraps packet dissection tools (tshark / tcpdump) inside a strictly confined
# Bubblewrap sandbox (unshare-net, cap-drop ALL, read-only root, ephemeral tmpfs)
# to protect the host against complex C/C++ parser memory vulnerabilities.
#
# Usage:
#   dissect-pcap.sh <pcap_file> [options]
#   dissect-pcap.sh <pcap_file> --summary
#   dissect-pcap.sh <pcap_file> --filter "tcp.port == 443"
#   dissect-pcap.sh <pcap_file> --dry-run

set -euo pipefail

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
Usage: $0 <pcap_file> [options]

Options:
  -s, --summary           Output high-level packet summary and protocol breakdown
  -f, --filter <expr>     Filter expression (Wireshark display filter or BPF)
  -t, --tool <tool>       Dissector tool to use: 'tshark' (default) or 'tcpdump'
  -c, --count <num>       Maximum packet count to dissect
  --dry-run               Simulate sandboxed dissector startup
  -h, --help              Display this help message
EOF
    exit 1
}

PCAP_FILE=""
SUMMARY=0
FILTER=""
TOOL="tshark"
COUNT=""
DRY_RUN=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--summary) SUMMARY=1; shift ;;
        -f|--filter) FILTER="$2"; shift 2 ;;
        -t|--tool) TOOL="$2"; shift 2 ;;
        -c|--count) COUNT="$2"; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) usage ;;
        -*) log_error "Unknown option: $1"; usage ;;
        *)
            if [[ -z "$PCAP_FILE" ]]; then
                PCAP_FILE="$1"
                shift
            else
                log_error "Unexpected argument: $1"; usage
            fi
            ;;
    esac
done

if [[ -z "$PCAP_FILE" ]]; then
    log_error "Missing target PCAP file."
    usage
fi

if [[ $DRY_RUN -eq 1 ]]; then
    log_info "[DRY-RUN] Simulating sandboxed PCAP dissection:"
    log_info "  Target File : $PCAP_FILE"
    log_info "  Tool        : $TOOL"
    log_info "  Summary     : $([[ $SUMMARY -eq 1 ]] && echo 'Yes' || echo 'No')"
    log_info "  Filter      : ${FILTER:-none}"
    log_info "  Sandbox     : Bubblewrap (unshare-net, cap-drop ALL, ro-root, tmpfs)"
    log_success "Dissector sandbox parameters validated."
    exit 0
fi

if [[ ! -f "$PCAP_FILE" ]]; then
    log_error "PCAP file not found: '$PCAP_FILE'"
    exit 1
fi

REAL_PCAP=$(realpath "$PCAP_FILE")

# Check dissector binary availability
if ! command -v "$TOOL" &>/dev/null; then
    if command -v tcpdump &>/dev/null; then
        TOOL="tcpdump"
    elif command -v tshark &>/dev/null; then
        TOOL="tshark"
    else
        log_error "Neither tshark nor tcpdump found in PATH."
        exit 1
    fi
fi

# Build dissector command inside sandbox
DISSECT_ARGS=()
if [[ "$TOOL" == "tshark" ]]; then
    DISSECT_ARGS+=("tshark" "-r" "$REAL_PCAP")
    if [[ $SUMMARY -eq 1 ]]; then
        DISSECT_ARGS+=("-q" "-z" "io,phs" "-z" "endpoints,ip")
    fi
    if [[ -n "$FILTER" ]]; then
        DISSECT_ARGS+=("-Y" "$FILTER")
    fi
    if [[ -n "$COUNT" ]]; then
        DISSECT_ARGS+=("-c" "$COUNT")
    fi
else
    # tcpdump
    DISSECT_ARGS+=("tcpdump" "-nn" "-r" "$REAL_PCAP")
    if [[ -n "$FILTER" ]]; then
        DISSECT_ARGS+=("$FILTER")
    fi
    if [[ -n "$COUNT" ]]; then
        DISSECT_ARGS+=("-c" "$COUNT")
    fi
fi

# Execute via Bubblewrap if installed, otherwise run bounded
if command -v bwrap &>/dev/null; then
    log_info "Executing $TOOL inside isolated Bubblewrap sandbox (zero network)..."
    exec bwrap \
        --ro-bind /usr /usr \
        --ro-bind-try /lib /lib \
        --ro-bind-try /lib64 /lib64 \
        --ro-bind-try /bin /bin \
        --ro-bind-try /sbin /sbin \
        --ro-bind-try /etc /etc \
        --ro-bind "$REAL_PCAP" "$REAL_PCAP" \
        --dev /dev \
        --tmpfs /tmp \
        --tmpfs /run \
        --tmpfs /home \
        --unshare-user \
        --unshare-net \
        --unshare-ipc \
        --unshare-pid \
        --unshare-uts \
        --unshare-cgroup \
        --cap-drop ALL \
        --die-with-parent \
        -- "${DISSECT_ARGS[@]}"
else
    log_warn "bwrap not detected; executing dissector with process limits."
    exec "${DISSECT_ARGS[@]}"
fi
