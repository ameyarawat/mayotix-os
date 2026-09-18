# MAYOTIX OS — Phase 11: Anaconda Installer & Encrypted Dual-Boot Partitioning

## 1. Executive Architectural Overview

MAYOTIX OS Phase 11 delivers a hardened, production-ready **System Installer Subsystem**. Designed for Fedora 40/44 with UEFI Secure Boot and SELinux Enforcing, Phase 11 provides:
- **Full-Disk Encryption (FDE)** using the modern **LUKS2** container format paired with the memory-hard **Argon2id** password hashing algorithm (`1048576 KB` memory cost, 4 iterations).
- **TPM 2.0 Auto-Unlock Binding**: Optional hardware-bound decryption against firmware state measurements (PCRs 0, 2, 4, 7) via `clevis-luks-bind` / `systemd-cryptenroll`.
- **Zero-Loss Dual-Boot Protection**: Automatic discovery of existing operating systems (e.g. Windows Boot Manager `\EFI\Microsoft\Boot\bootmgfw.efi`), enforcing read-only preservation of EFI System Partitions (ESP >= 512MB) and automatic GRUB2 chainloader generation.
- **Btrfs Subvolume Layout**: Immutable root separation into subvolumes (`@root`, `@home`, `@var_log`, `@var_cache`, `@snapshots`).
- **Anaconda Kickstart Automation**: Production kickstarts for unattended OEM installations (`mayotix-hardened.ks`) and live desktop installations (`mayotix-live.ks`).
- **Guided Installation Wizard**: Native Qt6 / Wayland installer GUI (`mayotix-installer-gui.py`) and unified CLI (`mayotix install`).

```
+-----------------------------------------------------------------------------------+
|                                  MAYOTIX OS HOST                                  |
|                                                                                   |
|  +--------------------+     +---------------------+     +-----------------------+ |
|  |    Mayotix CLI     |     | Guided Installer GUI|     |  System D-Bus Daemon  | |
|  |  (mayotix install) |     |   (Qt6 / Wayland)   |     |   (mayotix-daemon)    | |
|  +---------+----------+     +----------+----------+     +-----------+-----------+ |
|            |                           |                            |             |
|            +-------------------+       |       +--------------------+             |
|                                |       |       |                                  |
|                                v       v       v                                  |
|                  +-----------------------------------------+                      |
|                  |       mayotix-daemon (JSON-RPC)         |                      |
|                  |        /run/mayotix/daemon.sock         |                      |
|                  +--------------------+--------------------+                      |
|                                       |                                           |
|             +-------------------------+-------------------------+                 |
|             |                                                   |                 |
|             v                                                   v                 |
|  +-----------------------+                           +-----------------------+    |
|  | partition-validator.sh|                           |    luks2-setup.sh     |    |
|  | (Dual-Boot & ESP Guard|                           | (Argon2id + TPM2 FDE) |    |
|  +----------+------------+                           +----------+------------+    |
|             |                                                   |                 |
|             v                                                   v                 |
|   Windows ESP Preserved: /dev/nvme0n1p1              LUKS2 aes-xts-plain64        |
|   No-Overwrite: bootmgfw.efi                         Argon2id 1024MB Memory Cost  |
|   GPT Layout Verified                                TPM2 PCR 0,2,4,7 Bound       |
+-------------|---------------------------------------------------|-----------------+
              |                                                   |
              v                                                   v
       +-----------------------------------------------------------------+
       |                     TARGET DISK PARTITIONING                    |
       |                                                                 |
       |   +-------------------+  +-----------------+  +---------------+ |
       |   | /dev/nvme0n1p1    |  | /dev/nvme0n1p2  |  |/dev/nvme0n1p3 | |
       |   | ESP (FAT32, 600MB)|  | /boot (1024 MB) |  |LUKS2 Container| |
       |   | Windows/Linux EFI |  | Ext4 Kernel/GRUB|  |Argon2id Enc   | |
       |   +-------------------+  +-----------------+  +-------+-------+ |
       |                                                       |         |
       |                                                       v         |
       |                                            Btrfs Subvolumes:    |
       |                                            @root, @home, @var   |
       |                                            @snapshots           |
       +-----------------------------------------------------------------+
```

