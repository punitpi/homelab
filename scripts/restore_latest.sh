#!/bin/bash
set -euo pipefail

# Use homelab user's rclone config even when running as root
export RCLONE_CONFIG=/home/homelab/.config/rclone/rclone.conf

# Load environment variables (local.env last to override common.env)
export $(grep -v '^#' /opt/stacks/env/common.env | xargs)
export $(grep -v '^#' /opt/stacks/env/secrets.env | xargs)
if [ -f /opt/stacks/env/local.env ]; then
    export $(grep -v '^#' /opt/stacks/env/local.env | xargs)
fi

# --- Configuration ---
# Use NODE_NAME from env (falls back to hostname if not set)
CURRENT_NODE="${NODE_NAME:-$(hostname -s)}"
# Use RCLONE_REMOTE_NAME from common.env (defaults to b2-crypt for encryption)
RCLONE_REMOTE="${RCLONE_REMOTE_NAME:-b2-crypt}"

# For crypt remotes (like b2-crypt), the bucket is already in the remote config
# For direct remotes (like b2), we need to append the bucket
if [[ "${RCLONE_REMOTE}" == *"-crypt"* ]]; then
    # Crypt remote - bucket already included in remote config
    # All backups are under rpi-homelab-backup/ subfolder
    B2_REMOTE="${RCLONE_REMOTE}:rpi-homelab-backup"
else
    # Direct remote - append bucket name
    B2_REMOTE="${RCLONE_REMOTE}:${B2_BUCKET}"
fi

# Parse arguments - handle --test flag first
TEST_MODE=false
# Default to restoring from current node's own backups
RESTORE_SOURCE_HOST="${CURRENT_NODE}"

# Check if --test flag is present in any argument
for arg in "$@"; do
    if [[ "$arg" == "--test" ]]; then
        TEST_MODE=true
    elif [[ ! "$arg" == --* ]]; then
        # Not a flag, must be source node name
        RESTORE_SOURCE_HOST="$arg"
    fi
done

echo "=========================================="
echo "Restore process started at $(date)"
echo "=========================================="

# --- Test Mode ---
if [[ "$TEST_MODE" == "true" ]]; then
    echo "--- Running NON-DESTRUCTIVE test restore ---"
    TEST_PATH="/tmp/rclone_restore_test"
    mkdir -p ${TEST_PATH}

    echo "Finding latest backup for host: ${RESTORE_SOURCE_HOST}"
    LATEST_BACKUP=$(rclone lsd "${B2_REMOTE}/${RESTORE_SOURCE_HOST}" | grep -v "with-media" | tail -1 | awk '{print $NF}')

    if [ -z "${LATEST_BACKUP}" ]; then
        echo "ERROR: No backups found for host '${RESTORE_SOURCE_HOST}'"
        exit 1
    fi

    echo "Latest backup found: ${LATEST_BACKUP}"
    echo "Restoring to temporary directory: ${TEST_PATH}"

    rclone copy "${B2_REMOTE}/${RESTORE_SOURCE_HOST}/${LATEST_BACKUP}" "${TEST_PATH}" \
        --progress \
        --log-level INFO

    echo "Test restore complete. Check the contents of ${TEST_PATH}"
    echo "To clean up, run: rm -rf ${TEST_PATH}"
    exit 0
fi

# --- Destructive Restore ---
echo "WARNING: This will restore data and may overwrite existing files!"
echo "Restoring from host: ${RESTORE_SOURCE_HOST}"
read -p "Are you sure you want to continue? (yes/no): " CONFIRM

if [ "${CONFIRM}" != "yes" ]; then
    echo "Restore cancelled."
    exit 0
fi

# --- Stop Services ---
echo "Stopping Docker stacks to prevent data corruption..."
docker compose -f /opt/stacks/apps/compose.yml down 2>/dev/null || echo "Apps stack not running."
docker compose -f /opt/stacks/base/compose.yml down 2>/dev/null || echo "Base stack not running."
echo "Services stopped."

# --- Find Latest Backup ---
echo "Finding latest backup for host: ${RESTORE_SOURCE_HOST}"
LATEST_BACKUP=$(rclone lsd "${B2_REMOTE}/${RESTORE_SOURCE_HOST}" | grep -v "with-media" | tail -1 | awk '{print $NF}')

if [ -z "${LATEST_BACKUP}" ]; then
    echo "ERROR: No backups found for host '${RESTORE_SOURCE_HOST}'"
    exit 1
fi

echo "Latest backup found: ${LATEST_BACKUP}"
BACKUP_PATH="${B2_REMOTE}/${RESTORE_SOURCE_HOST}/${LATEST_BACKUP}"

# --- Restore Stacks ---
if rclone lsd "${BACKUP_PATH}/stacks" > /dev/null 2>&1; then
    echo "Restoring /opt/stacks..."
    rclone copy "${BACKUP_PATH}/stacks" "/opt/stacks" \
        --progress \
        --log-level INFO
else
    echo "WARNING: No stacks directory found in backup, skipping."
fi

# --- Restore Application Data ---
if rclone lsd "${BACKUP_PATH}/appdata" > /dev/null 2>&1; then
    echo "Restoring ${APPDATA_PATH}..."
    rclone copy "${BACKUP_PATH}/appdata" "${APPDATA_PATH}" \
        --progress \
        --log-level INFO
else
    echo "WARNING: No appdata directory found in backup, skipping."
fi

# --- Restore Database Dumps ---
if rclone lsd "${BACKUP_PATH}/db_dumps" > /dev/null 2>&1; then
    echo "Restoring database dumps..."
    rclone copy "${BACKUP_PATH}/db_dumps" "${DB_DUMP_PATH}" \
        --progress \
        --log-level INFO
else
    echo "No database dumps found in backup (optional, skipping)."
fi

echo "Restore complete."

# --- Final Instructions ---
echo "=========================================="
echo "Restore process finished at $(date)"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Manually verify the restored data in /opt/stacks"
echo "2. If database dumps were restored, check ${DB_DUMP_PATH}"
echo "3. Restart the stacks using:"
echo "   make deploy-base"
echo "   make deploy-apps target=${CURRENT_NODE}"
echo ""
