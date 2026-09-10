#!/bin/bash
# MAYOTIX OS Phase 3 Week 2: Script to configure and enforce Flatpak overrides
# This script applies the global-overrides.conf to the system-wide Flatpak configuration.

set -euo pipefail

# Paths
OVERRIDES_FILE="${0%/*}/global-overrides.conf"
FLATPAK_SYSTEM_CONF_DIR="/etc/flatpak/overrides"
FLATPAK_USER_CONF_DIR="${HOME}/.var/app/overrides"  # Typically, user overrides are in ~/.local/share/flatpak/overrides
# According to Flatpak documentation, system overrides go in /etc/flatpak/overrides
# and user overrides in ~/.local/share/flatpak/overrides.

# We'll use the system directory for a system-wide enforcement.
TARGET_DIR="/etc/flatpak/overrides"
TARGET_FILE="${TARGET_DIR}/global"

# Check if the overrides file exists
if [[ ! -f "${OVERRIDES_FILE}" ]]; then
    echo "Error: Overrides file not found at ${OVERRIDES_FILE}"
    exit 1
fi

# Create the target directory if it doesn't exist
if [[ ! -d "${TARGET_DIR}" ]]; then
    mkdir -p "${TARGET_DIR}"
fi

# Copy the overrides file to the target location
cp "${OVERRIDES_FILE}" "${TARGET_FILE}"

# Set appropriate permissions (readable by all, writable only by root)
chmod 644 "${TARGET_FILE}"
chown root:root "${TARGET_FILE}"

# Optionally, we can also reload Flatpak configuration if needed.
# Flatpak does not have a reload command for overrides; they are read at app start.
# So we just inform the user that new applications will use the new overrides.

echo "Flatpak global overrides have been installed to ${TARGET_FILE}"
echo "New Flatpak applications will use these overrides."
echo "To apply to already installed applications, you may need to reinstall them or override individually."

# End of script