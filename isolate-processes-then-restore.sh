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

echo "[$(date)] Getting the device for root filesystem..."
ROOT_DEVICE=$(findmnt -n -o SOURCE /)
echo "[$(date)] Root device: $ROOT_DEVICE"

echo "[$(date)] Unmounting /.snapshots..."
umount /.snapshots || true

echo "[$(date)] Unmounting / (root filesystem)..."
umount / || true

echo "[$(date)] Mounting raw filesystem to temporary location..."
TEMP_MOUNT="/mnt/btrfs_toplevel_$$"
mkdir -p "$TEMP_MOUNT"
if ! mount -o defaults "$ROOT_DEVICE" "$TEMP_MOUNT"; then
    echo "[$(date)] ERROR: Failed to mount raw filesystem."
    systemctl reboot
    exit 1
fi

echo "[$(date)] Creating writable snapshot from clean-state snapshot #$SNAPSHOT_NUM..."
if ! btrfs subvolume snapshot "$TEMP_MOUNT/.snapshots/$SNAPSHOT_NUM/snapshot" "$TEMP_MOUNT/@rootfs_restored"; then
    echo "[$(date)] ERROR: Failed to create writable snapshot."
    umount "$TEMP_MOUNT" || true
    rmdir "$TEMP_MOUNT" || true
    systemctl reboot
    exit 1
fi

echo "[$(date)] Getting restored snapshot subvolume ID from temporary mount..."
SNAPSHOT_ID=$(btrfs inspect-internal rootid "$TEMP_MOUNT/@rootfs_restored")
echo "[$(date)] Restored snapshot ID: $SNAPSHOT_ID"

echo "[$(date)] Setting restored snapshot as default root subvolume..."
if ! btrfs subvolume set-default "$SNAPSHOT_ID" "$TEMP_MOUNT"; then
    echo "[$(date)] ERROR: Failed to set default subvolume."
    umount "$TEMP_MOUNT" || true
    rmdir "$TEMP_MOUNT" || true
    systemctl reboot
    exit 1
fi

echo "[$(date)] Default subvolume set. Old root filesystem will be accessible after reboot."

echo "[$(date)] Unmounting temporary mount..."
umount "$TEMP_MOUNT" || true
rmdir "$TEMP_MOUNT" || true

echo "[$(date)] Restore complete. Rebooting..."
systemctl reboot
