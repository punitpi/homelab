#!/bin/bash
# Fix DNS resolution issues by configuring Tailscale to use public DNS servers
# Run this on nodes experiencing DNS resolution failures

set -e

echo "🔧 Fixing DNS configuration..."

# Check if running with sudo
if [ "$EUID" -ne 0 ]; then
  echo "❌ Please run with sudo: sudo bash $0"
  exit 1
fi

# Configure Tailscale to use Cloudflare and Google DNS as nameservers
echo "📡 Configuring Tailscale DNS settings..."
tailscale set --accept-dns=true

# Alternative: If you want to use specific DNS servers instead of MagicDNS
# tailscale set --accept-dns=false

# Add fallback DNS servers to system resolver
echo "🌐 Adding fallback DNS servers..."
cat > /etc/systemd/resolved.conf.d/tailscale-dns-fix.conf << 'EOF'
[Resolve]
DNS=1.1.1.1 8.8.8.8
FallbackDNS=1.0.0.1 8.8.4.4
Domains=~.
EOF

# Create directory if it doesn't exist
mkdir -p /etc/systemd/resolved.conf.d/

# Write the config file
cat > /etc/systemd/resolved.conf.d/tailscale-dns-fix.conf << 'EOF'
[Resolve]
DNS=1.1.1.1 8.8.8.8
FallbackDNS=1.0.0.1 8.8.4.4
EOF

# Restart systemd-resolved
echo "🔄 Restarting DNS resolver..."
systemctl restart systemd-resolved

# Test DNS resolution
echo "🧪 Testing DNS resolution..."
if nslookup registry-1.docker.io > /dev/null 2>&1; then
  echo "✅ DNS resolution working! registry-1.docker.io resolves successfully"
else
  echo "⚠️  DNS still not working, trying alternative method..."

  # Fallback: Configure Docker daemon to use specific DNS
  echo "🐳 Configuring Docker daemon DNS..."
  mkdir -p /etc/docker
  cat > /etc/docker/daemon.json << 'EOF'
{
  "dns": ["1.1.1.1", "8.8.8.8", "1.0.0.1"]
}
EOF

  systemctl restart docker
  echo "✅ Docker daemon restarted with custom DNS"
fi

echo ""
echo "✅ DNS fix complete!"
echo ""
echo "Next steps:"
echo "1. Test DNS: nslookup registry-1.docker.io"
echo "2. Re-run deployment: make deploy-apps target=rpi-home"