---

## 2. Core Components & Subsystems

### 2.1 Partition Validator & Dual-Boot Guard (`partition-validator.sh`)
Located at `installer/partition-validator.sh`, this engine inspects the host storage topology:
- **Device Discovery**: Enumerates physical NVMe, SATA, and virtual block devices.
- **Partition Table Audit**: Validates GPT (GUID Partition Table) compliance required for modern UEFI booting.
- **Dual-Boot Protection Guard**: Scans for `bootmgfw.efi` in existing EFI partitions. Enforces strict read-only preservation so Windows installations and BitLocker partitions are never corrupted.
- **ESP Capacity Validation**: Ensures the EFI System Partition is at least 512MB (600MB recommended) to prevent bootloader overflow.

### 2.2 LUKS2 Full-Disk Encryption & Key Escrow (`luks2-setup.sh`)
Located at `installer/luks2-setup.sh`, this module manages storage encryption:
- **Argon2id Key Derivation**: Uses memory-hard Argon2id (`--pbkdf argon2id --pbkdf-memory 1048576`) to defeat GPU/ASIC brute-force cracking.
- **Cryptographic Cipher**: `aes-xts-plain64` with 512-bit key size.
- **Disaster Recovery Key**: Automatically generates a 256-bit emergency offline recovery token.
- **TPM 2.0 Integration**: Binds key slots to TPM2 PCR registers (0, 2, 4, 7) for transparent, tamper-evident boot auto-unlock.

### 2.3 Master System Installer Engine (`mayotix-installer.sh`)
Located at `installer/mayotix-installer.sh`, this engine drives the full deployment:
- **Pre-Flight Diagnostics**: Verifies x86_64 64-bit architecture, >= 4GB RAM, UEFI firmware mode, and Secure Boot readiness.
- **Btrfs Subvolume Hierarchy**: Partitions storage into `@root` (`/`), `@home` (`/home`), `@var_log` (`/var/log`), and `@snapshots` for atomic rollbacks.
- **Dual-Boot Chainloader**: Configures GRUB2 with automated Windows Boot Manager detection.

### 2.4 SELinux MAC Security Profile (`mayotix_installer.te` & `mayotix_installer.fc`)
Located in `security/selinux/`, the Phase 11 Type Enforcement policy enforces mandatory access control:
- Declares domain `mayotix_installer_t` allowing block device formatting (`fixed_disk_device_t`), TPM ioctls (`tpm_device_t`), and EFI filesystem mounting (`dosfs_t`).
- **Strict Host Airgap**: Zero permissions granted on `user_home_t`.

---

## 3. Privileged Daemon RPC Endpoints

The system daemon (`daemon/mayotix-daemon.py`) provides 5 dedicated JSON-RPC endpoints under `installer.*`:

| Method | Parameters | Description |
| :--- | :--- | :--- |
| `installer.preflight` | *none* | Evaluates CPU, RAM, UEFI, Secure Boot, and TPM2 readiness |
| `installer.disks` | *none* | Enumerates block devices and scans for existing Windows/Linux OS |
| `installer.validate_layout` | `disk` | Validates GPT partitioning, ESP capacity, and dual-boot boundaries |
| `installer.luks_status` | *none* | Reports LUKS2 Argon2id cipher and TPM2 auto-unlock parameters |
| `installer.simulate` | `target`, `dual_boot`, `encrypt` | Simulates full installation workflow and outputs verification telemetry |

---

## 4. CLI Usage Reference

The unified `mayotix` CLI controls all Phase 11 installer features:

```bash
# Perform pre-flight hardware and firmware diagnostics
mayotix install preflight --dry-run --json

# Discover storage drives and detect existing dual-boot installations
mayotix install disks --dry-run --json

# Validate partition layout and dual-boot ESP isolation
mayotix install validate --dry-run --json

# Inspect LUKS2 Argon2id encryption parameters and TPM2 status
mayotix install luks --dry-run --json

# Launch system installation (simulated dry-run)
mayotix install start --target /dev/nvme0n1 --dual-boot --encrypt --dry-run --json
```
