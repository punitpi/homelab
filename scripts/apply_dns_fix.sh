#!/bin/bash
# Quick DNS fix - applies to specified node using Tailscale IP
# Usage: ./scripts/apply_dns_fix.sh [rpi-home|rpi-friend|cloud-node]

set -e

# Map hostnames to Tailscale IPs (from inventory/hosts.ini)
declare -A HOSTS
HOSTS[rpi-home]="100.x.x.1"
HOSTS[rpi-friend]="100.x.x.2"
HOSTS[cloud-node]="100.x.x.3"

# Check if host is provided
if [ -z "$1" ]; then
    echo "❌ ERROR: Must specify host"
    echo ""
    echo "Usage: ./scripts/apply_dns_fix.sh [rpi-home|rpi-friend|cloud-node]"
    echo ""
    echo "Example: ./scripts/apply_dns_fix.sh rpi-home"
    exit 1
fi

HOST="$1"
IP="${HOSTS[$HOST]}"

if [ -z "$IP" ]; then
    echo "❌ ERROR: Unknown host '$HOST'"
    echo "Valid hosts: rpi-home, rpi-friend, cloud-node"
    exit 1
fi

echo "🔧 Fixing DNS configuration on $HOST ($IP)..."
echo ""

# Upload the fix script
echo "📤 Uploading DNS fix script..."
scp scripts/fix_dns.sh homelab@$IP:/tmp/fix_dns.sh

# Run the fix script
echo "🔄 Running DNS fix..."
ssh homelab@$IP "sudo bash /tmp/fix_dns.sh"

echo ""
echo "✅ DNS fix complete on $HOST!"
echo ""
echo "Next steps:"
echo "  1. Test DNS: ssh homelab@$IP 'nslookup registry-1.docker.io'"
echo "  2. Re-run deployment: make deploy-apps target=$HOST"
