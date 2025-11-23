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
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
# Use NODE_NAME from env (falls back to hostname if not set)
NODE_NAME="${NODE_NAME:-$(hostname -s)}"
# Use RCLONE_REMOTE_NAME from common.env (defaults to b2-crypt for encryption)
RCLONE_REMOTE="${RCLONE_REMOTE_NAME:-b2-crypt}"

# For crypt remotes (like b2-crypt), the bucket is already in the remote config
# For direct remotes (like b2), we need to append the bucket
if [[ "${RCLONE_REMOTE}" == *"-crypt"* ]]; then
    # Crypt remote - bucket already included in remote config
    # All backups go under rpi-homelab-backup/ subfolder for organization
    B2_REMOTE="${RCLONE_REMOTE}:rpi-homelab-backup"
else
    # Direct remote - append bucket name
    B2_REMOTE="${RCLONE_REMOTE}:${B2_BUCKET}"
fi

BACKUP_BASE_PATH="${B2_REMOTE}/${NODE_NAME}"
BACKUP_PATH="${BACKUP_BASE_PATH}/${TIMESTAMP}"
EXCLUDE_FILE="/opt/backups/rclone-excludes.txt"

# Create exclude file
cat > ${EXCLUDE_FILE} <<EOL
**/.cache/
**/cache/
**/tmp/
**/.Trash*/
**/lost+found/
EOL

# --- Log file ---
LOG_FILE="/var/log/backup.log"
exec 1> >(tee -a "${LOG_FILE}")
exec 2>&1

echo "=========================================="
echo "Backup started at $(date)"
echo "Node: ${NODE_NAME} (hostname: $(hostname -s))"
echo "=========================================="

# --- Run DB Dump ---
echo "Running database dump script..."
/opt/backups/db_dump.sh

# --- Backup Sources ---
BACKUP_SOURCES=(
    "/opt/stacks"
    "${APPDATA_PATH}"
    "${DB_DUMP_PATH}"
)

# --- Pre-move backup logic ---
# If the 'with-media' argument is passed, include media in the backup.
if [[ "${1:-}" == "--with-media" ]]; then
    echo "--- Running PRE-MOVE backup (including media) ---"
    BACKUP_SOURCES+=("${MEDIA_PATH}")
    BACKUP_PATH="${BACKUP_BASE_PATH}/with-media_${TIMESTAMP}"
else
    echo "--- Running POST-MOVE backup (important data only) ---"
fi

# --- Test B2 Connection ---
echo "Testing Backblaze B2 connection..."
if ! rclone lsd "${B2_REMOTE}" > /dev/null 2>&1; then
    echo "ERROR: Cannot connect to Backblaze B2. Check credentials in secrets.env"
    exit 1
fi
echo "B2 connection successful."

# --- Run Rclone Backup ---
echo "Starting rclone backup to ${BACKUP_PATH}..."
for SOURCE in "${BACKUP_SOURCES[@]}"; do
    if [ -d "${SOURCE}" ]; then
        DEST_NAME=$(basename "${SOURCE}")
        echo "Backing up ${SOURCE} to ${BACKUP_PATH}/${DEST_NAME}..."
        rclone copy "${SOURCE}" "${BACKUP_PATH}/${DEST_NAME}" \
            --exclude-from="${EXCLUDE_FILE}" \
            --progress \
            --stats 30s \
            --transfers 4 \
            --checkers 8 \
            --buffer-size 32M \
            --b2-chunk-size 96M \
            --b2-upload-cutoff 200M \
            --log-level INFO
    else
        echo "WARNING: ${SOURCE} does not exist, skipping."
    fi
done

echo "Backup complete."

# --- Create Latest Symlink Marker ---
echo "Creating 'latest' marker..."
echo "${TIMESTAMP}" | rclone rcat "${BACKUP_BASE_PATH}/LATEST.txt"

# --- List Recent Backups ---
echo "Recent backups:"
rclone lsd "${BACKUP_BASE_PATH}" | tail -5

# --- Cleanup Old Backups ---
# Keep last 7 daily, 4 weekly, 6 monthly backups
echo "Cleaning up old backups (keeping last 7 backups)..."
BACKUP_COUNT=$(rclone lsd "${BACKUP_BASE_PATH}" | grep -v "with-media" | wc -l)
if [ ${BACKUP_COUNT} -gt 7 ]; then
    rclone lsd "${BACKUP_BASE_PATH}" | grep -v "with-media" | head -n $((BACKUP_COUNT - 7)) | awk '{print $NF}' | while read OLD_BACKUP; do
        echo "Deleting old backup: ${OLD_BACKUP}"
        rclone purge "${BACKUP_BASE_PATH}/${OLD_BACKUP}"
    done
fi

# --- Optional: Copy to Linode Mirror ---
if [[ "${1:-}" == "--copy-to-linode" ]]; then
    echo "--- Copying backup to Linode Object Storage ---"
    LINODE_REMOTE="s3:${LINODE_BUCKET}"

    echo "Syncing to Linode mirror..."
    rclone sync "${BACKUP_PATH}" "${LINODE_REMOTE}/${HOSTNAME}/${TIMESTAMP}" \
        --progress \
        --log-level INFO

    echo "Copy to Linode complete."
fi

echo "=========================================="
echo "Backup finished at $(date)"
echo "=========================================="
