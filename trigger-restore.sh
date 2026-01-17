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
    echo "[$(date)] Spawning isolated restore process..."

    # Spawn the restore script detached so it survives systemctl isolate
    # Use nohup and & to detach from cron/current process group
    nohup bash "$REPO_DIR/isolate-processes-then-restore.sh" "$SNAPSHOT_NUM" "$REPO_DIR" > /var/log/declare-sh-restore.log 2>&1 &

    echo "[$(date)] Restore process spawned (PID: $!). Exiting to allow it to continue..."
    exit 0
else
    echo "[$(date)] No changes detected. System is up to date."
fi
