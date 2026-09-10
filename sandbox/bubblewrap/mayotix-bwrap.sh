#!/bin/bash
# MAYOTIX OS Phase 3 Week 2: Bubblewrap CLI Wrapper & Profiles
# Generic sandboxing launcher script that mounts a minimal read-only root,
# ephemeral /home, private /tmp, isolated network namespace, and drops capabilities.

set -euo pipefail

# Default configuration
READONLY_PATHS=("/usr" "/lib64" "/bin" "/sbin" "/lib" "/lib32" "/libx32" "/usr/lib" "/usr/lib64" "/usr/lib32" "/usr/libx32")
TMP_SIZE="100M"
HOME_SIZE="1G"
NETWORK="none"   # Options: none, private, host
CAPABILITIES=""  # By default, we drop all capabilities (--cap-all)
PROFILE=""       # Will be set by profile files or command line

# Profile directory
PROFILE_DIR="${0%/*}/profiles"

# Function to display usage
usage() {
    echo "Usage: $0 [--profile <profile>] [--network <none|private|host>] [--cap <cap>] [--] <command> [args...]"
    echo "  --profile   Use a profile from $PROFILE_DIR (e.g., network-isolated, minimal-net)"
    echo "  --network   Network namespace mode: none (default), private, host"
    echo "  --cap       Capabilities to keep (comma-separated, e.g., CAP_NET_BIND_SERVICE). If not set, all capabilities are dropped."
    echo "  --          Separator for options and command (required if command starts with -)"
    echo "  <command>   The command to run in the sandbox"
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --profile)
            PROFILE="$2"
            shift 2
            ;;
        --network)
            NETWORK="$2"
            shift  # We'll use this to set the sandboxing options
            shift 2
            ;;
        --cap)
            CAPABILITIES="$2"
            shift 2
            ;;
        --)
            shift
            break
            ;;
        *)
            # If we encounter an argument that is not an option, treat it as the start of the command
            break
            ;;
    esac
done

# If we have a profile, load it
if [[ -n "$PROFILE" ]]; then
    if [[ -f "$PROFILE_DIR/$PROFILE" ]]; then
        source "$PROFILE_DIR/$PROFILE"
    else
        echo "Error: Profile '$PROFILE' not found in $PROFILE_DIR"
        exit 1
    fi
fi

# Build the bubblewrap command
BWRAP_CMD=(bwrap)

# Mount read-only paths
for path in "${READONLY_PATHS[@]}"; do
    if [[ -d "$path" ]]; then
        BWRAP_CMD+=(--ro-bind "$path" "$path")
    fi
done

# Mount /etc as read-only (but we may need to override some files like resolv.conf)
BWRAP_CMD+=(--ro-bind /etc /etc)

# Mount /dev
BWRAP_CMD+=(--dev /dev)
BWRAP_CMD+=(--bind /dev/shm /dev/shm)

# Create a temporary /tmp
BWRAP_CMD+=(--tmpfs /tmp)

# Create an isolated /home (we'll use a tmpfs for the home directory)
BWRAP_CMD+=(--tmpfs /home)

# Set up the namespace based on the network option
case "$NETWORK" in
    none)
        # Unshare user, network, ipc, uts, cgroup
        BWRAP_CMD+=(--unshare-user --unshare-net --unshare-ipc --unshare-uts --unshare-cgroup)
        ;;
    private)
        # Unshare user, ipc, uts, cgroup but keep network (private network namespace)
        BWRAP_CMD+=(--unshare-user --unshare-ipc --unshare-uts --unshare-cgroup)
        ;;
    host)
        # Only unshare user, ipc, uts, cgroup (keep network and mount namespace? Actually we want to keep the host network)
        BWRAP_CMD+=(--unshare-user --unshare-ipc --unshare-uts --unshare-cgroup)
        # Note: We are not unsharing the network namespace, so we use the host's network.
        ;;
    *)
        echo "Error: Invalid network option: $NETWORK"
        exit 1
        ;;
esac

# Handle capabilities
if [[ -n "$CAPABILITIES" ]]; then
    # Convert comma-separated list to bubblewrap arguments
    IFS=',' read -ra CAPS <<< "$CAPABILITIES"
    for cap in "${CAPS[@]}"; do
        BWRAP_CMD+=(--cap-add "$cap")
    done
else
    # Drop all capabilities
    BWRAP_CMD+=(--cap-all)
done

# If we have a command to run, add it
if [[ $# -eq 0 ]]; then
    echo "Error: No command specified."
    usage
fi

# Add the command and its arguments
BWRAP_CMD+=("$@")

# Execute bubblewrap
exec "${BWRAP_CMD[@]}"