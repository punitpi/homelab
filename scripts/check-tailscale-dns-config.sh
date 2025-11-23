#!/bin/bash
# Check what DNS configuration Tailscale is actually using
# This helps diagnose DNS forwarding issues

echo "🔍 Checking Tailscale DNS Configuration..."
echo ""

echo "=== From Tailscale's Perspective ==="
ansible rpi-home -i inventory/hosts.ini -m shell -a "tailscale status --json | jq '{MagicDNSSuffix, DNS, CurrentTailnet: {MagicDNSEnabled, MagicDNS}}'" --ask-vault-pass

echo ""
echo "=== What DNS Servers Are Actually Configured ==="
ansible rpi-home -i inventory/hosts.ini -m shell -a "resolvectl status | grep -A 5 'Current DNS'" --ask-vault-pass

echo ""
echo "=== Testing Direct Queries ==="
echo "1. Via Tailscale DNS (100.100.100.100):"
ansible rpi-home -i inventory/hosts.ini -m shell -a "nslookup ghcr.io 100.100.100.100" --ask-vault-pass 2>&1 | grep -A 10 "CHANGED\|FAILED"

echo ""
echo "2. Via Cloudflare (1.1.1.1):"
ansible rpi-home -i inventory/hosts.ini -m shell -a "nslookup ghcr.io 1.1.1.1" --ask-vault-pass 2>&1 | grep -A 10 "CHANGED"

echo ""
echo "=== Possible Issues ==="
echo "- If Tailscale DNS shows no nameservers, check Tailscale admin console"
echo "- If you see 127.0.0.53, systemd-resolved is intercepting DNS"
echo "- If you see any IP ending in .1 (like 10.1.1.1), that's your router DNS"
echo ""
echo "🔗 Check your Tailscale DNS settings:"
echo "   https://login.tailscale.com/admin/dns"
