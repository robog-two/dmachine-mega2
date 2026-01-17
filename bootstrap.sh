#!/bin/bash
set -euo pipefail

REPO_DIR="/opt/declare-sh"
MARKER_FILE="$REPO_DIR/has-run-once"
WEBHOOK_PID_FILE="/var/run/webhook-receiver.pid"

cd "$REPO_DIR"

# ============================================================================
# LOCKED SECTION - This code exists in the Btrfs restore point snapshot
# ============================================================================
# Any changes to this section will NOT take effect until a new snapshot is made.
# This ensures the system can always pull the latest configuration from Git.
#
# PATH 1 (First run after restore): BOOTSTRAP=0, no marker file
#   → Pulls from Git, re-executes with BOOTSTRAP=1, then EXITS via exec
#
# PATH 3 (Normal boot): BOOTSTRAP=0, marker file exists
#   → Skips this entire block, continues to webhook startup below
# ============================================================================
if [ "${BOOTSTRAP:-0}" != "1" ]; then
    if [ ! -f "$MARKER_FILE" ]; then
        # PATH 1 ONLY: First run after restore
        echo "[PATH 1] First run detected. Pulling latest configuration from Git..."

        # Wait for DNS to be available before attempting git operations
        echo "[PATH 1] Waiting for DNS resolution..."
        for i in {1..30}; do
            if getent hosts github.com >/dev/null 2>&1; then
                echo "[PATH 1] DNS is ready"
                break
            fi
            echo "[PATH 1] Waiting for DNS... ($i/30)"
            sleep 1
        done

        git fetch origin
        git reset --hard origin/main

        echo "[PATH 1] Re-executing bootstrap.sh with updated code..."
        export BOOTSTRAP=1
        exec "$0" "$@"
        # exec replaces this process - script will NOT continue past this line
    else
        # PATH 3: Normal boot - pull updates
        echo "[PATH 3] Normal boot - marker exists, pulling updates from Git..."

        # Wait for DNS to be available before attempting git operations
        echo "[PATH 3] Waiting for DNS resolution..."
        for i in {1..30}; do
            if getent hosts github.com >/dev/null 2>&1; then
                echo "[PATH 3] DNS is ready"
                break
            fi
            echo "[PATH 3] Waiting for DNS... ($i/30)"
            sleep 1
        done

        git fetch origin
        git reset --hard origin/main
        echo "[PATH 3] Configuration updated from Git"
    fi
fi
# ============================================================================
# END OF LOCKED SECTION
# ============================================================================

# ============================================================================
# The code below runs in TWO scenarios:
#
# PATH 2 (Second run, first boot): BOOTSTRAP=1, no marker file
#   → Came from PATH 1 exec above
#   → Installs Deno, starts webhook, runs initialize.sh, creates marker
#
# PATH 3 (Normal boot): BOOTSTRAP=0, marker file exists
#   → System restarted, marker exists
#   → Already pulled latest from Git in locked section
#   → Installs Deno (if needed), starts webhook, skips initialize.sh
# ============================================================================

# BOTH PATHS: Install Deno if not present
if ! command -v deno &> /dev/null; then
    echo "Installing Deno..."
    apt install -y 7zip
    curl -fsSL https://deno.land/install.sh | sh -s -- -y
    export DENO_INSTALL="/.deno"
    export PATH="$DENO_INSTALL/bin:$PATH"
fi

# BOTH PATHS: Start webhook receiver
echo "Starting webhook receiver..."
if [ -f "$WEBHOOK_PID_FILE" ]; then
    OLD_PID=$(cat "$WEBHOOK_PID_FILE")
    if kill -0 "$OLD_PID" 2>/dev/null; then
        echo "Stopping old webhook receiver (PID: $OLD_PID)..."
        kill "$OLD_PID" || true
    fi
fi

deno run --allow-net --allow-run "$REPO_DIR/webhook-receiver.ts" &
echo $! > "$WEBHOOK_PID_FILE"
echo "Webhook receiver started (PID: $(cat $WEBHOOK_PID_FILE))"

# PATH 2 only: First-time initialization
if [ "${BOOTSTRAP:-0}" = "1" ] && [ ! -f "$MARKER_FILE" ]; then
    echo "[PATH 2] Running first-time initialization..."
    # Fork initialize.sh in background so failures don't block webhook startup
    bash "$REPO_DIR/initialize.sh" &
    INIT_PID=$!
    echo "[PATH 2] Initialization process started (PID: $INIT_PID)"

    echo "[PATH 2] Creating marker file..."
    touch "$MARKER_FILE"
    echo "[PATH 2] First boot complete."
fi

echo "System ready."
