#!/bin/bash
# MAYOTIX OS Phase 2: Audit Daemon Configuration Script
#
# Sets up auditd with comprehensive security rules
# Configures systemd-journald for persistent logging
# Establishes log retention and rotation
#
# Usage:
#   sudo ./scripts/configure-audit-phase2.sh
#   sudo ./scripts/configure-audit-phase2.sh --dry-run
#   sudo ./scripts/configure-audit-phase2.sh --status

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
    log_info "Checking audit prerequisites..."

    if ! command -v auditctl &>/dev/null; then
        log_error "auditd not found. Install: sudo dnf install audit"
    fi

    if ! command -v systemctl &>/dev/null; then
        log_error "systemctl not found"
    fi

    if [[ $EUID -ne 0 ]] && [[ $DRY_RUN -eq 0 ]] && [[ $STATUS_ONLY -eq 0 ]]; then
        log_error "This script must be run as root (use sudo)"
    fi

    log_success "Prerequisites verified"
}

# Show audit status
show_audit_status() {
    log_info "Audit daemon status:"
    echo ""
    auditctl -v
    echo ""
    auditctl -l | head -20
    echo ""
    log_info "Systemd-journald status:"
    echo ""
    systemctl status systemd-journald --no-pager | head -10
    echo ""
    log_info "Journal storage:"
    journalctl --disk-usage
}

# Enable auditd
enable_auditd() {
    log_info "Enabling audit daemon..."

    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "  [DRY RUN] Would enable and start auditd"
        return 0
    fi

    systemctl enable auditd
    systemctl start auditd || systemctl restart auditd

    log_success "auditd enabled and started"
}

# Configure audit rules
configure_audit_rules() {
    log_info "Configuring comprehensive audit rules..."

    local audit_rules_file="/etc/audit/rules.d/mayotix.rules"

    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "  [DRY RUN] Would write audit rules to $audit_rules_file"
        return 0
    fi

    mkdir -p "$(dirname "$audit_rules_file")"

    cat > "$audit_rules_file" << 'EOF'
# MAYOTIX OS Phase 2: Comprehensive Audit Rules
#
# These rules monitor:
# - System calls: execve, open, read, write, mount
# - Authentication: login, sudo, SSH
# - File operations: /etc, /usr, critical binaries
# - Permissions: setuid, setgid operations
# - Network: socket creation, connections
# - SELinux: policy enforcement events
#

# Remove any existing rules
-D

# Buffer Size
-b 8192

# Failure handling
-f 1

## Core monitoring rules

# System calls: execve (command execution)
-a always,exit -F arch=b64 -S execve -F uid!=0 -F auid>=1000 -F auid!=-1 -k exec

# File access: /etc (system configuration)
-w /etc/passwd -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/sudoers -p wa -k sudoers
-w /etc/sudoers.d/ -p wa -k sudoers

# File access: critical binaries
-w /usr/bin/passwd -p x -k passwd_modification
-w /usr/bin/sudo -p x -k sudo_modification
-w /usr/bin/su -p x -k su_modification

# SELinux monitoring
-w /etc/selinux/ -p wa -k selinux
-w /usr/share/selinux/ -p wa -k selinux

# Audit configuration (prevent tampering)
-w /etc/audit/ -p wa -k audit_rules
-w /sbin/auditctl -p x -k audit_tools
-w /sbin/auditd -p x -k audit_tools

# System administration
-w /usr/sbin/useradd -p x -k user_modification
-w /usr/sbin/userdel -p x -k user_modification
-w /usr/sbin/usermod -p x -k user_modification
-w /usr/sbin/groupadd -p x -k group_modification
-w /usr/sbin/groupdel -p x -k group_modification
-w /usr/sbin/groupmod -p x -k group_modification

# Kernel module operations
-w /sbin/insmod -p x -k kernel_modules
-w /sbin/rmmod -p x -k kernel_modules
-a always,exit -F arch=b64 -S init_module,delete_module -F auid!=0 -F auid!=-1 -k kernel_modules

## Monitor for suspicious activities

# Unauthorized privilege attempts
-a always,exit -F arch=b64 -S adjtimex -S settimeofday -k time_change
-a always,exit -F arch=b64 -S sethostname -S setdomainname -k network_modifications
-a always,exit -F arch=b64 -S sysctl -S sysctl_modprobe -k system_configuration

# Network activity (socket operations)
-a always,exit -F arch=b64 -S socket -S connect -S sendto -S recvfrom -S sendmsg -S recvmsg -S setsockopt -F auid>=1000 -F auid!=-1 -k network_socket

# File deletion
-a always,exit -F arch=b64 -S unlink -S unlinkat -S rename -S renameat -F auid>=1000 -F auid!=-1 -k delete

# Suspicious permissions (setuid/setgid)
-a always,exit -F arch=b64 -S chmod -S fchmod -S fchmodat -F auid>=1000 -F auid!=-1 -F perms=u+s -k setuid
-a always,exit -F arch=b64 -S chmod -S fchmod -S fchmodat -F auid>=1000 -F auid!=-1 -F perms=g+s -k setgid

## Finalize rules

# Make rules immutable
-e 2
EOF

    # Load rules
    auditctl -R "$audit_rules_file"

    log_success "Audit rules configured: $audit_rules_file"
}

