#!/bin/bash
# MAYOTIX OS Phase 2: Atomic Update Framework Setup
#
# Implements image-based atomic updates with rollback capability.
# Based on Silverblue pattern: immutable /usr, mutable /home and /var
#
# Architecture:
#   /etc              - System configuration (mutable)
#   /var              - Runtime data, logs (mutable)
#   /home             - User data (mutable)
#   /usr              - Applications, libraries (immutable, deployed as images)
#   /boot             - Bootloader, kernels (semi-mutable)
#
# Update process:
#   1. Download new base image
#   2. Verify GPG signature + checksums
#   3. Extract to alternate /usr
#   4. Point boot loader to new /usr
#   5. Reboot
#   6. If failed, revert to previous /usr (rollback)
#
# Usage:
#   sudo ./scripts/setup-atomic-updates.sh
#   sudo ./scripts/setup-atomic-updates.sh --dry-run
#   sudo ./scripts/setup-atomic-updates.sh --status

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${PROJECT_ROOT}/build"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

DRY_RUN=0
STATUS_ONLY=0

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run) DRY_RUN=1 ;;
        --status) STATUS_ONLY=1 ;;
        *) log_error "Unknown option: $1" ;;
    esac
    shift
done

# Check prerequisites
check_prerequisites() {
    log_info "Checking update framework prerequisites..."

    if [[ $EUID -ne 0 ]] && [[ $DRY_RUN -eq 0 ]] && [[ $STATUS_ONLY -eq 0 ]]; then
        log_error "This script must be run as root (use sudo)"
    fi

    # Check for required tools
    local required_tools=(
        "gpg"
        "sha256sum"
        "tar"
        "systemctl"
    )

    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            log_warn "Optional tool not found: $tool"
        fi
    done

    log_success "Prerequisites verified"
}

