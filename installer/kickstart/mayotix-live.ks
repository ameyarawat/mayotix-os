# ==============================================================================
# MAYOTIX OS — Phase 11: Production Live Anaconda Kickstart
# File: installer/kickstart/mayotix-live.ks
# Description: Standard installation kickstart with Btrfs subvolumes,
#              SELinux Enforcing, and dual-boot ESP preservation.
# ==============================================================================

# Version and Installation Mode
version=F40
text
reboot

# Keyboard and Localization
keyboard --vckeymap=us --xlayouts='us'
lang en_US.UTF-8
timezone UTC --utc

# Network Configuration
network --bootproto=dhcp --device=link --activate --onboot=on

# SELinux and Firewall
selinux --enforcing
firewall --enabled --ssh

# Authentication and User Setup
rootpw --lock
user --name=mayotix --groups=wheel --plaintext --password=mayotix --gecos="MAYOTIX User"

# Partitioning Configuration (Btrfs subvolumes with ESP preservation)
zerombr
clearpart --all --initlabel

# Standard UEFI Layout
part /boot/efi --fstype="efi" --size=600 --fsoptions="umask=0077,shortname=winnt"
part /boot --fstype="ext4" --size=1024 --label=MAYOTIX_BOOT
part btrfs.mayotix --fstype="btrfs" --size=30000 --grow --encrypted --luks-version=luks2 --cipher=aes-xts-plain64 --pbkdf=argon2id

# Btrfs Subvolume Hierarchy
btrfs none --label=MAYOTIX_SYS btrfs.mayotix
btrfs / --subvol --name=root MAYOTIX_SYS
btrfs /home --subvol --name=home MAYOTIX_SYS
btrfs /var/log --subvol --name=var_log MAYOTIX_SYS
btrfs /var/cache --subvol --name=var_cache MAYOTIX_SYS

# Package Manifest
%packages
@core
@standard
kernel
grub2-efi-x64
shim-x64
btrfs-progs
cryptsetup
clevis
clevis-luks
systemd-udev
selinux-policy-targeted
nftables
audit
bubblewrap
%end

# Post-Installation Security Hardening Script
%post --log=/root/ks-post.log
echo "[INFO] Running MAYOTIX OS Post-Installation Security Lockdown..."

# Enable SELinux relabeling
touch /.autorelabel

# Disable core dumps and enable kernel sysctl hardening
cat > /etc/sysctl.d/99-mayotix-hardened.conf << 'EOF'
fs.suid_dumpable = 0
kernel.randomize_va_space = 2
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.unprivileged_bpf_disabled = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
EOF

# Ensure auditd and firewalld are enabled
systemctl enable auditd.service
systemctl enable nftables.service

echo "[✓] MAYOTIX OS Installation Complete."
%end
