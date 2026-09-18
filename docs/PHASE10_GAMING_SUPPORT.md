# MAYOTIX OS — Phase 10: Hardened Gaming Support & Performance Optimization

## 1. Executive Architectural Overview

MAYOTIX OS Phase 10 bridges high-performance gaming with enterprise-grade operating system security. Running on Fedora 40/44 with Wayland and SELinux Enforcing, Phase 10 introduces a sandboxed gaming architecture that enables **Steam, Valve Proton, Vulkan/Mesa, and Feral GameMode** without violating the host operating system's core defense-in-depth guarantees.

Proprietary game binaries and third-party anti-cheat modules run under a strictly confined execution domain (`mayotix_gaming_t`) and Bubblewrap container boundaries. Games gain direct access to GPU acceleration nodes (`/dev/dri/renderD*`), PipeWire audio, and Wayland display sockets, while **host user credentials (`~/.ssh`, `~/.gnupg`), crypto keys, browser vaults, and system files remain completely invisible and air-gapped**.

```
+-----------------------------------------------------------------------------------+
|                                  MAYOTIX OS HOST                                  |
|                                                                                   |
|  +--------------------+     +---------------------+     +-----------------------+ |
|  |    Mayotix CLI     |     |   Gaming Center GUI |     |  System D-Bus Daemon  | |
|  |   (mayotix game)   |     |    (Qt6 / Wayland)  |     |   (mayotix-daemon)    | |
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
|  |  mayotix-gamemode.sh  |                           |   gpu-optimizer.sh    |    |
|  | (CPU Governor / Nice) |                           | (Vulkan / Mesa / DRI) |    |
|  +----------+------------+                           +----------+------------+    |
|             |                                                   |                 |
|             v                                                   v                 |
|   /sys/devices/system/cpu/cpufreq                    /dev/dri/renderD128          |
|   Governor: performance                              Mesa 24.1.0 / RADV / ANV     |
|   I/O Priority: Realtime                             Shader Cache: Isolated       |
+-------------|---------------------------------------------------|-----------------+
              |                                                   |
              v                                                   v
       +-----------------------------------------------------------------+
       |               SANDBOXED GAMING RUNTIME CONTAINER                |
       |                   (Bubblewrap + mayotix_gaming_t)               |
       |                                                                 |
       |   +---------------------------------------------------------+   |
       |   |                     Steam Client                        |   |
       |   |   +-------------------------------------------------+   |   |
       |   |   | Proton-Experimental (DXVK 2.4 / VKD3D 2.13)     |   |   |
       |   |   | Fsync (futex2) & Esync (eventfd)                |   |   |
       |   |   | Anti-Cheat Bridge: BattlEye & EAC (User Space)  |   |   |
       |   |   +-------------------------------------------------+   |   |
       |   +---------------------------------------------------------+   |
       |                                                                 |
       |   Airgap Guard: MASKED ~/.ssh, ~/.gnupg, ~/.config/mayotix      |
       +-----------------------------------------------------------------+
```

---

## 2. Core Components & Subsystems

### 2.1 Feral GameMode Controller (`mayotix-gamemode.sh`)
Located at `desktop/gaming/mayotix-gamemode.sh`, this controller dynamically optimizes system latency and hardware scheduling for gaming:
- **CPU Governor Scaling**: Transitions active CPU cores from `powersave`/`schedutil` to `performance` on launch, and seamlessly restores baselines on exit.
- **Process Priority Renicing**: Elevates game processes (`nice -n -5`) and assigns realtime I/O scheduling classes (`ionice -c 1 -n 0`).
- **Memory Management**: Activates transparent hugepages (`transparent_hugepage=always`) and tunes memory compaction.
- **Wayland Screen Inhibit**: Inhibits screen lockouts and desktop idle sleep timers during active gaming sessions.

### 2.2 GPU Driver Optimizer & Vulkan Acceleration Probe (`gpu-optimizer.sh`)
Located at `desktop/gaming/gpu-optimizer.sh`, this engine optimizes the hardware graphics stack:
- **Hardware Probing**: Detects GPU hardware, kernel DRM drivers (`amdgpu`, `i915`/`xe`, `nvidia`/`nouveau`), and registered Vulkan ICD manifests (`/usr/share/vulkan/icd.d/`).
- **Direct Rendering Nodes**: Validates `/dev/dri/card*` and `/dev/dri/renderD*` devices.
- **Shader Cache Confinement**: Isolates Mesa shader compilation caches to `/var/cache/mayotix/gaming/shaders` to prevent cross-domain cache poisoning.
- **Variable Refresh Rate (VRR)**: Configures Adaptive-Sync and Wayland tearing protocol extensions (`wp_tearing_control_v1`).

