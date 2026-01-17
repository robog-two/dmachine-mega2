#!/bin/bash
set -euo pipefail

# This script is spawned detached and runs the filesystem restore after entering rescue mode
# It receives snapshot number and repo dir as arguments

SNAPSHOT_NUM="$1"
REPO_DIR="$2"

cd "$REPO_DIR"

echo "[$(date)] Entering rescue mode for filesystem swap..."
systemctl isolate rescue.target

# Give rescue mode a moment to settle
sleep 2

echo "[$(date)] Creating writable snapshot from clean-state snapshot #$SNAPSHOT_NUM..."
if ! btrfs subvolume snapshot -r "/.snapshots/$SNAPSHOT_NUM/snapshot" "/.root_restored"; then
    echo "[$(date)] ERROR: Failed to create writable snapshot."
    systemctl reboot
    exit 1
fi

echo "[$(date)] Swapping root filesystem with clean snapshot..."
if ! btrfs subvolume swap "/.root_restored" "/"; then
    echo "[$(date)] ERROR: Failed to swap subvolumes."
    systemctl reboot
    exit 1
fi

echo "[$(date)] Removing old filesystem..."
if ! btrfs subvolume delete "/.root_restored"; then
    echo "[$(date)] WARNING: Failed to delete old root subvolume. Continuing anyway..."
fi

echo "[$(date)] Restore complete. Rebooting..."
systemctl reboot
