#!/bin/bash
# Get Tailscale hostnames for all nodes
# This helps update inventory after enabling MagicDNS

echo "Fetching Tailscale hostnames from all nodes..."
echo ""

echo "rpi-home:"
ansible rpi-home -i inventory/hosts.ini -m shell -a "tailscale status --json | jq -r '.Self.DNSName' | sed 's/\.$//' " --ask-vault-pass 2>/dev/null | grep -v "rpi-home |"

echo ""
echo "rpi-friend:"
ansible rpi-friend -i inventory/hosts.ini -m shell -a "tailscale status --json | jq -r '.Self.DNSName' | sed 's/\.$//' " --ask-vault-pass 2>/dev/null | grep -v "rpi-friend |"

echo ""
echo "cloud-node:"
ansible cloud-node -i inventory/hosts.ini -m shell -a "tailscale status --json | jq -r '.Self.DNSName' | sed 's/\.$//' " --ask-vault-pass 2>/dev/null | grep -v "cloud-node |"

echo ""
echo "Done. Use these hostnames to update inventory/hosts.ini"
