# DNS Configuration - Working Setup

## Final Working Configuration

**Date:** October 2025
**Status:**  Working

### Tailscale MagicDNS Settings

Configure at: https://login.tailscale.com/admin/dns

```
MagicDNS: [ON]

Global nameservers:
  • 1.1.1.1 (Cloudflare)
  • 8.8.8.8 (Google)

Override local DNS: (EMPTY - DO NOT USE)
Split DNS: (EMPTY - DO NOT USE)
```

### How It Works

1. **MagicDNS enabled** on all nodes (`tailscale set --accept-dns=true`)
2. **Tailscale DNS (100.100.100.100)** handles ALL DNS queries:
   - `.ts.net` domains → Resolved by Tailscale
   - Public domains (e.g., `ghcr.io`, `registry-1.docker.io`) → Forwarded to 1.1.1.1 and 8.8.8.8
3. **Docker** uses system DNS (Tailscale DNS) automatically
4. **Hostnames** work everywhere: `ub-house-green` instead of `100.88.245.35`

### Benefits

-  Use hostnames instead of IP addresses in inventory
-  Automatic DNS for all services
-  Centralized DNS management via Tailscale admin console
-  Docker can pull images from public registries
-  No special Docker daemon.json configuration needed

### Inventory Configuration

```ini
# inventory/hosts.ini
[rpi_nodes]
rpi-home ansible_host=ub-house-green      # Tailscale hostname
rpi-friend ansible_host=ub-friend-blue     # Tailscale hostname

[cloud_nodes]
cloud-node ansible_host=100.98.185.81      # Tailscale IP (can use hostname after installing jq)
```

### Node Hostnames

| Node | Tailscale Hostname | IP Address |
|------|-------------------|------------|
| rpi-home | `ub-house-green.tailb99699.ts.net` | 100.88.245.35 |
| rpi-friend | `ub-friend-blue.tailb99699.ts.net` | 100.119.194.61 |
| cloud-node | (hostname TBD) | 100.98.185.81 |

### Common Issues (SOLVED)

####  Problem: "server misbehaving" errors

**Root Cause:** "Override local DNS" was configured in Tailscale admin console, pointing to non-existent AdGuard DNS

**Solution:**
1. Go to https://login.tailscale.com/admin/dns
2. Remove ANY entries under "Override local DNS"
3. Ensure "Global nameservers" has 1.1.1.1 and 8.8.8.8
4. Restart Tailscale: `sudo systemctl restart tailscaled`

####  Problem: Split DNS blocking public queries

**Root Cause:** Split DNS was enabled, only forwarding specific domains

**Solution:** Disable Split DNS or leave it empty

### Testing DNS

```bash
# Test Tailscale DNS forwarding
ansible rpi-home -i inventory/hosts.ini -m shell -a "nslookup ghcr.io 100.100.100.100" --ask-vault-pass

# Test Docker DNS
ansible rpi-home -i inventory/hosts.ini -b -m shell -a "docker run --rm alpine nslookup registry-1.docker.io" --ask-vault-pass

# Test Docker image pull
ansible rpi-home -i inventory/hosts.ini -b -m shell -a "docker pull alpine:latest" --ask-vault-pass
```

All three should succeed 

### For New Nodes

When adding new nodes to the Tailscale network:

```bash
# 1. Join Tailscale with DNS enabled
sudo tailscale up --ssh --accept-routes --accept-dns=true --authkey=tskey-auth-XXX

# 2. Get hostname
tailscale status --json | jq -r '.Self.DNSName' | sed 's/\.$//'

# 3. Add to inventory with hostname
# Example: new-node ansible_host=new-node-hostname
```

### Maintenance

No ongoing maintenance required! DNS is managed centrally through Tailscale.

**If you need to change nameservers:**
1. Update in Tailscale admin console only
2. Restart Tailscale on nodes: `sudo systemctl restart tailscaled`
3. No Docker or application changes needed

---

## Historical Context (For Reference)

### What We Tried (Don't Do This)

-  Manual daemon.json DNS override (Docker ignores it with Tailscale DNS)
-  Disabling Tailscale DNS entirely (loses hostnames)
-  Per-container DNS overrides (unnecessary complexity)
-  systemd-resolved manipulation (Tailscale handles it)

### What Actually Worked

1. **Remove "Override local DNS"** from Tailscale admin console
2. **Disable Split DNS** (or leave empty)
3. **Ensure Global nameservers** are configured
4. **Restart Tailscale daemon** on all nodes

Simple and clean! 🎉
