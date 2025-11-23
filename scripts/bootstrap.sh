#!/bin/bash
set -euo pipefail

# Homelab Bootstrap Script for Ubuntu/Debian/Raspbian systems
# Compatible with: Ubuntu 20.04+, Debian 11+, Raspbian Bullseye+
#
# Usage: sudo bash bootstrap.sh [TIMEZONE] [SOURCE_USER]
#
# Arguments:
#   TIMEZONE    - Target timezone (default: Asia/Kolkata)
#   SOURCE_USER - User to copy SSH keys from (default: root)
#
# Examples:
#   sudo bash bootstrap.sh Europe/Vienna
#   sudo bash bootstrap.sh Asia/Kolkata pi
#   sudo bash bootstrap.sh America/New_York ubuntu

echo "--- Starting bootstrap process ---"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root. Use: sudo bash bootstrap.sh"
   exit 1
fi

# --- Parse Arguments ---
# Set timezone based on first argument or default to Asia/Kolkata
TIMEZONE="${1:-Asia/Kolkata}"
# Set source user for SSH key copying (second argument or default to root)
SOURCE_USER="${2:-root}"

echo "Configuration:"
echo "  - Timezone: $TIMEZONE"
echo "  - Source user for SSH keys: $SOURCE_USER"

# --- User Creation ---
echo "Creating 'homelab' user..."
# Create user if it doesn't exist
if ! id "homelab" &>/dev/null; then
    useradd -m -s /bin/bash -G sudo homelab
    echo "User 'homelab' created. Please set a password:"
    passwd homelab
    
    # Copy SSH keys from source user if they exist
    SOURCE_SSH_DIR="/home/$SOURCE_USER/.ssh"
    if [ "$SOURCE_USER" = "root" ]; then
        SOURCE_SSH_DIR="/root/.ssh"
    fi
    
    if [ -d "$SOURCE_SSH_DIR" ] && [ -f "$SOURCE_SSH_DIR/authorized_keys" ]; then
        echo "Copying SSH keys from $SOURCE_USER to homelab user..."
        mkdir -p /home/homelab/.ssh
        cp "$SOURCE_SSH_DIR/authorized_keys" /home/homelab/.ssh/
        chmod 700 /home/homelab/.ssh
        chmod 600 /home/homelab/.ssh/authorized_keys
        chown -R homelab:homelab /home/homelab/.ssh
        echo "SSH keys copied successfully."
    else
        echo "Warning: No SSH keys found in $SOURCE_SSH_DIR/"
        echo "SSH keys will need to be added manually before hardening."
    fi
else
    echo "User 'homelab' already exists."
    # Still copy SSH keys if they don't exist for existing user
    SOURCE_SSH_DIR="/home/$SOURCE_USER/.ssh"
    if [ "$SOURCE_USER" = "root" ]; then
        SOURCE_SSH_DIR="/root/.ssh"
    fi
    
    if [ -d "$SOURCE_SSH_DIR" ] && [ -f "$SOURCE_SSH_DIR/authorized_keys" ]; then
        if [ -f "/home/homelab/.ssh/authorized_keys" ]; then
            # Update SSH keys if they're different
            if ! cmp -s "$SOURCE_SSH_DIR/authorized_keys" "/home/homelab/.ssh/authorized_keys"; then
                echo "Updating SSH keys for homelab user..."
                cp "$SOURCE_SSH_DIR/authorized_keys" /home/homelab/.ssh/
                chmod 600 /home/homelab/.ssh/authorized_keys
                chown -R homelab:homelab /home/homelab/.ssh
                echo "SSH keys updated successfully."
            else
                echo "SSH keys are already up to date."
            fi
        else
            echo "Copying SSH keys from $SOURCE_USER to existing homelab user..."
            mkdir -p /home/homelab/.ssh
            cp "$SOURCE_SSH_DIR/authorized_keys" /home/homelab/.ssh/
            chmod 700 /home/homelab/.ssh
            chmod 600 /home/homelab/.ssh/authorized_keys
            chown -R homelab:homelab /home/homelab/.ssh
            echo "SSH keys copied successfully."
        fi
    else
        echo "Warning: No SSH keys found in $SOURCE_SSH_DIR/"
        echo "Manual SSH key setup will be required."
    fi
fi

# --- System Configuration ---
echo "Setting timezone to $TIMEZONE..."
timedatectl set-timezone "$TIMEZONE"

