# MAYOTIX OS Phase 3 Week 1: Wayland Compositor & Hardened Display Server

## Objective
Replace the legacy X11 display server with a hardened Wayland compositor (based on sway or labwc) to provide a secure graphical environment with minimized attack surface.

## Deliverables
1. **Hardened Sway Configuration** (`desktop/compositor/sway.config`)
   - Disables unwanted IPC, screenshot/screen recording, and clipboard snooping.
   - Minimalist, dark-mode security aesthetic.
   - Keybindings for launcher (`rofi`), terminal (`alacritty`), and Security Center (`mayotix-security-center`).

2. **Secure Session Wrapper** (`desktop/compositor/session-start.sh`)
   - Sanitizes environment variables, drops unnecessary privileges.
   - Starts the Wayland compositor (sway) under a systemd user session.

3. **Status Bar** (`desktop/compositor/waybar.config` & `style.css`)
   - Displays live security indicators: SELinux status, firewall status, pending updates.
   - Uses JetBrains Mono font, dark theme.

4. **SELinux Policy** (`security/selinux/mayotix_desktop.te`)
   - Defines the `mayotix_compositor_t` domain.
   - Confines the compositor with least privilege: access to binaries, config, tmp, var, limited home.
   - Allows necessary DBus and IPC for session management.

## Setup and Build Instructions

### Prerequisites
- Linux system with root access (Fedora 40+ recommended).
- Packages: sway, waybar, alacritty, rofi, libinput, seatd, dbus, selinux-policy-dev, policycoreutils, make, gcc.
- SELinux in enforcing mode.

### Build the SELinux Policy Module
```bash
# Navigate to the SELinux directory
cd security/selinux

# Compile the policy module
make -f /usr/share/selinux/devel/Makefile mayotix_desktop.pp

# Install the module (requires root)
sudo semodule -i mayotix_desktop.pp

# Verify installation
sudo semodule -l | grep mayotix_desktop
```

### Install and Configure Sway
```bash
# Copy the sway config to the user's config directory
mkdir -p ~/.config/sway
cp desktop/compositor/sway.config ~/.config/sway/config

# Copy session-start.sh to a location in PATH (e.g., /usr/local/bin)
sudo cp desktop/compositor/session-start.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/session-start.sh

# Copy waybar config and style
mkdir -p ~/.config/waybar
cp desktop/compositor/waybar.config ~/.config/waybar/config
cp desktop/compositor/style.css ~/.config/waybar/style.css

# Ensure the script to get SELinux status exists (placeholder)
# You will need to create ~/scripts/get-selinux-status.sh, etc., later.
```

### Start the Session via systemd User Service
Create a systemd user service to launch the session:

```ini
# ~/.config/systemd/user/wayland-session.service
[Unit]
Description=MAYOTIX Wayland Session
After=graphical-session.target

[Service]
ExecStart=/usr/local/bin/session-start.sh
Restart=always
ExecStartPre=-/bin/pkill -f sway

[Install]
WantedBy=default.target
```

Enable and start:
```bash
systemctl --user daemon-reload
systemctl --user enable wayland-session.service
systemctl --user start wayland-session.service
```

### Verification
- After login, you should see the Wayland desktop with the dark theme and waybar at the top.
- Check SELinux status: `ps -eZ | grep mayotix_compositor_t` should show the compositor running in the custom domain.
- Test keybindings:
  - `Super + Return` opens terminal.
  - `Super + Space` opens launcher.
  - `Super + Shift + S` opens Security Center (once implemented).
- Verify that screenshot and screen recording are not bound by default (attempting to use typical shortcuts like `Print` should do nothing unless you bind them).
- Confirm that no clipboard manager is running (unless you add one later).

## Security Features
- **Environment Sanitization**: The session-start.sh script unsets potentially dangerous environment variables (LD_PRELOAD, PYTHONPATH, etc.) and sets a minimal PATH.
- **Privilege Dropping**: The script runs as the user; systemd can be configured to drop capabilities further (not shown here but can be added to the service file).
- **IPC Restriction**: By not binding keys for screenshot/screen recording and not installing a clipboard manager, we reduce the attack surface for IPC-based exploits.
- **SELinux Confinement**: The compositor runs in a dedicated domain (`mayotix_compositor_t`) with limited access to files, directories, and capabilities.
- **Minimalist Design**: Reduced features mean fewer lines of code and fewer potential vulnerabilities.

## Next Steps
- Week 2: Integrate Flatpak and Bubblewrap for application sandboxing.
- Week 3: Develop the Mayotix Security Center GUI to display live security data.
- Week 4: Implement disposable workspace sessions.
- Week 5: Perform end-to-end verification and build the Phase 3 ISO.

---
*MAYOTIX Development Team*  
*Document Version: 1.0*  
*Date: 2026-09-10*