### 2.3 Proton & Wine Compatibility Engine (`proton-runner.sh`)
Located at `desktop/gaming/proton-runner.sh`, this runner orchestrates Windows game translation:
- **Translation Runtimes**: Out-of-the-box support for `Proton-Experimental`, `GE-Proton`, `Proton-8.0`, and `Wine-GE-Custom`.
- **Direct3D to Vulkan**: Bundles DXVK 2.4 (D3D9/10/11) and VKD3D-Proton 2.13 (D3D12).
- **Fast Kernel Event Synchronization**: Enables `WINEFSYNC=1` (Linux kernel `futex2`) and `WINEESYNC=1` (`eventfd`) for low CPU overhead.
- **Anti-Cheat Risk Audit**: Evaluates BattlEye and Easy Anti-Cheat (EAC) compatibility through user-space Proton bridges while strictly blocking kernel Ring 0 rootkits.

### 2.4 Sandboxed Steam & Game Container Launcher (`steam-launcher.sh`)
Located at `desktop/gaming/steam-launcher.sh`, this container engine isolates gaming runtimes:
- **Bubblewrap (`bwrap`) Sandboxing**: Mounts a read-only system root (`/usr`, `/lib64`, `/etc`), creates ephemeral `/tmp` and `/var/tmp` namespaces, and passes through DRI and Wayland sockets.
- **Strict Host Airgap**: Personal user folders, `~/.ssh` authentication keys, `~/.gnupg` cryptographic keyrings, and browser databases are masked and completely inaccessible from the game container.

### 2.5 SELinux MAC Security Profile (`mayotix_gaming.te` & `mayotix_gaming.fc`)
Located in `security/selinux/`, the Phase 10 Type Enforcement policy enforces mandatory access control:
- Declares domain `mayotix_gaming_t` and executable entry points.
- Permits DRI/DRM ioctls (`dri_device_t`), sound devices (`sound_device_t`), and Wayland client socket operations.
- Enforces an absolute airgap: **0 allow rules for `user_home_t`**.
- Prohibits `sys_ptrace` inspection of non-gaming host processes.

---

## 3. Privileged Daemon RPC Endpoints

The system daemon (`daemon/mayotix-daemon.py`) provides 7 dedicated JSON-RPC endpoints under `game.*`:

| Method | Parameters | Description |
| :--- | :--- | :--- |
| `game.status` | *none* | Queries combined GameMode, GPU, and Vulkan acceleration posture |
| `game.gamemode_start` | `pid` *(optional)* | Engages performance governor, renicing, and screen inhibitor |
| `game.gamemode_stop` | *none* | Disengages optimization and restores baseline power governors |
| `game.gpu_status` | *none* | Probes GPU DRM driver, Vulkan ICDs, and Mesa version |
| `game.proton_status` | *none* | Inspects installed Proton runtimes and DXVK/VKD3D capabilities |
| `game.launch` | `app` | Launches game binary inside sandboxed Bubblewrap container |
| `game.anticheat_audit` | *none* | Audits anti-cheat modules for user-space bridge compliance |

---

## 4. CLI Usage Reference

The unified `mayotix` CLI manages all Phase 10 gaming features:

```bash
# Check GameMode and GPU acceleration status
mayotix game status --dry-run --json

# Engage GameMode performance governor optimization
mayotix game optimize start --dry-run --json

# Restore baseline power profile
mayotix game optimize stop --dry-run --json

# Inspect GPU driver, Vulkan ICDs, and Mesa stack
mayotix game gpu --dry-run --json

# Query Proton compatibility runtimes and DXVK status
mayotix game proton --dry-run --json

# Audit anti-cheat compatibility and security risks
mayotix game anticheat --dry-run --json

# Launch sandboxed Steam client or game
mayotix game launch steam --dry-run --json
```

---

## 5. Wayland Desktop Studio GUI

Located at `desktop/gaming/mayotix-gaming-gui.py` with XDG entry `desktop/applications/mayotix-gaming.desktop`, the Gaming Center provides:
- **Tab 1: GameMode & Performance**: One-click toggle for CPU governor, process renicing, and idle inhibitor.
- **Tab 2: GPU & Vulkan Diagnostics**: Real-time inspection of DRI render nodes, Mesa stack, and shader caches.
- **Tab 3: Proton & Steam Runner**: Graphical launcher for sandboxed game binaries and Proton runtime selector.
- **Tab 4: Anti-Cheat & Host Airgap**: Visual status of SELinux domain confinement and host credential airgap.