# --- Package Installation ---
echo "Updating package list and installing prerequisites..."
apt update
apt full-upgrade -y

# Detect distribution
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$ID
    VERSION_ID=$VERSION_ID
else
    echo "Cannot detect distribution. /etc/os-release not found."
    exit 1
fi

echo "Detected distribution: $DISTRO $VERSION_ID"

# Install base packages (common to all distributions)
BASE_PACKAGES="apt-transport-https ca-certificates curl gnupg lsb-release fail2ban ufw unattended-upgrades rclone"

# Add distribution-specific packages
case "$DISTRO" in
    "ubuntu")
        PACKAGES="$BASE_PACKAGES software-properties-common"
        ;;
    "debian")
        # Debian doesn't need software-properties-common for this setup
        PACKAGES="$BASE_PACKAGES"
        ;;
    "raspbian")
        PACKAGES="$BASE_PACKAGES"
        ;;
    *)
        echo "Warning: Unknown distribution '$DISTRO'. Using base packages only."
        PACKAGES="$BASE_PACKAGES"
        ;;
esac

echo "Installing packages: $PACKAGES"
if ! apt-get install -y $PACKAGES; then
    echo "Error: Failed to install some packages. Continuing with available packages..."
    # Try to install packages individually to identify which ones fail
    for pkg in $PACKAGES; do
        if ! apt-get install -y "$pkg"; then
            echo "Warning: Failed to install $pkg, skipping..."
        fi
    done
fi

# --- Firewall Setup (UFW) ---
echo "Configuring UFW firewall..."
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh # Allow SSH (port 22)
ufw allow 51820/udp # WireGuard for Tailscale
ufw allow 41641/udp # Tailscale pathfinding
ufw enable
echo "UFW enabled and configured."

# --- Automatic Updates ---
echo "Configuring unattended-upgrades..."
dpkg-reconfigure -plow unattended-upgrades

# --- Docker Installation ---
echo "Installing Docker and Docker Compose..."
install -m 0755 -d /etc/apt/keyrings

# Choose Docker repository based on distribution
case "$DISTRO" in
    "ubuntu")
        DOCKER_REPO="ubuntu"
        GPG_URL="https://download.docker.com/linux/ubuntu/gpg"
        ;;
    "debian"|"raspbian")
        DOCKER_REPO="debian"
        GPG_URL="https://download.docker.com/linux/debian/gpg"
        ;;
    *)
        echo "Using Debian repository as fallback for $DISTRO"
        DOCKER_REPO="debian"
        GPG_URL="https://download.docker.com/linux/debian/gpg"
        ;;
esac

curl -fsSL $GPG_URL | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$DOCKER_REPO \
  $VERSION_CODENAME stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
usermod -aG docker homelab
echo "Docker and Docker Compose installed."

# --- Tailscale Installation ---
echo "Installing Tailscale..."

# Choose Tailscale repository based on distribution
case "$DISTRO" in
    "ubuntu")
        TAILSCALE_REPO="ubuntu"
        ;;
    "debian"|"raspbian")
        TAILSCALE_REPO="debian"
        ;;
    *)
        echo "Using Debian repository as fallback for $DISTRO"
        TAILSCALE_REPO="debian"
        ;;
esac

curl -fsSL https://pkgs.tailscale.com/stable/$TAILSCALE_REPO/$VERSION_CODENAME.noarmor.gpg | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
curl -fsSL https://pkgs.tailscale.com/stable/$TAILSCALE_REPO/$VERSION_CODENAME.tailscale-keyring.list | tee /etc/apt/sources.list.d/tailscale.list
apt-get update
apt-get install -y tailscale
echo "Tailscale installed."

# --- DNS Configuration Fix (Tailscale + systemd-resolved) ---
echo "Configuring DNS to work with Tailscale and systemd-resolved..."

# This fixes conflicts between Tailscale trying to manage /etc/resolv.conf
# and systemd-resolved. We let systemd-resolved be the primary DNS manager.
# See docs/TROUBLESHOOTING.md for more details.

