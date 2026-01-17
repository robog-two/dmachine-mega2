#!/bin/bash
set -euo pipefail

REPO_DIR="/opt/declare-sh"

cd "$REPO_DIR"

echo "[$(date)] Checking for configuration updates..."

# Fetch latest changes from Git
git fetch origin

# Get current and remote HEAD commits
LOCAL_HEAD=$(git rev-parse HEAD)
REMOTE_HEAD=$(git rev-parse origin/main)

echo "[$(date)] Local HEAD:  $LOCAL_HEAD"
echo "[$(date)] Remote HEAD: $REMOTE_HEAD"

# Compare commits
if [ "$LOCAL_HEAD" != "$REMOTE_HEAD" ]; then
    echo "[$(date)] Changes detected. Restoring to clean-state snapshot..."

    # Check if snapper is available
    if ! command -v snapper &> /dev/null; then
        echo "[$(date)] ERROR: snapper not found. Cannot restore snapshot."
        echo "[$(date)] Falling back to reboot without restore."
        systemctl reboot
        exit 0
    fi

    # Find the clean-state snapshot using CSV output for reliable parsing
    # Using --csvout ensures consistent, parseable output format
    SNAPSHOT_NUM=$(snapper -c root --csvout list --columns number,description | \
        grep ",clean-state$" | \
        cut -d',' -f1 | \
        head -n 1)

    if [ -z "$SNAPSHOT_NUM" ]; then
        echo "[$(date)] ERROR: No clean-state snapshot found."
        echo "[$(date)] Available snapshots:"
        snapper -c root list
        echo "[$(date)] Falling back to reboot without restore."
        systemctl reboot
        exit 0
    fi

    echo "[$(date)] Found clean-state snapshot: #$SNAPSHOT_NUM"
    echo "[$(date)] Performing restore..."

    # Get the current default subvolume
    CURRENT_SUBVOL=$(btrfs subvolume get-default / | awk '{print $NF}')
    echo "[$(date)] Current subvolume: $CURRENT_SUBVOL"

    # Create a writable snapshot from the read-only clean-state snapshot
    echo "[$(date)] Creating writable copy from clean-state snapshot..."
    if ! btrfs subvolume snapshot "/home/.snapshots/$SNAPSHOT_NUM/snapshot" "/.root_restored"; then
        echo "[$(date)] ERROR: Failed to create writable snapshot."
        echo "[$(date)] Falling back to reboot without restore."
        systemctl reboot
        exit 1
    fi

    # Swap the subvolumes so the clean state becomes the root filesystem
    # After swap: "/" contains clean filesystem, "/.root_restored" contains old modified filesystem
    echo "[$(date)] Swapping root filesystem with clean snapshot..."
    if ! btrfs subvolume swap "/.root_restored" "/"; then
        echo "[$(date)] ERROR: Failed to swap subvolumes."
        echo "[$(date)] Falling back to reboot without restore."
        systemctl reboot
        exit 1
    fi

    # Delete the old root filesystem (now at /.root_restored)
    echo "[$(date)] Removing old filesystem..."
    if ! btrfs subvolume delete "/.root_restored"; then
        echo "[$(date)] WARNING: Failed to delete old root subvolume. Continuing anyway..."
    fi

    echo "[$(date)] Restore complete. Rebooting to verify..."

    # Trigger system reboot
    systemctl reboot
else
    echo "[$(date)] No changes detected. System is up to date."
fi
