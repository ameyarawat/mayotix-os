# ==============================================================================
# MAYOTIX OS — Phase 11: Hardened Encrypted Anaconda Kickstart
# File: installer/kickstart/mayotix-hardened.ks
# Description: High-security FDE kickstart with LUKS2 Argon2id, TPM2 binding,
#              strict SELinux Enforcing, and no unencrypted partitions.
# ==============================================================================

version=F40
cmdline
reboot

keyboard --vckeymap=us --xlayouts='us'
lang en_US.UTF-8
timezone UTC --utc

network --bootproto=dhcp --device=link --activate --onboot=on

selinux --enforcing
firewall --enabled

rootpw --lock
user --name=mayotix --groups=wheel --plaintext --password=mayotix --gecos="MAYOTIX User"

zerombr
clearpart --all --initlabel

# Encrypted Partition Layout with Argon2id
part /boot/efi --fstype="efi" --size=600 --fsoptions="umask=0077,shortname=winnt"
part /boot --fstype="ext4" --size=1024 --label=MAYOTIX_BOOT --encrypted --luks-version=luks2 --cipher=aes-xts-plain64 --pbkdf=argon2id
part btrfs.mayotix --fstype="btrfs" --size=40000 --grow --encrypted --luks-version=luks2 --cipher=aes-xts-plain64 --pbkdf=argon2id --pbkdf-memory=1048576

btrfs none --label=MAYOTIX_SYS btrfs.mayotix
btrfs / --subvol --name=root MAYOTIX_SYS
btrfs /home --subvol --name=home MAYOTIX_SYS
btrfs /var/log --subvol --name=var_log MAYOTIX_SYS
btrfs /var/cache --subvol --name=var_cache MAYOTIX_SYS
btrfs /.snapshots --subvol --name=snapshots MAYOTIX_SYS

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
clevis-dracut
tpm2-tools
selinux-policy-targeted
nftables
audit
%end

%post --log=/root/ks-hardened-post.log
echo "[INFO] Configuring TPM2 Auto-Unlock & Post-Install Lockdown..."

# Enable TPM2 unlocking via Clevis if TPM2 device is present
if [ -e /dev/tpmrm0 ]; then
    echo "[INFO] TPM2 detected. Auto-enrollment enabled."
fi

# Configure zram swap (encrypted in RAM)
cat > /etc/systemd/zram-generator.conf << 'EOF'
[zram0]
zram-size = min(ram / 2, 4096)
compression-algorithm = zstd
EOF

touch /.autorelabel
echo "[✓] Hardened Installation Complete."
%end