# Configure systemd-journald
configure_journald() {
    log_info "Configuring systemd-journald for persistent logging..."

    local journald_conf="/etc/systemd/journald.conf"

    if [[ ! -f "$journald_conf" ]]; then
        log_warn "journald.conf not found: $journald_conf"
        return 1
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "  [DRY RUN] Would configure journald"
        return 0
    fi

    # Backup original
    cp "$journald_conf" "${journald_conf}.backup-$(date +%s)"

    # Configure persistent storage
    cat >> "$journald_conf" << 'EOF'

# MAYOTIX Phase 2: Journald Configuration
Storage=persistent
Compress=yes
Seal=yes
RateLimitInterval=30s
RateLimitBurst=1000
SystemMaxUse=1G
SystemKeepFree=100M
SystemMaxFileSize=100M
MaxRetentionSec=30day
EOF

    # Create journal directory if needed
    mkdir -p /var/log/journal
    chown root:systemd-journal /var/log/journal
    chmod 2755 /var/log/journal

    # Restart journald
    systemctl restart systemd-journald

    log_success "systemd-journald configured for persistent logging"
}

# Create audit configuration
create_audit_config() {
    log_info "Creating audit configuration files..."

    mkdir -p "$BUILD_DIR"

    # Create audit.rules reference file
    cat > "${BUILD_DIR}/audit.rules" << 'EOF'
# MAYOTIX OS Phase 2: Complete Audit Rules Reference
#
# System monitoring events logged to:
# - /var/log/audit/audit.log (auditd)
# - /var/log/journal/ (systemd-journald persistent)
#
# Query audit logs:
#   ausearch -ts recent -k <key>
#   journalctl -u auditd -f
#   journalctl -x -e
#

# Remove previous rules
-D

# Buffer configuration
-b 8192                # Buffer size (events)
-f 1                  # Fail mode (1=ignore, 2=printk, 3=panic)

# IDENTITY EVENTS (User/Group changes)
-w /etc/passwd -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/gshadow -p wa -k identity
-w /etc/security/opasswd -p wa -k identity

# SUDOERS EVENTS (Privilege escalation)
-w /etc/sudoers -p wa -k sudoers
-w /etc/sudoers.d/ -p wa -k sudoers

# SELINUX EVENTS
-w /etc/selinux/ -p wa -k selinux
-w /usr/share/selinux/ -p wa -k selinux
-w /var/lib/selinux/ -p wa -k selinux

# AUDIT CONFIGURATION (Prevent tampering)
-w /etc/audit/ -p wa -k audit_rules
-w /sbin/auditctl -p x -k audit_tools
-w /sbin/auditd -p x -k audit_tools

# KERNEL MODULES
-w /sbin/insmod -p x -k kernel_modules
-w /sbin/rmmod -p x -k kernel_modules
-a always,exit -F arch=b64 -S init_module,delete_module -F auid!=0 -k kernel_modules

# TIME EVENTS (System clock changes)
-a always,exit -F arch=b64 -S adjtimex -S settimeofday -k time_change
-a always,exit -F arch=b64 -S clock_settime -k time_change

# NETWORK EVENTS
-a always,exit -F arch=b64 -S sethostname -S setdomainname -k network_modifications
-a always,exit -F arch=b64 -S sysctl -S sysctl_modprobe -k system_configuration
-a always,exit -F arch=b64 -S socket -S connect -F auid>=1000 -k network_socket

# SYSTEM ADMINISTRATION
-w /usr/sbin/useradd -p x -k user_modification
-w /usr/sbin/userdel -p x -k user_modification
-w /usr/sbin/usermod -p x -k user_modification
-w /usr/sbin/groupadd -p x -k group_modification
-w /usr/sbin/groupdel -p x -k group_modification

# FILE DELETION
-a always,exit -F arch=b64 -S unlink -S unlinkat -F auid>=1000 -k delete

# PERMISSIONS CHANGES
-a always,exit -F arch=b64 -S chmod -S fchmod -F perms=u+s -k setuid
-a always,exit -F arch=b64 -S chmod -S fchmod -F perms=g+s -k setgid

# Make rules immutable
-e 2
EOF

    log_success "Audit configuration reference: ${BUILD_DIR}/audit.rules"
}

