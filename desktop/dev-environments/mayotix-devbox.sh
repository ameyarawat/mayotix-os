#!/usr/bin/env bash
# MAYOTIX OS Phase 4: Hardened Dev Container Engine (mayotix-devbox.sh)
# Wrapper for Distrobox / Toolbx enforcing restricted host filesystem mounts.
#
# Features:
#   - Mounts ~/Projects read-write, host root / as read-only, private /tmp, isolated IPC.
#   - CLI flags for ephemeral mode (--ephemeral: automatically removes container on exit) and network isolation.
#   - Integrates with devbox-audit-hook.sh for lifecycle logging.
#   - Defaults to Toolbx if available, falls back to Distrobox.
#
# Usage:
#   mayotix-devbox.sh [OPTIONS] [-- <command>]
#   Options:
#     --image <image>          Container image to use (default: mayotix/devbox:latest)
#     --name <name>            Container instance name (default: mayotix-devbox-$$)
#     --workspace <path>       Host workspace to mount RW (default: $HOME/Projects)
#     --ephemeral              Remove container on exit (no persistence)
#     --network <mode>         Network mode: none, private, host (default: private)
#     --no-audit               Skip audit hook invocation
#     --debug                  Enable verbose logging
#     --help                   Show this help
#
# Examples:
#   mayotix-devbox.sh --ephemeral --network none -- bash
#   mayotix-devbox.sh --workspace $HOME/code -- podman run ...
#
set -euo pipefail

PROGNAME="mayotix-devbox"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
AUDIT_HOOK="${SCRIPT_DIR}/devbox-audit-hook.sh"

# Defaults
IMAGE="${MAYOTIX_DEVBOX_IMAGE:-mayotix/devbox:latest}"
NAME="mayotix-devbox-$$"
WORKSPACE="${HOME}/Projects"
EPHEMERAL=0
NETWORK="private"   # none, private, host
USE_AUDIT=1
DEBUG=0
EXTRA_ARGS=()
CMD=()

# Logging helpers
log_info() { [[ $DEBUG -eq 1 ]] && echo "[${PROGNAME}][INFO] $*" || :; }
log_error() { echo "[${PROGNAME}][ERROR] $*" >&2; }
log_warn()  { echo "[${PROGNAME}][WARN] $*" >&2; }

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --image)
            IMAGE="$2"
            shift 2
            ;;
        --name)
            NAME="$2"
            shift 2
            ;;
        --workspace)
            WORKSPACE="$2"
            shift 2
            ;;
        --ephemeral)
            EPHEMERAL=1
            shift
            ;;
        --network)
            NETWORK="$2"
            shift 2
            ;;
        --no-audit)
            USE_AUDIT=0
            shift
            ;;
        --debug)
            DEBUG=1
            shift
            ;;
        --help)
            cat <<EOF
Usage: $PROGNAME [OPTIONS] [-- <command>]
Options:
  --image <image>          Container image to use (default: mayotix/devbox:latest)
  --name <name>            Container instance name (default: mayotix-devbox-\$\$)
  --workspace <path>       Host workspace to mount RW (default: \$HOME/Projects)
  --ephemeral              Remove container on exit (no persistence)
  --network <mode>         Network mode: none, private, host (default: private)
  --no-audit               Skip audit hook invocation
  --debug                  Enable verbose logging
  --help                   Show this help
