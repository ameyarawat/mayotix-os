#!/usr/bin/env bash
# MAYOTIX OS Phase 4: Dev Container Lifecycle Audit & Monitoring Hook
# Records container creation, entry, execution, and termination events to journald/syslog and audit log.
#
# Usage:
#   devbox-audit-hook.sh --action <CREATE|START|ENTER|EXEC|STOP|TERMINATE|REMOVE> \
#                        --name <container-name> \
#                        --image <image-name> \
#                        [--ephemeral <true|false>] \
#                        [--network <net-mode>] \
#                        [--workspace <path>] \
#                        [--exit-code <code>] \
#                        [--details <json-or-text>]

set -euo pipefail

PROGNAME="mayotix-devbox-audit"

# Resolve log file paths
LOG_DIR="${MAYOTIX_AUDIT_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/mayotix}"
AUDIT_LOG="${LOG_DIR}/devbox-audit.log"
SYSTEM_LOG_TAG="mayotix-devbox"

ACTION=""
CONTAINER_NAME=""
IMAGE_NAME="unknown"
EPHEMERAL="false"
NETWORK_MODE="default"
WORKSPACE_PATH=""
EXIT_CODE="0"
DETAILS=""

# Parse CLI options
while [[ $# -gt 0 ]]; do
    case "$1" in
        --action)
            ACTION="$2"
            shift 2
            ;;
        --name)
            CONTAINER_NAME="$2"
            shift 2
            ;;
        --image)
            IMAGE_NAME="$2"
            shift 2
            ;;
        --ephemeral)
            EPHEMERAL="$2"
            shift 2
            ;;
        --network)
            NETWORK_MODE="$2"
            shift 2
            ;;
        --workspace)
            WORKSPACE_PATH="$2"
            shift 2
            ;;
        --exit-code)
            EXIT_CODE="$2"
            shift 2
            ;;
        --details)
            DETAILS="$2"
            shift 2
            ;;
        --list|--read)
            # Query recent audit log entries
            if [[ -f "$AUDIT_LOG" ]]; then
                tail -n 50 "$AUDIT_LOG"
            else
                echo "No audit log found at ${AUDIT_LOG}"
            fi
            exit 0
            ;;
        --help|-h)
            cat <<EOF
Usage: $0 [OPTIONS]
  --action <ACTION>      Lifecycle action (CREATE, START, ENTER, EXEC, STOP, TERMINATE, REMOVE)
  --name <NAME>          Container name
  --image <IMAGE>        Container image
  --ephemeral <BOOL>     Whether container is ephemeral (true/false)
  --network <MODE>       Network isolation mode
  --workspace <PATH>     Mounted workspace path
  --exit-code <CODE>     Exit status code
  --details <TEXT>       Additional event metadata
  --list                 View recent audit logs
EOF
            exit 0
            ;;
        *)
            echo "[$PROGNAME] Unknown argument: $1" >&2
            shift
            ;;
    esac
done

if [[ -z "${ACTION}" || -z "${CONTAINER_NAME}" ]]; then
    echo "[$PROGNAME] ERROR: --action and --name are required." >&2
    exit 1
fi

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EVENT_USER="${USER:-$(whoami)}"
EVENT_UID="$(id -u 2>/dev/null || echo 1000)"
CALLER_PID="$$"

# Format structured JSON audit record
AUDIT_ENTRY=$(cat <<EOF
{"timestamp":"${TIMESTAMP}","event":"DEVBOX_${ACTION^^}","container":"${CONTAINER_NAME}","image":"${IMAGE_NAME}","user":"${EVENT_USER}","uid":${EVENT_UID},"pid":${CALLER_PID},"ephemeral":${EPHEMERAL},"network":"${NETWORK_MODE}","workspace":"${WORKSPACE_PATH}","exit_code":${EXIT_CODE},"details":"${DETAILS}"}
EOF
)

# 1. Forward to system journal / syslog if logger is available
if command -v logger >/dev/null 2>&1; then
    logger -t "${SYSTEM_LOG_TAG}" -p user.info -- "${AUDIT_ENTRY}" || true
fi

# 2. Append to local persistent audit log
mkdir -p "$LOG_DIR" 2>/dev/null || true
if [[ -d "$LOG_DIR" && -w "$LOG_DIR" ]]; then
    echo "${AUDIT_ENTRY}" >> "$AUDIT_LOG"
elif [[ -w "/tmp" ]]; then
    # Fallback to /tmp if state dir not writable
    echo "${AUDIT_ENTRY}" >> "/tmp/mayotix-devbox-audit.log"
fi

exit 0
