#!/usr/bin/with-contenv bash
# VS Code Server initialization script
# This script ensures the correct password is set on container startup

set -e

CONFIG_FILE="/config/.config/code-server/config.yaml"

# Wait for config file to exist (code-server creates it on first run)
echo "[code-server-init] Waiting for config file to be generated..."
for i in {1..30}; do
    if [ -f "$CONFIG_FILE" ]; then
        echo "[code-server-init] Config file found"
        break
    fi
    sleep 1
done

# Update password if config exists
if [ -f "$CONFIG_FILE" ]; then
    # Check if PASSWORD env var is set
    if [ -n "$PASSWORD" ]; then
        echo "[code-server-init] Updating password in config file..."

        # Update the password line
        sed -i "s/password: .*/password: ${PASSWORD}/" "$CONFIG_FILE"

        echo "[code-server-init] Password updated successfully"
        echo "[code-server-init] Config contents:"
        cat "$CONFIG_FILE"
    else
        echo "[code-server-init] WARNING: PASSWORD environment variable not set"
    fi
else
    echo "[code-server-init] WARNING: Config file not found at $CONFIG_FILE"
fi

echo "[code-server-init] Initialization complete"
