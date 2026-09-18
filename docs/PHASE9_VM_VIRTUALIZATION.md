# MAYOTIX OS — Phase 9: Hardware-Assisted KVM/QEMU Hypervisor & Multi-Node Lab Virtualization

## 1. Executive Architectural Overview

MAYOTIX OS Phase 9 elevates the platform's malware detonation and security training infrastructure from container-level cgroupv2/Bubblewrap isolation to full **hardware-assisted Type-2 virtualization** using the Linux Kernel-based Virtual Machine (**KVM**) hypervisor and **QEMU micro-VMs**.

Operating under strict Fedora 40/44 SELinux Enforcing security profiles, Phase 9 provides:
- Near-native guest CPU performance via direct `/dev/kvm` hardware ioctl virtualization (Intel VT-x / AMD-V).
- Microsecond-speed copy-on-write snapshotting and non-destructive rollbacks via standard **QCOW2** storage layers.
- Multi-tier layer-2 virtual Ethernet bridge routing (`mayotix-vbr0`) coupled to isolated TAP adapters (`mayotix-tap0/1`) under an absolute fail-closed `nftables` egress firewall.
- Declarative multi-node lab topology orchestration (`lab-topology.py`) provisioning complex adversary simulation scenarios: `malware-sandbox`, `attack-defense`, and `dmz-pivot`.
- End-to-end integration across the privileged UNIX socket daemon (`mayotix-daemon.py`), the unified CLI (`mayotix vm`), and the Wayland Labs Studio GUI (`mayotix-labs-gui.py`).

```
+-----------------------------------------------------------------------------------+
|                                  MAYOTIX OS HOST                                  |
|                                                                                   |
|  +--------------------+     +---------------------+     +-----------------------+ |
|  |    Mayotix CLI     |     |   Labs Studio GUI   |     | Declarative Topology  | |
|  |    (mayotix vm)    |     |  (Qt6 / Wayland)    |     |   (lab-topology.py)   | |
|  +---------+----------+     +----------+----------+     +-----------+-----------+ |
|            |                           |                            |             |
|            +-------------------+       |       +--------------------+             |
|                                |       |       |                                  |
|                                v       v       v                                  |
|                  +-----------------------------------------+                      |
|                  |     mayotix-daemon (UNIX RPC Domain)    |                      |
|                  |          /run/mayotix/daemon.sock       |                      |
|                  +--------------------+--------------------+                      |
|                                       |                                           |
|                                       v                                           |
|                  +-----------------------------------------+                      |
|                  |    SELinux Confined Engine: mayotix_vm_t|                      |
|                  +--------------------+--------------------+                      |
|                                       |                                           |
|             +-------------------------+-------------------------+                 |
|             |                                                   |                 |
|             v                                                   v                 |
|  +-----------------------+                           +-----------------------+    |
|  |   mayotix-vm.sh       |                           |   vm-network.sh       |    |
|  | (QEMU Micro-VM Core)  |                           | (VBR0 Bridge & TAPs)  |    |
|  +----------+------------+                           +----------+------------+    |
|             |                                                   |                 |
|             v                                                   v                 |
|   /dev/kvm (Hardware Accel)                         mayotix-vbr0 (10.99.1.1/24)   |
|   QCOW2 Overlay Snapshots                           mayotix-tap0 / mayotix-tap1   |
|                                                     nftables DROP_PHYSICAL_EGRESS |
+-------------|---------------------------------------------------|-----------------+
              |                                                   |
              v                                                   v
       +-----------------------------------------------------------------+
       |                     ISOLATED GUEST SUBNET                       |
       |                                                                 |
       |   +-----------------------+           +-----------------------+ |
       |   | VM: sandbox-node01    |           | VM: target-node02     | |
       |   | IP: 10.99.1.10        | <=======> | IP: 10.99.1.11        | |
       |   | MAC: 52:54:00:12:34:56|           | MAC: 52:54:00:12:34:57| |
       |   +-----------------------+           +-----------------------+ |
       +-----------------------------------------------------------------+
```

---

## 2. Core Components & Subsystems

### 2.1 Hardware-Assisted Micro-VM Controller (`mayotix-vm.sh`)
Located at `desktop/labs/vm/mayotix-vm.sh`, this POSIX-compliant management controller drives QEMU/KVM virtual machine instances with strict resource envelopes:
- **Default Specifications**: 2 vCPUs, 2048 MB RAM, 20 GB sparse virtual disk (`qcow2`), headless operation with QEMU monitor socket (`/run/mayotix/vm/<name>-monitor.sock`).
- **Hardware Acceleration**: Probes `/dev/kvm`. Defaults to `-enable-kvm -cpu host` when accessible, with seamless software TCG fallback (`-accel tcg`) during simulated or nested container environments.
- **Copy-on-Write Snapshots**: Integrates `qemu-img snapshot` allowing sub-second snapshots (`snapshot create <name> <tag>`) and instantaneous post-detonation restoration (`rollback <name> <tag>`).
- **Safe Teardown & Destruction**: Provides graceful ACPI shutdown (`system_powerdown` via monitor) followed by forced SIGTERM/SIGKILL termination if uncooperative, followed by disk image and monitor socket cleanup.