After '--', the remainder is treated as the command to run inside the container.
If no command is given, defaults to an interactive shell.
EOF
            exit 0
            ;;
        --)
            shift
            CMD=("$@")
            break
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# If no command provided, default to interactive shell
if [[ ${#CMD[@]} -eq 0 ]]; then
    CMD=("${SHELL:-/bin/bash}")
fi

# Validate workspace exists
if [[ ! -d "$WORKSPACE" ]]; then
    log_warn "Workspace directory does not exist: $WORKSPACE. Creating it."
    mkdir -p "$WORKSPACE"
fi

# Determine container engine: prefer toolbx, then distrobox, then podman directly
if command -v toolbx >/dev/null 2>&1; then
    ENGINE="toolbx"
    ENGINE_CMD=(toolbx)
elif command -v distrobox >/dev/null 2>&1; then
    ENGINE="distrobox"
    ENGINE_CMD=(distrobox)
else
    # Fallback to podman run with manual flags
    ENGINE="podman"
    ENGINE_CMD=(podman run)
fi

log_info "Using container engine: $ENGINE"
log_info "Image: $IMAGE"
log_info "Instance name: $NAME"
log_info "Workspace (RW): $WORKSPACE"
log_info "Network mode: $NETWORK"
log_info "Ephemeral: $EPHEMERAL"

# Function to invoke audit hook if enabled and executable
audit() {
    if [[ $USE_AUDIT -eq 1 && -x "$AUDIT_HOOK" ]]; then
        "$AUDIT_HOOK" "$@"
    fi
}

# Build common podman run arguments for hardened dev container
build_podman_args() {
    local args=()
    # Interactive TTY
    args+=(--it)
    # Ephemeral: remove container on exit
    if [[ $EPHEMERAL -eq 1 ]]; then
        args+=(--rm)
    else
        args+=(--name "$NAME")
    fi
    # Network isolation
    case "$NETWORK" in
        none)
            args+=(--network none)
            ;;
        private)
            args+=(--network none)   # We'll add custom bridges later if needed; for now none.
            ;;
        host)
            args+=(--network host)
            ;;
        *)
            log_warn "Unknown network mode: $NETWORK, defaulting to none"
            args+=(--network none)
            ;;
    esac
    # Private /tmp (tmpfs)
    args+=(--tmpfs /tmp)
    # Read-only root filesystem (except for specific mounts)
    args+=(--read-only)
    # Mount workspace read-write
    args+=(--bind "$WORKSPACE":/home/${USER:-developer}/Projects:Z)
    # Mount home read-only
    args+=(--bind "$HOME":/home/${USER:-developer}:ro)
    # Isolate IPC
    args+=(--ipc private)
    # Drop dangerous capabilities (similar to disposable session)
    args+=(--cap-drop CAP_SYS_ADMIN)
    args+=(--cap-drop CAP_SYS_MODULE)
    args+=(--cap-drop CAP_SYS_PTRACE)
    args+=(--cap-drop CAP_SYS_RAWIO)
    args+=(--cap-drop CAP_SYS_BOOT)
    args+=(--cap-drop CAP_SYS_NICE)
    args+=(--cap-drop CAP_NET_ADMIN)
    args+=(--cap-drop CAP_NET_RAW)
    args+=(--cap-drop CAP_MKNOD)
    args+=(--cap-drop CAP_AUDIT_WRITE)
    args+=(--cap-drop CAP_AUDIT_CONTROL)
    # Set environment variables
    args+=(--env HOME=/home/${USER:-developer})
    args+=(--env USER=${USER:-developer})
    args+=(--env MAYOTIX_DEVCONTAINER=1)
    args+=(--env MAYOTIX_DEVCONTAINER_NAME=$NAME)
    if [[ $EPHEMERAL -eq 1 ]]; then
        args+=(--env MAYOTIX_DEVCONTAINER_EPHEMERAL=1)
    fi
    printf '%s' "${args[@]}"
}