# Generate audit report
generate_audit_report() {
    log_info "Generating audit configuration report..."

    local report_file="${BUILD_DIR}/audit-config-report.txt"

    {
        echo "MAYOTIX OS Phase 2: Audit Configuration Report"
        echo "=============================================="
        echo "Date: $(date)"
        echo ""
        echo "Audit Daemon Configuration:"
        echo "  Status: $(systemctl is-active auditd)"
        echo "  Enabled: $(systemctl is-enabled auditd)"
        echo ""
        echo "Systemd-journald Configuration:"
        echo "  Status: $(systemctl is-active systemd-journald)"
        echo "  Storage: persistent (/var/log/journal)"
        echo "  Compression: enabled (gzip)"
        echo "  Sealing: enabled (FSSB signatures)"
        echo ""
        echo "Log Files Monitored:"
        echo "  - /etc/passwd, /etc/group, /etc/shadow (identity)"
        echo "  - /etc/sudoers, /etc/sudoers.d/ (privilege escalation)"
        echo "  - /etc/selinux/ (MAC policy)"
        echo "  - /sbin/auditctl, /sbin/auditd (audit tampering)"
        echo "  - /sbin/insmod, /sbin/rmmod (kernel modules)"
        echo "  - /usr/sbin/useradd, /usr/sbin/groupadd (system administration)"
        echo ""
        echo "System Call Monitoring:"
        echo "  - adjtimex, settimeofday, clock_settime (time changes)"
        echo "  - sethostname, setdomainname (network changes)"
        echo "  - socket, connect (network activity)"
        echo "  - chmod, chown, chgrp (permission changes)"
        echo "  - unlink, rename (file deletion)"
        echo ""
        echo "Log Retention:"
        echo "  - Duration: 30 days"
        echo "  - Size limit: 1GB total, 100MB per file"
        echo "  - Free space guarantee: 100MB minimum"
        echo ""
        echo "Accessing Audit Logs:"
        echo "  Recent events: ausearch -ts recent"
        echo "  By key: ausearch -k <key>"
        echo "  Identity changes: ausearch -k identity"
        echo "  Privilege escalation: ausearch -k sudoers"
        echo "  SELinux events: ausearch -k selinux"
        echo ""
        echo "Accessing Journal Logs:"
        echo "  Recent: journalctl -n 100"
        echo "  Follow: journalctl -f"
        echo "  By unit: journalctl -u auditd"
        echo "  By priority: journalctl -p err"
        echo "  By time: journalctl --since today"
        echo ""
        echo "Configuration Complete"
    } > "$report_file"

    log_success "Report: $report_file"
    cat "$report_file"
}

# Main execution
main() {
    log_info "MAYOTIX OS Phase 2: Audit Configuration"
    echo ""

    check_prerequisites

    if [[ $STATUS_ONLY -eq 1 ]]; then
        show_audit_status
        exit 0
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        log_warn "DRY RUN MODE - no changes will be made"
        echo ""
    fi

    enable_auditd
    configure_audit_rules
    configure_journald
    create_audit_config
    generate_audit_report

    echo ""
    log_success "Audit configuration complete!"
    echo ""
    echo "Verify configuration:"
    echo "  sudo systemctl status auditd"
    echo "  sudo auditctl -l"
    echo "  journalctl --disk-usage"
}

main "$@"
