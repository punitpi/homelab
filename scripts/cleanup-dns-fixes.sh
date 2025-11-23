#!/bin/bash
# Clean up all temporary DNS fix scripts and playbooks
# Run this after DNS is working to clean up the repository

set -e

echo "🧹 Cleaning up temporary DNS fix files..."
echo ""

# Files to remove
DNS_FIX_FILES=(
  "playbooks/fix-docker-dns.yml"
  "playbooks/diagnose-dns.yml"
  "playbooks/fix-tailscale-dns.yml"
  "playbooks/force-docker-dns-fix.yml"
  "playbooks/disable-tailscale-dns.yml"
  "playbooks/force-docker-public-dns.yml"
  "playbooks/nuclear-dns-fix.yml"
  "playbooks/test-tailscale-dns.yml"
  "scripts/fix_dns.sh"
  "scripts/apply_dns_fix.sh"
  "scripts/check-tailscale-dns-config.sh"
)

# Keep these useful files:
# - playbooks/enable-tailscale-dns.yml (useful for future nodes)
# - scripts/get-tailscale-hostnames.sh (useful for inventory updates)

echo "Removing temporary DNS fix files:"
for file in "${DNS_FIX_FILES[@]}"; do
  if [ -f "$file" ]; then
    echo "  ✓ Removing $file"
    rm "$file"
  else
    echo "  - $file (already removed)"
  fi
done

echo ""
echo "✅ Cleanup complete!"
echo ""
echo "Files kept (still useful):"
echo "  ✓ playbooks/enable-tailscale-dns.yml"
echo "  ✓ scripts/get-tailscale-hostnames.sh"
echo ""
echo "Next: Remove Docker daemon.json DNS override"
echo "  Run: ansible-playbook -i inventory/hosts.ini playbooks/remove-docker-dns-override.yml --ask-vault-pass"