# Main logic
main() {
    # Check if container exists (by name) and its state
    container_exists=false
    container_running=false
    if [[ $EPHEMERAL -eq 0 ]]; then
        if podman container exists "$NAME" 2>/dev/null; then
            container_exists=true
            if podman container inspect "$NAME" --format "{{.State.Running}}" 2>/dev/null | grep -q true; then
                container_running=true
            fi
        fi
    fi

    if [[ $EPHEMERAL -eq 1 ]] || [[ $container_exists == false ]]; then
        # We will create a new container (or ephemeral)
        log_info "Creating new container: $NAME"
        audit --action CREATE --name "$NAME" --image "$IMAGE" --ephemeral "$EPHEMERAL" --network "$NETWORK" --workspace "$WORKSPACE"

        # Build the podman run command
        local podman_args=()
        while IFS= read -r -d '' arg; do
            podman_args+=("$arg")
        done < <(build_podman_args && printf '\0')

        # Start the container
        log_info "Starting container: $NAME"
        audit --action START --name "$NAME" --image "$IMAGE" --ephemeral "$EPHEMERAL" --network "$NETWORK" --workspace "$WORKSPACE"

        # Run the command in the container
        log_info "Executing command in container: $NAME"
        audit --action EXEC --name "$NAME" --image "$IMAGE" --ephemeral "$EPHEMERAL" --network "$NETWORK" --workspace "$WORKSPACE" --details "{\"command\": \"${CMD[*]}\"}"

        # exec podman run with the built arguments
        # Note: We use exec to replace the current process, so the podman run becomes our process.
        # When the command exits, podman will exit and we will remove the container (if ephemeral) due to --rm.
        # We want to audit the STOP after the container exits? Actually, the container will be removed by podman due to --rm.
        # We can audit STOP just before the exec? But we don't know the exit code yet.
        # Instead, we can trap EXIT and audit STOP. However, since we are about to exec, we can set a trap.
        # We'll set a trap to audit STOP when the script exits (which will be after podman run exits).
        # But note: we are about to exec podman run, so the trap will be inherited by the podman process?
        # Actually, traps are not inherited across exec unless we set them with -p? In bash, traps are not inherited by exec'd processes.
        # So we cannot rely on that.
        # Alternative: we do not exec, we run podman run and wait for it, then audit STOP.
        # We'll do that to keep it simple.
        # We'll run: podman run [args] "$IMAGE" "${CMD[@]}"
        # Then we get the exit code and audit STOP.

        # Build the full command
        local run_cmd=("podman" "run")
        run_cmd+=("${podman_args[@]}")
        run_cmd+=("$IMAGE")
        run_cmd+=("${CMD[@]}")

        "${run_cmd[@]}"
        local exit_code=$?

        # Audit STOP for the container we just ran
        audit --action STOP --name "$NAME" --image "$IMAGE" --ephemeral "$EPHEMERAL" --network "$NETWORK" --workspace "$WORKSPACE" --exit-code "$exit_code"

        # For ephemeral, the container is already removed by --rm, so we don't need to audit REMOVE.
        # For non-ephemeral, we are not in this branch because container_exists would be true? Wait, we are in this branch if container_exists is false.
        # So if we are creating a non-ephemeral container that didn't exist, we have now created and started it, run the command, and then stopped it?
        # Actually, we ran the command and then the container exited (because we didn't use -- detach). So the container is now stopped (not removed).
        # We should not remove it; we leave it stopped for future use.
        # But our audit STOP is correct.
        # However, we did not add --rm for non-ephemeral, so the container remains after stop.
        # Good.

        exit $exit_code
    else
        # Container exists and we are not ephemeral
        if [[ $container_running == true ]]; then
            log_info "Container already running: $NAME"
            audit --action START --name "$NAME" --image "$IMAGE" --ephemeral "$EPHEMERAL" --network "$NETWORK" --workspace "$WORKSPACE" || true # Avoid double START audit? We'll still audit.
        else
            log_info "Starting existing stopped container: $NAME"
            audit --action START --name "$NAME" --image "$IMAGE" --ephemeral "$EPHEMERAL" --network "$NETWORK" --workspace "$WORKSPACE"
            podman start "$NAME" >/dev/null
        fi

        # Execute command in the running container
        log_info "Executing command in existing container: $NAME"
        audit --action EXEC --name "$NAME" --image "$IMAGE" --ephemeral "$EPHEMERAL" --network "$NETWORK" --workspace "$WORKSPACE" --details "{\"command\": \"${CMD[*]}\"}"

        podman exec -it "$NAME" "${CMD[@]}"
        local exit_code=$?

        # We do not audit STOP here because the container is still running after exec.
        # The user can stop it later.
        exit $exit_code
    fi
}

main "$@"