### 2.2 Multi-Tier Isolated TAP Network Router (`vm-network.sh`)
Located at `desktop/labs/vm/vm-network.sh`, this network manager provisions a virtual Ethernet bridge and TAP devices:
- **Bridge Configuration**: Allocates `mayotix-vbr0` with CIDR `10.99.1.1/24`.
- **TAP Interfaces**: Creates persistent tun/tap adapters (e.g., `mayotix-tap0`, `mayotix-tap1`) attached directly to `mayotix-vbr0`.
- **Packet Isolation & Containment**: Enforces zero-leakage egress filtering via `nftables`:
  ```nftables
  table inet mayotix_vm_isolation {
      chain forward {
          type filter hook forward priority 0; policy drop;
          iifname "mayotix-vbr0" oifname "mayotix-vbr0" accept
          iifname "mayotix-vbr0" drop
      }
      chain input {
          type filter hook input priority 0; policy drop;
          iifname "mayotix-vbr0" accept
      }
  }
  ```
  Physical NIC egress is dropped at the hook forward layer, preventing any guest-originated packet from routing out to the host's LAN or WAN.

### 2.3 Declarative Topology Orchestration Engine (`lab-topology.py`)
Located at `desktop/labs/vm/lab-topology.py`, this engine orchestrates multi-node distributed lab topologies:
- **`malware-sandbox`**: Single hardened micro-VM attached to `mayotix-tap0` with instant rollback markers for live binary detonation.
- **`attack-defense`**: Two-node adversarial setup with an attacker workstation (`attacker-node01`, `10.99.1.10`) and a vulnerable victim target (`victim-node02`, `10.99.1.11`).
- **`dmz-pivot`**: Three-node dual-tier architecture with an edge DMZ bastion (`dmz-bastion`, `10.99.1.10`), internal enterprise server (`internal-srv`, `10.99.1.11`), and domain asset (`domain-asset`, `10.99.1.12`).

### 2.4 Mandatory Access Control Policy (`mayotix_vm.te` & `mayotix_vm.fc`)
Located in `security/selinux/`, the Phase 9 Type Enforcement policy confines the hypervisor daemon and worker scripts:
- Declares domain `mayotix_vm_t` and executable entry point `mayotix_vm_exec_t`.
- Grants `rw_file_perms` and specific ioctl permissions (`0xAE00`-`0xAEFF`) on `kvm_device_t`.
- Grants `tun_socket` creation and ioctl manipulation on `tun_tap_device_t`.
- **Absolute User Airgap**: Zero file or directory access permissions to `user_home_t`, ensuring that compromised VM processes or breakout attempts cannot inspect user files or cryptographic credentials.

---

## 3. Privileged Daemon RPC Endpoints

The system daemon (`daemon/mayotix-daemon.py`) exposes 10 dedicated JSON-RPC methods over `/run/mayotix/daemon.sock`:

| Method | Parameters | Description |
| :--- | :--- | :--- |
| `vm.launch` | `name`, `ram`, `cpus`, `disk_size`, `tap` | Boots a micro-VM instance with KVM acceleration |
| `vm.stop` | `name`, `force` | Shuts down or forcefully terminates a running VM |
| `vm.list` | *none* | Enumerates all active and registered virtual machines |
| `vm.destroy` | `name` | Terminates VM process and purges associated QCOW2 storage |
| `vm.status` | `name` | Queries live process status, PID, and hardware KVM state |
| `vm.snapshot` | `name`, `tag` | Creates an instant QCOW2 copy-on-write snapshot |
| `vm.rollback` | `name`, `tag` | Reverts VM disk state to the designated snapshot tag |
| `vm.topology_deploy` | `name` | Declaratively brings up a multi-node lab scenario |
| `vm.topology_list` | *none* | Lists available topology blueprints and active deployments |
| `vm.topology_teardown` | `name` | Tears down all member nodes and restores network state |

---

## 4. CLI Usage Reference

The unified `mayotix` CLI controls all Phase 9 virtualization features:

```bash
# Check hypervisor status and KVM hardware acceleration
mayotix vm status --dry-run --json

# Launch an isolated micro-VM
mayotix vm launch sandbox-node01 --ram 2048 --cpus 2 --disk 20 --tap mayotix-tap0 --dry-run --json

# Create a clean pre-infection snapshot
mayotix vm snapshot sandbox-node01 clean-baseline --dry-run --json

# Rollback disk state after malware detonation
mayotix vm rollback sandbox-node01 clean-baseline --dry-run --json

# List registered and active VMs
mayotix vm list --dry-run --json

# Stop and purge micro-VM
mayotix vm stop sandbox-node01 --dry-run --json
mayotix vm destroy sandbox-node01 --dry-run --json

# List available multi-node topology blueprints
mayotix vm topology list --dry-run --json

# Declaratively deploy multi-node attack-defense lab
mayotix vm topology deploy attack-defense --dry-run --json

# Teardown multi-node scenario
mayotix vm topology teardown attack-defense --dry-run --json
```

---

## 5. Verification and Security Audit

Phase 9 includes automated test harnesses:
- `scripts/verify-phase9.sh`: 10 verification modules covering binaries, network bridge creation, QCOW2 snapshotting, multi-node topologies, SELinux airgap, daemon IPC, and GUI integration.
- `scripts/conduct-security-audit-phase9.sh`: Rigorous 8-pillar security audit evaluating Hypervisor Isolation, Fail-Closed Egress, Multi-Node Airgap, Copy-on-Write Integrity, SELinux MAC Policy, Daemon IPC Input Sanitization, Privilege Boundaries, and GUI Confinement (target: 100/100 points).
