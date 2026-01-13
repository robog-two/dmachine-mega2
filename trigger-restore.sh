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
    echo "[$(date)] Performing rollback..."

    # Perform the rollback
    snapper -c root rollback "$SNAPSHOT_NUM"

    echo "[$(date)] Rollback prepared. Rebooting to complete restore..."

    # Trigger system reboot
    systemctl reboot
else
    echo "[$(date)] No changes detected. System is up to date."
fi