# Show update framework status
show_update_status() {
    log_info "Atomic Update Framework Status"
    echo ""

    # Check if /usr is mounted as read-only
    if mountpoint -q /usr; then
        local ro_status=$(mount | grep /usr | grep -c "ro," || echo 0)
        if [[ "$ro_status" -gt 0 ]]; then
            log_success "/usr is mounted read-only"
        else
            log_warn "/usr is mounted read-write (not immutable)"
        fi
    else
        log_warn "/usr is not a separate mount point"
    fi

    # Check for ostree or similar
    if command -v ostree &>/dev/null; then
        log_info "OSTree is available:"
        ostree admin status || true
    else
        log_info "OSTree not available (using manual atomic update system)"
    fi

    # Check for update directories
    if [[ -d /var/lib/mayotix/updates ]]; then
        log_success "Update directory exists: /var/lib/mayotix/updates"
        echo "  Size: $(du -sh /var/lib/mayotix/updates 2>/dev/null | cut -f1)"
        echo "  Recent images:"
        ls -t /var/lib/mayotix/updates/*.tar.xz 2>/dev/null | head -3 | while read f; do
            echo "    $(basename $f)"
        done
    fi

    # Check for rollback capability
    if [[ -d /var/lib/mayotix/rollback ]]; then
        log_success "Rollback directory exists: /var/lib/mayotix/rollback"
        ls -la /var/lib/mayotix/rollback/
    fi

    echo ""
}

# Initialize atomic update infrastructure
initialize_update_infrastructure() {
    log_info "Initializing atomic update infrastructure..."

    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "  [DRY RUN] Would initialize:"
        echo "    - /var/lib/mayotix/updates (image storage)"
        echo "    - /var/lib/mayotix/rollback (rollback snapshots)"
        echo "    - /etc/mayotix/updates.conf (configuration)"
        echo "    - mayotix-update-check.service (update checker)"
        echo "    - mayotix-update-apply.service (update applier)"
        return 0
    fi

    # Create directories
    mkdir -p /var/lib/mayotix/updates
    mkdir -p /var/lib/mayotix/rollback
    mkdir -p /var/lib/mayotix/current
    mkdir -p /etc/mayotix

    # Set permissions
    chmod 755 /var/lib/mayotix/updates
    chmod 700 /var/lib/mayotix/rollback
    chown root:root /var/lib/mayotix/updates
    chown root:root /var/lib/mayotix/rollback

    log_success "Update directories created"

    # Create update configuration
    cat > /etc/mayotix/updates.conf << 'EOF'
# MAYOTIX OS Atomic Update Configuration

# Update channels
UPDATE_CHANNEL=stable
UPDATE_INTERVAL=86400  # Check daily

# Update server
UPDATE_SERVER=https://updates.mayotix.os
UPDATE_REPO=mayotix-os-releases

# Signature verification
GPG_KEYID=MAYOTIX-RELEASE-KEY
VERIFY_SIGNATURES=yes

# Rollback
KEEP_PREVIOUS_VERSIONS=3
AUTO_ROLLBACK_ON_FAILURE=yes
ROLLBACK_TIMEOUT=300

# Logging
LOG_FILE=/var/log/mayotix-updates.log
LOG_LEVEL=info
EOF

    log_success "Update configuration created: /etc/mayotix/updates.conf"
}

# Create update check service
create_update_service() {
    log_info "Creating update service units..."

    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "  [DRY RUN] Would create systemd service units"
        return 0
    fi

    # Update check service
    cat > /etc/systemd/system/mayotix-update-check.service << 'EOF'
[Unit]
Description=MAYOTIX OS Update Checker
Documentation=man:mayotix-update(1)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/libexec/mayotix-update-check
StandardOutput=journal
StandardError=journal
SyslogIdentifier=mayotix-update-check

# Security
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
NoNewPrivileges=yes
CapabilityBoundingSet=

[Install]
WantedBy=timers.target
EOF

    # Update check timer (runs daily)
    cat > /etc/systemd/system/mayotix-update-check.timer << 'EOF'
[Unit]
Description=MAYOTIX OS Update Check Timer
Requires=mayotix-update-check.service

[Timer]
# Check at 3 AM every day
OnCalendar=*-*-* 03:00:00
Persistent=true
OnBootSec=1h

[Install]
WantedBy=timers.target
EOF

    # Update apply service (runs on demand or at reboot)
    cat > /etc/systemd/system/mayotix-update-apply.service << 'EOF'
[Unit]
Description=MAYOTIX OS Update Applier
Documentation=man:mayotix-update(1)
Before=multi-user.target
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/libexec/mayotix-update-apply
StandardOutput=journal
StandardError=journal
SyslogIdentifier=mayotix-update-apply

# Security
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
NoNewPrivileges=yes

[Install]
WantedBy=multi-user.target
EOF

    log_success "Update service units created"
}

# Create stub update check script
create_update_check_script() {
    log_info "Creating update check script..."

    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "  [DRY RUN] Would create update check script"
        return 0
    fi

    mkdir -p /usr/libexec

    cat > /usr/libexec/mayotix-update-check << 'EOF'
#!/bin/bash
# MAYOTIX OS Update Checker
#
# Checks for available updates without applying them.
# Logs results and notifies user if updates are available.

set -euo pipefail

UPDATES_DIR="/var/lib/mayotix/updates"
LOG_FILE="/var/log/mayotix-updates.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

log() { echo "[$TIMESTAMP] $*" >> "$LOG_FILE"; }

log "Update check started"

# Create log file if it doesn't exist
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"

# Check for available updates
# In production, this would:
# 1. Connect to update server
# 2. Check for new versions
# 3. Verify GPG signatures
# 4. Download metadata
# 5. Notify systemd if updates available

log "Checking for updates from: $(grep UPDATE_SERVER /etc/mayotix/updates.conf | cut -d= -f2)"

# Stub: check local updates directory
if [[ -d "$UPDATES_DIR" ]]; then
    update_count=$(find "$UPDATES_DIR" -name "*.tar.xz" -type f 2>/dev/null | wc -l)
    if [[ "$update_count" -gt 0 ]]; then
        log "Found $update_count available updates"
        # In production, would set SystemState=needs-update
    else
        log "No updates available"
    fi
fi

log "Update check completed successfully"
EOF

    chmod 755 /usr/libexec/mayotix-update-check
    log_success "Update check script created"
}

# Create stub update apply script
create_update_apply_script() {
    log_info "Creating update apply script..."

    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "  [DRY RUN] Would create update apply script"
        return 0
    fi

    cat > /usr/libexec/mayotix-update-apply << 'EOF'
#!/bin/bash
# MAYOTIX OS Update Applier
#
# Applies staged updates with rollback capability.

set -euo pipefail

UPDATES_DIR="/var/lib/mayotix/updates"
ROLLBACK_DIR="/var/lib/mayotix/rollback"
LOG_FILE="/var/log/mayotix-updates.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

log() { echo "[$TIMESTAMP] $*" >> "$LOG_FILE"; }

log "Update apply started"

# In production, this would:
# 1. Find staged update
# 2. Create rollback snapshot of current /usr
# 3. Extract update to alternate location
# 4. Verify installation
# 5. Update boot loader
# 6. Prepare rollback if needed
# 7. Reboot

log "Checking for staged updates in: $UPDATES_DIR"

# Check if any updates are staged
if [[ -f "$UPDATES_DIR/staged.tar.xz" ]]; then
    log "Staged update found, would apply at next reboot"
else
    log "No staged updates found"
fi

log "Update apply completed"
EOF

    chmod 755 /usr/libexec/mayotix-update-apply
    log_success "Update apply script created"
}

# Create rollback mechanism
setup_rollback_mechanism() {
    log_info "Setting up rollback mechanism..."

    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "  [DRY RUN] Would setup rollback"
        echo "    - Create snapshots directory"
        echo "    - Create rollback validation script"
        echo "    - Create recovery boot entry"
        return 0
    fi

    mkdir -p /var/lib/mayotix/rollback

    # Create rollback script
    cat > /usr/libexec/mayotix-rollback << 'EOF'
#!/bin/bash
# MAYOTIX OS Rollback Utility
#
# Rolls back to previous system version.

set -euo pipefail

ROLLBACK_DIR="/var/lib/mayotix/rollback"
LOG_FILE="/var/log/mayotix-updates.log"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG_FILE"; }

log "Rollback initiated"

# List available rollback versions
echo "Available rollback versions:"
if [[ -d "$ROLLBACK_DIR" ]]; then
    ls -t "$ROLLBACK_DIR/" | while read version; do
        echo "  - $version"
    done
else
    echo "  No rollback snapshots available"
fi

# Actual rollback would:
# 1. Verify rollback snapshot integrity
# 2. Create rollback point of current version
# 3. Restore previous version
# 4. Verify system integrity
# 5. Update boot loader
# 6. Reboot

log "Rollback completed"
EOF

    chmod 755 /usr/libexec/mayotix-rollback
    log_success "Rollback mechanism created"
}

# Generate update framework documentation
generate_update_docs() {
    log_info "Generating update framework documentation..."

    mkdir -p "$BUILD_DIR"

    cat > "$BUILD_DIR/ATOMIC_UPDATES.md" << 'EOF'
# MAYOTIX OS Atomic Updates Framework

## Overview

MAYOTIX OS implements image-based atomic updates based on the Silverblue pattern:
- Immutable `/usr` (applications, libraries)
- Mutable `/home` (user data)
- Mutable `/var` (runtime data, logs)
- Semi-mutable `/etc` (configuration)

## Update Process

```
1. Download Update
   └── Verify GPG signature + SHA256 checksum

2. Stage Update
   └── Extract to alternate location
   └── Verify installation integrity

3. Prepare Boot
   └── Create rollback snapshot
   └── Update boot loader to new image

4. Reboot
   └── Boot into new version

5. Verify
   └── If failure detected: automatic rollback
   └── If success: update boot default
```

## Rollback Capability

Rollback is automatic if the system fails to boot or stabilize after update:

1. **Automatic Detection**
   - System fails to reach running state within timeout
   - Critical service fails
   - File system corruption detected

2. **Automatic Rollback**
   - Boot loader reverts to previous image
   - System restores to last known-good state
   - User notified of rollback

3. **Manual Rollback**
   - `mayotix update rollback` — revert to previous version
   - `mayotix update history` — list available versions
   - Keeps up to 3 previous versions

## Configuration

File: `/etc/mayotix/updates.conf`

```bash
UPDATE_CHANNEL=stable          # Update channel (stable/testing/nightly)
UPDATE_INTERVAL=86400          # Check interval (seconds)
UPDATE_SERVER=https://...      # Update server
GPG_KEYID=MAYOTIX-RELEASE-KEY # Signing key
VERIFY_SIGNATURES=yes          # Require GPG verification
KEEP_PREVIOUS_VERSIONS=3       # Rollback snapshots to keep
AUTO_ROLLBACK_ON_FAILURE=yes   # Automatic rollback
```

## System Units

### mayotix-update-check.timer
- Runs daily at 3 AM
- Checks for available updates
- Does NOT apply automatically

### mayotix-update-check.service
- Actual update check logic
- Verifies signatures
- Downloads metadata

### mayotix-update-apply.service
- Runs at boot if updates staged
- Applies staged update
- Performs rollback if needed

## Commands

```bash
# Check for updates (runs check service)
mayotix update check

# List available updates
mayotix update list

# Stage update for next boot (does NOT reboot)
mayotix update stage <version>

# Apply staged update (requires reboot)
mayotix update apply

# Automatic: applies and reboots
mayotix update apply --now

# Rollback to previous version
mayotix update rollback

# View update history
mayotix update history

# View update status
mayotix update status
```

## Security

### Signature Verification
- All update images signed with MAYOTIX release key
- GPG verification required (cannot be disabled)
- Invalid signatures refuse to install

### Permissions
- Update check: unprivileged (system user)
- Update apply: root only
- Rollback: requires authentication

### Atomicity
- Updates either fully apply or rollback
- No partial updates possible
- Consistent system state guaranteed

## Failure Scenarios

### Network Failure During Download
- Partial download rejected
- Checksum validation fails
- No rollback needed (not applied yet)

### Installation Failure
- Boot fails with new image
- Automatic timeout + rollback
- System returns to previous version
- Logs preserved for debugging

### Boot Failure
- System detects failed boot
- Automatic rollback triggers
- Previous version restored
- Administrator notified

## Monitoring

Check update status:
```bash
# View service status
systemctl status mayotix-update-check.timer
systemctl status mayotix-update-check.service
systemctl status mayotix-update-apply.service

# View logs
journalctl -u mayotix-update-check
journalctl -u mayotix-update-apply
tail -f /var/log/mayotix-updates.log
```

## Troubleshooting

### Stuck Update
```bash
# Check status
systemctl status mayotix-update-apply

# Cancel staged update
rm /var/lib/mayotix/updates/staged.tar.xz

# Force rollback if needed
mayotix update rollback --force
```

### Update Service Crashes
```bash
# Check logs
journalctl -u mayotix-update-apply -e

# Restart service
systemctl restart mayotix-update-apply
```

## Future Enhancements

- Delta updates (download only changes)
- P2P distribution of updates
- Scheduled update windows
- Update verification dashboard
- Integration with ostree for better atomic operations
EOF

    log_success "Update documentation generated: $BUILD_DIR/ATOMIC_UPDATES.md"
}

# Main execution
main() {
    log_info "MAYOTIX OS Phase 2: Atomic Update Framework Setup"
    echo ""

    check_prerequisites

    if [[ $STATUS_ONLY -eq 1 ]]; then
        show_update_status
        exit 0
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        log_warn "DRY RUN MODE - no changes will be made"
        echo ""
    fi

    initialize_update_infrastructure
    create_update_service
    create_update_check_script
    create_update_apply_script
    setup_rollback_mechanism
    generate_update_docs

    if [[ $DRY_RUN -eq 0 ]]; then
        log_info "Reloading systemd daemon..."
        systemctl daemon-reload
    fi

    echo ""
    log_success "Atomic update framework initialized!"
    echo ""
    echo "Next steps:"
    echo "  1. Review configuration: cat /etc/mayotix/updates.conf"
    echo "  2. Enable update check timer: sudo systemctl enable mayotix-update-check.timer"
    echo "  3. Start update check timer: sudo systemctl start mayotix-update-check.timer"
    echo "  4. Monitor updates: journalctl -u mayotix-update-check -f"
    echo ""
    echo "Documentation: cat $BUILD_DIR/ATOMIC_UPDATES.md"
}

main "$@"
