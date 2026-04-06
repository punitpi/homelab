#  Homelab Quick Start Guide

This is your **5-minute setup guide** for the complete homelab infrastructure.

## Prerequisites 

- **4 nodes**: 2 Raspberry Pis + 1 Cloud VM + 1 India box (optional)
  - RPi-Home (primary)
  - RPi-Friend (standby)
  - Cloud VM (edge proxy) - Linode/DigitalOcean/Vultr
  - India-Box (optional backup target)
- All running Ubuntu/Debian
- Tailscale account with auth key
- Backblaze B2 account for backups
- Domain name for public access
- SSH key access to all nodes

## Setup Steps

### 1. **Initial Validation** (2 minutes)

```bash
# Clone this repo to your management machine
git clone <your-repo> homelab && cd homelab

# Run validation to check setup completeness
./scripts/validate_setup.sh
```

### 2. **Configure Secrets** (2 minutes)

```bash
# Copy the secrets template
cp env/secrets.example.env env/secrets.env

# Edit with your actual values
nano env/secrets.env
```

**Required values:**

- `TAILSCALE_AUTH_KEY` - From Tailscale admin console
- `B2_KEY_ID`, `B2_APP_KEY`, `B2_BUCKET` - From Backblaze B2 (for rclone backups)
- `DOMAIN`, `CF_DNS_API_TOKEN` - Your domain and Cloudflare API token
- `PG_PASSWORD` - Strong password for PostgreSQL
- Database passwords for each app
- Admin passwords for services

### 3. **Update Inventory** (30 seconds)

```bash
# Edit inventory with actual Tailscale IPs
nano inventory/hosts.ini

# Update all 4 nodes with Tailscale IPs from: tailscale status
# [rpi_nodes]: rpi-home, rpi-friend
# [cloud_nodes]: cloud-vm
# [backup_nodes]: india-box (optional)
```

### 4. **Deploy Infrastructure** (1 minute)

```bash
# Deploy core services (PostgreSQL, Redis)
make deploy-base

# Deploy applications to primary node
make deploy-apps target=rpi-home

# Set up automated backups
make deploy-backup-automation
```

## Verification 

### Check Services

```bash
# Check base stack health
make check-health

# Check app service URLs
make check-urls HOST=rpi-home

# Or SSH directly (Tailscale MagicDNS hostname)
ssh homelab@ub-house-green "docker ps"
```

### Test Backup System

```bash
# Trigger manual backup
make backup-now HOST=rpi-home

# Verify backup worked
make restore-test HOST=rpi-friend  # Non-destructive test
```

## Common Issues 🔧

### "SSH connection failed"

- Ensure SSH keys are set up: `ssh-copy-id homelab@<node-ip>`
- Check Tailscale connectivity: `tailscale ping <node>`

### "Docker containers not starting"

- Check secrets: `grep -c "your-" env/secrets.env` (should be 0)
- Verify environment: `docker compose -f stacks/base/compose.yml config`

### "Backup failed"

- Test B2 credentials: `./scripts/backup_now.sh --dry-run`
- Check disk space: `df -h /opt/backups`

## Migration Scenario 🌍

When you move to Austria:

1. **Pack rpi-home**: Your apps keep running on rpi-friend automatically
2. **Ship to Austria**: Set up rpi-home with same config
3. **Restore data**: `make restore-latest HOST=rpi-home`
4. **Promote**: `make failover` to switch back

## Support 📚

- **Full documentation**: [README.md](README.md)
- **Operational scenarios**: See README sections 4-7
- **Troubleshooting**: README section 8

Your homelab is now **production-ready** with:

-  High availability (primary + standby)
-  Automated encrypted backups
-  Secure networking (Tailscale)
-  One-command deployments
-  Geographic redundancy (India + Austria)
