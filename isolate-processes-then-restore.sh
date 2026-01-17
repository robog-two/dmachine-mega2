#!/bin/bash
set -euo pipefail

# This script is spawned detached and runs the filesystem restore after entering rescue mode
# It receives snapshot number and repo dir as arguments

SNAPSHOT_NUM="$1"
REPO_DIR="$2"

cd "$REPO_DIR"

echo "[$(date)] Entering rescue mode for filesystem swap..."
systemctl isolate rescue.target

# Wait for rescue mode to be ready - check that we're in rescue.target
echo "[$(date)] Waiting for rescue mode to settle..."
for i in {1..30}; do
    if systemctl is-system-running | grep -q "degraded\|running"; then
        echo "[$(date)] Rescue mode ready"
        break
    fi
    echo "[$(date)] Waiting... ($i/30)"
    sleep 1
done

sleep 2

echo "[$(date)] Making root filesystem read-write..."
mount -o remount,rw / || true

echo "[$(date)] Unsetting btrfs read-only property..."
btrfs property set / ro false || true

echo "[$(date)] Checking if /.snapshots is mounted read-only..."
if mount | grep -q "on /.snapshots"; then
    echo "[$(date)] Remounting /.snapshots as read-write..."
    mount -o remount,rw /.snapshots || true
fi

echo "[$(date)] Creating writable snapshot from clean-state snapshot #$SNAPSHOT_NUM..."
if ! btrfs subvolume snapshot "/.snapshots/$SNAPSHOT_NUM/snapshot" "/.root_restored"; then
    echo "[$(date)] ERROR: Failed to create writable snapshot."
    echo "[$(date)] Checking mount and permissions..."
    mount | grep "on / "
    btrfs property get / ro
    mount | grep snapshots || true
    systemctl reboot
    exit 1
fi

echo "[$(date)] Getting snapshot subvolume ID..."
SNAPSHOT_ID=$(btrfs inspect-internal rootid "/.root_restored")
echo "[$(date)] Snapshot ID: $SNAPSHOT_ID"

echo "[$(date)] Setting restored snapshot as default root subvolume..."
if ! btrfs subvolume set-default "$SNAPSHOT_ID" /; then
    echo "[$(date)] ERROR: Failed to set default subvolume."
    systemctl reboot
    exit 1
fi

echo "[$(date)] Getting current root subvolume ID..."
CURRENT_ROOT_ID=$(btrfs inspect-internal rootid /)
echo "[$(date)] Current root ID: $CURRENT_ROOT_ID"

# Note: We can't delete the old root subvolume because it's the current /
# It will be accessible as a subvolume after reboot and can be cleaned up manually

echo "[$(date)] Restore complete. Rebooting..."
systemctl reboot
