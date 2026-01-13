#!/bin/bash
set -euo pipefail

# Parse command line arguments
REPO_URL="${1:-}"

echo "=== Declare-sh First Run Initialization ==="
echo "This script will:"
echo "  1. Install Git, Btrfs tools, and Snapper"
echo "  2. Clone the declare-sh repository to /opt/declare-sh"
echo "  3. Install the daily cron job failsafe"
echo "  4. Install the systemd service"
echo "  5. Configure Snapper and create clean-state snapshot"
echo "  6. Restart the system"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

# Get repository URL if not provided
if [ -z "$REPO_URL" ]; then
    read -r -p "Enter the Git repository URL: " REPO_URL
    if [ -z "$REPO_URL" ]; then
        echo "ERROR: Repository URL cannot be empty"
        exit 1
    fi
fi

# Install git, btrfs-progs, and snapper (Debian only)
echo "=== Installing Git, Btrfs tools, and Snapper ==="
apt-get update
apt-get install -y git btrfs-progs snapper
echo "Git, Btrfs tools, and Snapper installed successfully."

# Clone repository to /opt/declare-sh
echo ""
echo "=== Cloning repository ==="
if [ -d "/opt/declare-sh" ]; then
    echo "WARNING: /opt/declare-sh already exists. Removing..."
    rm -rf /opt/declare-sh
fi

git clone "$REPO_URL" /opt/declare-sh
echo "Repository cloned successfully."

# Make scripts executable
echo ""
echo "=== Setting script permissions ==="
chmod +x /opt/declare-sh/*.sh
echo "Scripts made executable."

# Install daily cron job failsafe
echo ""
echo "=== Installing daily cron job failsafe ==="
CRON_JOB="0 0 * * * root /opt/declare-sh/trigger-restore.sh"
CRON_FILE="/etc/cron.d/declare-sh-restore"

cat > "$CRON_FILE" <<EOF
# Daily failsafe check for configuration updates
# Runs every day at midnight
$CRON_JOB
EOF

chmod 0644 "$CRON_FILE"
echo "Cron job installed to $CRON_FILE"

# Install systemd service
echo ""
echo "=== Installing systemd service ==="
cp /opt/declare-sh/run-after-restore.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable run-after-restore.service
echo "Systemd service installed and enabled."

# Configure Snapper and create initial snapshot
echo ""
echo "=== Configuring Snapper for root filesystem ==="

# Detect root filesystem
ROOT_FS=$(findmnt -n -o SOURCE /)
ROOT_MOUNT=$(findmnt -n -o TARGET /)

echo "Root filesystem: $ROOT_FS"
echo "Root mount point: $ROOT_MOUNT"

# Check if root is on Btrfs
if ! btrfs filesystem show "$ROOT_FS" &>/dev/null; then
    echo "WARNING: Root filesystem is not Btrfs. Snapshot creation skipped."
    echo "You will need to manually configure restore functionality for your filesystem."
else
    echo "Btrfs root filesystem detected. Setting up Snapper..."

    # Create snapper config for root if it doesn't exist
    if ! snapper -c root list &>/dev/null; then
        echo "Creating snapper configuration for root..."
        snapper -c root create-config /
        echo "Snapper configuration created."
    else
        echo "Snapper configuration for root already exists."
    fi

    # Configure snapper settings for declarative infrastructure
    echo "Configuring snapper settings..."
    snapper -c root set-config \
        TIMELINE_CREATE="no" \
        TIMELINE_CLEANUP="no" \
        NUMBER_LIMIT="10" \
        NUMBER_LIMIT_IMPORTANT="5"

    echo "Snapper settings configured:"
    echo "  - Timeline snapshots: disabled (we manage snapshots manually)"
    echo "  - Number limit: 10 snapshots"
    echo "  - Important snapshots limit: 5"

    # Delete the default snapshot that snapper creates
    if snapper -c root list | grep -q "^0 "; then
        echo "Removing default snapper snapshot..."
        snapper -c root delete 0 2>/dev/null || true
    fi

    # Create the clean-state snapshot
    echo "Creating clean-state snapshot..."
    if ! snapper -c root create --description "clean-state" --cleanup-algorithm number --userdata "important=yes"; then
        echo "ERROR: Failed to create snapshot with snapper."
        echo "Cannot proceed without a valid snapshot for restore functionality."
        exit 1
    fi

    # Verify snapshot creation using CSV output for reliable parsing
    SNAPSHOT_NUM=$(snapper -c root --csvout list --columns number,description | \
        grep ",clean-state$" | \
        cut -d',' -f1 | \
        tail -n 1)

    if [ -n "$SNAPSHOT_NUM" ]; then
        echo "Clean-state snapshot created: #$SNAPSHOT_NUM"
    else
        echo "ERROR: Snapshot creation command succeeded but snapshot not found in list."
        echo "Available snapshots:"
        snapper -c root list
        echo ""
        echo "Cannot proceed without a valid snapshot for restore functionality."
        exit 1
    fi

    # This snapshot will be used for rollback when configuration changes are detected
    echo "Snapshot configured for automatic restore."
    echo ""
    echo "NOTE: This system uses Snapper for automatic restore to clean state."
    echo "      When trigger-restore.sh detects new commits, it performs a"
    echo "      'snapper rollback' to this snapshot, then reboots the system."
    echo "      After reboot, bootstrap.sh applies the new configuration from Git."
fi

# Final message
echo ""
echo "=== Installation Complete ==="
echo "The system will now restart to begin the declarative management cycle."
echo ""
read -r -p "Press Enter to restart now, or Ctrl+C to cancel..."

systemctl reboot