# Check if systemd-resolved is active
if systemctl is-active --quiet systemd-resolved; then
    echo "systemd-resolved is active - configuring proper DNS chain..."

    # Backup current resolv.conf
    if [ -f /etc/resolv.conf ] && [ ! -L /etc/resolv.conf ]; then
        cp /etc/resolv.conf /etc/resolv.conf.backup.$(date +%Y%m%d-%H%M%S)
        echo "Backed up current resolv.conf"
    fi

    # Remove existing resolv.conf (whether file or symlink)
    rm -f /etc/resolv.conf

    # Create symlink to systemd-resolved stub
    ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

    # Restart systemd-resolved to ensure proper operation
    systemctl restart systemd-resolved

    echo "DNS configuration updated:"
    echo "  - /etc/resolv.conf → systemd-resolved stub (127.0.0.53)"
    echo "  - Tailscale DNS will be configured as upstream after 'tailscale up'"
    echo "  - Use 'tailscale set --accept-dns=false' after joining to prevent conflicts"
else
    echo "systemd-resolved is not active - skipping DNS configuration"
    echo "Manual DNS setup may be required"
fi

# --- SSH Hardening (Final Step) ---
echo "--- Preparing SSH Hardening ---"

# Check if SSH keys are properly set up for homelab user
if [ -f "/home/homelab/.ssh/authorized_keys" ]; then
    KEY_COUNT=$(wc -l < /home/homelab/.ssh/authorized_keys)
    echo "Found $KEY_COUNT SSH key(s) for homelab user."
    
    echo "Hardening SSH configuration..."
    # Create backup of sshd_config
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.$(date +%Y%m%d-%H%M%S)

    # Prepare SSH hardening changes
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config
    sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
    sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config

    # Test SSH configuration
    if sshd -t; then
        echo "SSH configuration test passed."
        echo ""
        echo "⚠️  IMPORTANT: SSH will be hardened in 10 seconds!"
        echo "   - Root login will be DISABLED"
        echo "   - Password authentication will be DISABLED" 
        echo "   - You must use SSH keys to connect as 'homelab' user"
        echo ""
        echo "Press Ctrl+C now to cancel SSH hardening, or wait to continue..."
        
        # 10 second countdown
        for i in {10..1}; do
            echo -n "$i... "
            sleep 1
        done
        echo ""
        
        # Apply SSH hardening
        systemctl restart sshd
        echo "✅ SSH hardened successfully!"
        echo ""
        echo "🔑 From now on, connect using:"
        echo "   ssh homelab@$(hostname -I | awk '{print $1}')"
        echo ""
    else
        echo "❌ SSH configuration test failed. SSH hardening skipped for safety."
        echo "   Please check /etc/ssh/sshd_config manually."
    fi
else
    echo "❌ No SSH keys found for homelab user!"
    echo "   SSH hardening SKIPPED to prevent lockout."
    echo ""
    echo "To harden SSH manually after adding keys:"
    echo "1. Add your SSH public key to /home/homelab/.ssh/authorized_keys"
    echo "2. Run: sudo sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config"
    echo "3. Run: sudo sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config"
    echo "4. Run: sudo systemctl restart sshd"
fi

# --- Final Instructions ---
echo ""
echo "--- Bootstrap Complete! ---"
echo ""
echo "System Information:"
echo "  - Distribution: $DISTRO $VERSION_ID"
echo "  - Timezone: $TIMEZONE"
echo "  - Docker: Installed"
echo "  - Tailscale: Installed"
echo "  - Firewall: UFW enabled"
echo "  - SSH: $([ -f /home/homelab/.ssh/authorized_keys ] && echo 'Hardened' || echo 'Not hardened')"
echo ""
echo "Next steps:"
echo "1. Connect to Tailscale network:"
echo "   sudo tailscale up --ssh --accept-routes --authkey=YOUR_TAILSCALE_AUTH_KEY"
echo "   (Replace with a key from your Tailscale admin console)"
echo ""
echo "2. Configure DNS to prevent conflicts:"
echo "   sudo tailscale set --accept-dns=false"
echo "   (This prevents Tailscale from overwriting /etc/resolv.conf)"
echo ""
echo "3. Get your Tailscale IP: tailscale ip -4"
echo ""
echo "4. Set up your Ansible inventory with the new Tailscale IP."
echo ""
echo "5. Optional: Reboot to ensure all changes take effect: sudo reboot"
echo ""
echo "Usage:"
echo "  sudo bash bootstrap.sh [TIMEZONE] [SOURCE_USER]"
echo ""
echo "Examples:"
echo "  sudo bash bootstrap.sh Europe/Vienna           # Use Vienna timezone, copy keys from root"
echo "  sudo bash bootstrap.sh Asia/Kolkata pi         # Use Kolkata timezone, copy keys from pi user"
echo "  sudo bash bootstrap.sh America/New_York ubuntu # Use NY timezone, copy keys from ubuntu user"
