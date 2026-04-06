# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a **homelab infrastructure-as-code** repository designed for a **local-first, geographically distributed** deployment strategy. It manages self-hosted applications across Raspberry Pis with cloud edge services, supporting a phased migration from India to Austria.

**Design Philosophy:**
- **Local-first**: Heavy lifting on low-power RPis, not expensive cloud VMs
- **Cloud edge only**: Minimal cloud footprint (Traefik + monitoring — Authentik removed April 2026)
- **Geographic resilience**: India footprint (2 RPis) + Austria expansion (new server with HDDs)
- **10-minute promotion**: Standby node can be promoted rapidly via restore + compose up
- **Databases collocated**: DBs always run with their apps (no cross-site DB calls)
- **Phased deployment**: Light services on RPis now, heavy services on Austria server later

## Geographic Distribution

**India (Bangalore) - Permanent:**
- **rpi-home**: Your house - Primary node with light applications
- **rpi-friend**: Friend's house - Standby node (can be promoted in <10min)
- **Optional india-box**: Small Linux box for extra backups/DR

**Austria (Vorarlberg) - Future (2-3 months post-move):**
- **austria-server**: New Synology-like server with existing Unraid HDDs (2×8TB NAS, 2×512GB NVMe)
- Will host heavy workloads: Media stack, Nextcloud, Home Assistant, etc.

**Cloud (Linode/DigitalOcean):**
- **cloud-node**: Edge proxy, SSO, monitoring ($5-10/month)

**Storage:**
- **Backblaze B2**: Primary backup target
- **Linode Object Storage**: Optional weekly mirror

**Core Architecture:**
- **Primary Node (rpi-home)**: Runs all applications + base services (Raspberry Pi 5 + 120GB SSD) - **Stays in India at your house**
- **Standby Node (rpi-friend)**: Runs base services only, ready for <10min promotion - **Stays in India at friend's house**
- **Austria Node (future)**: New server (Synology-like) with Unraid hard disks - heavy workloads (media, Nextcloud, etc.)
- **Cloud VM (Linode $5-10/mo)**: Edge proxy with Traefik, Uptime Kuma (Authentik removed — too heavy for RPi)
- **Optional Backup Node (india-box)**: DR-lite and backup target only (no steady-state hosting)
- **Networking**: Tailscale VPN mesh (WireGuard fallback option)
- **Backups**: Rclone with client-side encryption to Backblaze B2 primary, optional Linode Object Storage mirror

## Essential Commands

### Validation & Setup
```bash
# Validate configuration before deployment
make validate

# Check if all secrets are properly configured
grep -c "your-" env/secrets.env  # Should return 0
```

### Deployment
```bash
# Deploy base services (PostgreSQL, Redis) to all nodes
make deploy-base

# Deploy rclone cloud mounts (optional - for cloud storage streaming)
make deploy-rclone-mount

# Deploy applications to primary node (will prompt for Ansible Vault password)
make deploy-apps target=rpi-home

# Deploy backup automation to all nodes
make deploy-backup-automation

# Full deployment sequence (deploys base + rclone + apps + backups)
make deploy-all
```

**Important:** All deployment commands will prompt for the **Ansible Vault password**. This password decrypts the `ansible_sudo_pass` variable stored in `inventory/group_vars/{rpi_nodes,cloud_nodes}.yml`.

**Note:** `deploy-all` uses `.active-node` file to determine which node to deploy apps to. If `.active-node` doesn't exist, you must specify `target=rpi-home` explicitly.

### Backup Operations
```bash
# Run manual backup on specific host
make backup-now HOST=rpi-home

# Test backup restoration (non-destructive, restores to /tmp)
make restore-test HOST=rpi-friend

# Restore latest backup (DESTRUCTIVE - requires confirmation)
make restore-latest HOST=rpi-home
```

### Rclone Mount Operations
```bash
# Deploy rclone cloud mounts to active node
make deploy-rclone-mount

# Deploy to specific node
make deploy-rclone-mount target=rpi-home

# Check mount status on node
ssh homelab@rpi-home "systemctl status rclone-audiobooks.service"

# View mount logs
ssh homelab@rpi-home "journalctl -u rclone-audiobooks.service -f"

# Verify mount is accessible
ssh homelab@rpi-home "ls -lah /mnt/audiobooks/"

# Restart rclone mount service
ssh homelab@rpi-home "sudo systemctl restart rclone-audiobooks.service"

# Check cache usage
ssh homelab@rpi-home "du -sh /home/homelab/.cache/rclone"
```

### High Availability
```bash
# Promote standby node to run applications
make failover

# Check service health across all nodes
make check-health

# View logs from specific host
make show-logs HOST=rpi-home
```

### Maintenance
```bash
# Update packages on all nodes
make update-packages

# Clean up unused Docker resources
make cleanup-docker

# Configure network priority (Ethernet over WiFi) on RPi nodes
make configure-network

# Reboot all nodes (requires confirmation)
make reboot-nodes
```

### Testing Deployments
```bash
# Test Ansible connectivity
ansible all -i inventory/hosts.ini -m ping --ask-vault-pass

# Verify services are running
ssh homelab@rpi-home "docker ps --format 'table {{.Names}}\t{{.Status}}'"

# Check resource usage
make show-resources
```

## Architecture Details

### Service Placement Strategy

**Base Stack** (`stacks/base/compose.yml`) - Deployed to ALL nodes:
- PostgreSQL (shared database)
- Redis (cache)
- Traefik (reverse proxy with HTTPS via Cloudflare DNS challenge)
- Authentik SSO (authentik, authentik-worker, authentik-db, authentik-redis)

**Note:** Tailscale runs as a system service (installed by bootstrap script), not as a Docker container.

**Apps Stack** (`stacks/apps/compose.yml`) - Deployed ONLY to nodes with `apps_enabled=true`:
- Mealie (recipe manager) - Port 9925
- Wallos (subscription tracker) - Port 8282
- Sterling PDF (PDF tools) - Port 8082
- SearXNG (search engine) - Port 8083
- VS Code Server - Port 8443
- Open WebUI (AI interface) - Port 8084
- Audiobookshelf (audiobook/podcast server) - Port 13378
- n8n (workflow automation) - Port 5678
- Homarr (dashboard) - Port 7575
- Paperless-ngx (document management) - Port 8000

**Cloud Stack** (`stacks/cloud/compose.yml`) - Deployed to cloud-node (optional):
- Traefik (reverse proxy with Let's Encrypt for public HTTPS access)
- Authentik (SSO/authentication provider with PostgreSQL + Redis)
- Uptime Kuma (monitoring dashboard)

**Note:** Cloud VM provides public internet access, SSO authentication, monitoring, and DNS filtering. See `docs/CLOUD-PROXY-SETUP.md` for setup guide.

### Ansible Deployment Flow

1. **Common Role** (`ansible/roles/common/`): Creates directories, deploys env files
2. **Compose-Deploy Role** (`ansible/roles/compose-deploy/`): Deploys Docker Compose stacks
3. **Rclone-Mount Role** (`ansible/roles/rclone-mount/`): Deploys cloud storage mounts via systemd
4. **Backup-Automation Role** (`ansible/roles/backup-automation/`): Installs backup scripts and cron jobs

The main playbook (`ansible/site.yml`) orchestrates these roles with tags:
- `base`: Deploy base services
- `rclone-mount`: Deploy cloud storage mounts (uses --limit for active node targeting)
- `apps`: Deploy applications (conditional on `apps_enabled`)
- `backup-automation`: Setup automated backups

**Important deployment order:** `deploy-all` runs in this sequence:
1. `deploy-base` (all nodes) → PostgreSQL, Redis
2. `deploy-rclone-mount` (active node only) → Cloud storage mounts
3. `deploy-apps` (active node only) → Applications that depend on mounts
4. `deploy-backup-automation` (all nodes) → Backup automation

### Node Configuration

**Inventory Location:** `inventory/hosts.ini`
- Groups: `rpi_nodes`, `cloud_nodes`, `backup_nodes`, `primary`, `standby`
- Connection: Uses `homelab` user with SSH key authentication
- Sudo: Encrypted passwords stored in `inventory/group_vars/{rpi_nodes,cloud_nodes}.yml`

**Host Variables:**
- `rpi-home`: `apps_enabled=true` (set in `inventory/host_vars/rpi-home.yml`)
- `rpi-friend`: `apps_enabled=false` by default (can be promoted)

### Environment Configuration

Environment files are sourced in this order:
1. `env/common.env` - Shared variables (timezone, paths, PUID/PGID)
2. `env/secrets.env` - Credentials and API keys (NOT in git)
3. `env/local.env` - Node-specific overrides (created on each node)

**Critical:** `env/secrets.env` must be created from `env/secrets.example.env` before deployment.

**How .env files work:**

When you run `make deploy`, Ansible does the following:
1. Copies `env/common.env`, `env/secrets.env`, and `env/local.env` to `/opt/stacks/env/` on each node
2. Merges all three files into a single `.env` file in each stack directory:
   - `/opt/stacks/base/.env` (for base stack)
   - `/opt/stacks/apps/.env` (for apps stack)
   - `/opt/stacks/cloud/.env` (for cloud stack)
3. Docker Compose automatically reads the `.env` file from its project directory

**Why this matters:**

This approach ensures that when the machine reboots:
- Docker automatically restarts containers (via `restart: unless-stopped` policy)
- The `.env` file is already present in each stack directory
- Services start successfully with all required environment variables
- **No need to run `make deploy` after every reboot**

Without this, Docker would try to start containers on boot but fail because the environment variables wouldn't be available.

### Security Model

1. **No Direct Internet Exposure**: All services bind to `127.0.0.1` or Tailscale IPs
2. **Tailscale VPN**: All inter-node communication encrypted, no port forwarding required
3. **SSH Hardening**: Root login disabled, password auth disabled (enforced by `scripts/bootstrap.sh`)
4. **Firewall**: UFW with default deny, only SSH and Tailscale ports allowed
5. **Encrypted Backups**: Rclone crypt encryption before data leaves network
6. **Ansible Vault**: Sudo passwords encrypted with Ansible Vault

### Backup Architecture

**Backup Strategy (Phase-aware):**
- **Pre-move**: Backup everything including media to B2 (encrypted with rclone crypt)
- **Post-move**: Backup only important data (files, photos, documents, DB dumps) - exclude media
- **Pruning**: Remove old "with-media" backups once Austria homelab is up
- **Optional**: Weekly mirror to Linode Object Storage with rclone sync

**Backup Flow:**
1. `scripts/db_dump.sh` - Dumps PostgreSQL databases to `/tmp/db_dumps/`
2. `scripts/backup_now.sh` - Uses Rclone to backup `/opt/stacks`, `/srv/appdata`, and database dumps to B2
3. Cron jobs run daily at 3:00 AM (configured by backup-automation role)

**Restoration:**
- `scripts/restore_latest.sh` - Restores from latest backup snapshot
- `--test` flag restores to `/tmp/rclone_restore_test/` for validation
- Without flag, restores directly to `/opt/stacks/` and `/srv/appdata/` (destructive)
- **Target recovery time**: <10 minutes for standby promotion

### Authentik SSO Architecture

**Purpose:** Provide single sign-on (SSO) for all homelab applications running on RPi.

**Components (in base stack):**
- **authentik**: Main SSO server (port 9000)
- **authentik-worker**: Background task processor
- **authentik-db**: Dedicated PostgreSQL (isolated from app DBs)
- **authentik-redis**: Dedicated Redis (isolated from app cache)

**SSO Integration Methods:**

| Service | Method | Notes |
|---------|--------|-------|
| Mealie, Wallos, Sterling PDF, SearXNG, Code Server, Open WebUI, Audiobookshelf, Homarr, Traefik | Forward Auth | Via Traefik middleware |
| n8n | Native OIDC | Uses N8N_AUTH_OIDC_* env vars |
| Paperless-ngx | Native OIDC | Uses PAPERLESS_SOCIALACCOUNT_PROVIDERS |

**Forward Auth Flow:**
1. User accesses `https://mealie.igh.one`
2. Traefik applies `authentik@file` middleware
3. Traefik forwards auth check to `http://authentik:9000/outpost.goauthentik.io/auth/traefik`
4. Authentik validates session or redirects to login
5. On success, Authentik sets headers (X-authentik-username, etc.)
6. Traefik proxies request to backend

**Configuration Files:**
- `stacks/base/traefik-config/middlewares.yml` - Forward auth middleware definition
- `stacks/base/compose.yml` - Authentik services
- `stacks/apps/compose.yml` - Apps with middleware labels or OIDC config
- `env/secrets.env` - AUTHENTIK_SECRET_KEY, AUTHENTIK_DB_PASSWORD, OIDC client secrets

**Authentik Management Commands:**
```bash
make authentik-status     # Check container status
make authentik-logs       # View server logs
make authentik-restart    # Restart all services
```

**Adding SSO to New Services:**
1. For forward auth apps: Add `traefik.http.routers.<name>.middlewares=authentik@file` label
2. For OIDC apps: Create application in Authentik admin, add client ID/secret to env

**First-Time Setup:**
1. Deploy base stack: `make deploy-base`
2. Access `https://auth.igh.one` and create admin account
3. Create forward auth provider and outpost in Authentik admin
4. Create OIDC applications for n8n and paperless
5. Update `env/secrets.env` with OIDC client IDs/secrets
6. Redeploy apps: `make deploy-apps target=rpi-home`

See `docs/AUTHENTIK-SETUP.md` for detailed setup guide.

### Rclone Cloud Mounts

**Purpose:** Stream media from cloud storage (Backblaze B2) without downloading entire libraries.

**Architecture:**
- Rclone mounts cloud storage paths as local filesystem via FUSE
- Systemd service manages auto-mount on boot
- VFS caching enables smooth streaming with local cache
- Deployed only to active node (where apps run)

**Configuration Files:**
- `env/rclone-mounts.env` - Mount configuration (remote paths, mount points)
- `scripts/rclone-audiobooks.service` - Systemd service definition
- `ansible/roles/rclone-mount/` - Ansible role for deployment

**Current Mounts:**
- **Audiobooks**: `b2-crypt:data/media/audiobooks` → `/mnt/audiobooks` (used by audiobookshelf)

**Cache Configuration:**
- **Mode**: `vfs-cache-mode full` - Caches entire files for best streaming performance
- **Max Size**: 50GB - Prevents cache from consuming too much disk space
- **Max Age**: 240 hours (10 days) - Keeps frequently accessed files cached
- **Chunk Size**: 128MB - Optimal for audiobook streaming
- **Buffer**: 256MB - Smooth playback without stuttering

**Systemd Service:**
- **Type**: `notify` - Rclone notifies systemd when mount is ready
- **User**: `homelab` - Runs as non-root user for security
- **Allow-Other**: Enabled - Allows Docker containers to access mount
- **Auto-Start**: Enabled - Mounts on boot before Docker services

**FUSE Configuration:**
- `/etc/fuse.conf` - Must have `user_allow_other` enabled
- Allows non-root users to use `--allow-other` flag
- Required for Docker containers to access mounts

**Adding New Mounts:**
1. Add mount configuration to `env/rclone-mounts.env`:
   ```bash
   PODCASTS_REMOTE=b2-crypt:data/media/podcasts
   PODCASTS_MOUNT=/mnt/podcasts
   ```
2. Create systemd service file (copy `rclone-audiobooks.service` as template)
3. Add Ansible tasks to `ansible/roles/rclone-mount/tasks/main.yml`
4. Update app compose file to mount the directory
5. Deploy with `make deploy-rclone-mount`

**Deployment Target:**
- Uses `.active-node` file or explicit `target=` parameter
- Only deploys to active node (not standby)
- Mount must be ready before apps start (deployment order enforced)

**Troubleshooting:**
```bash
# Check service status
systemctl status rclone-audiobooks.service

# View logs
journalctl -u rclone-audiobooks.service -f

# Check mount is accessible
ls -lah /mnt/audiobooks/

# Verify FUSE configuration
grep user_allow_other /etc/fuse.conf

# Check cache size
du -sh /home/homelab/.cache/rclone

# Manual unmount if needed
fusermount -uz /mnt/audiobooks
```

## Common Development Patterns

### Adding a New Service

**Important:** Follow the **databases-with-apps** rule - if service needs a DB, ensure it's collocated (no cross-site DB calls).

1. Add service definition to `stacks/apps/compose.yml`:
```yaml
  newservice:
    image: vendor/service:latest
    container_name: newservice
    environment:
      - TZ=${TZ}
      - DB_PASSWORD=${NEWSERVICE_DB_PASSWORD}
    ports:
      - "127.0.0.1:XXXX:YYYY"  # Always bind to localhost
    volumes:
      - ${APPDATA_PATH}/newservice:/data
    restart: unless-stopped
    depends_on:
      - postgres  # If using shared PostgreSQL
```

2. Add credentials to `env/secrets.example.env`:
```bash
NEWSERVICE_DB_PASSWORD=your-password-here
```

3. Update README.md service list and port mappings

4. Deploy:
```bash
make deploy-apps target=rpi-home
```

### Paused Services (Heavy/Can Wait for Austria)

Per original design, these services are **intentionally excluded** from the India RPis and will run on the Austria server:
- **Media stack**: Jellyfin, Sonarr, Radarr, Prowlarr, Jellyseerr, qBittorrent, Stash, Immich
- **Heavy docs**: Nextcloud, Bookstack, Paperless-ngx
- **Home automation**: Home Assistant

These can be added to a new `stacks/austria/compose.yml` or similar once the Austria server (Synology-like with Unraid HDDs) is set up. They were deprioritized to keep RPi resource usage manageable and because media requires the large HDDs that will be in Austria.

### Modifying Ansible Roles

**Common Pattern:**
```yaml
# ansible/roles/compose-deploy/tasks/main.yml
- name: Deploy {{ stack_name }} stack
  docker_compose:
    project_src: /opt/stacks/{{ stack_name }}
    state: present
    pull: true
  become: true
```

After modifying roles, test with:
```bash
ansible-playbook ansible/site.yml --tags "your-tag" --check --ask-vault-pass
```

### Updating Stack Overrides

Override files in `stacks/overrides/` customize base configurations:
- `local.private.yml` - Force localhost binding for security
- `cloud.traefik.yml` - Add Traefik labels for cloud proxy

These are merged during Ansible deployment by the compose-deploy role.

## Bootstrap New Nodes

For fresh nodes, run `scripts/bootstrap.sh` BEFORE Ansible:
```bash
scp scripts/bootstrap.sh pi@<new-node-ip>:/tmp/
ssh pi@<new-node-ip>
sudo bash /tmp/bootstrap.sh Europe/Vienna pi
```

This script:
- Creates `homelab` user with sudo access
- Installs Docker, Docker Compose, Tailscale
- Configures UFW firewall
- Hardens SSH configuration
- Copies SSH keys from source user to homelab user

## Tailscale Configuration

Nodes join Tailscale using auth key from `TAILSCALE_AUTH_KEY` in secrets.env:
```bash
# Manual join (if needed)
sudo tailscale up --ssh --accept-routes --accept-dns --authkey=tskey-auth-XXX

# Get Tailscale IP
tailscale ip -4
```

Update `inventory/hosts.ini` with Tailscale IPs after nodes join.

## Disaster Recovery Scenarios

**Target**: <10 minute recovery time for standby promotion

### Primary Node Failure (Your House → Friend's House in India)
```bash
make failover              # Promote standby (<10 min target)
# Update DNS/URLs to rpi-friend Tailscale IP
```

### Complete Rebuild
```bash
# Bootstrap fresh node
scp scripts/bootstrap.sh homelab@<node>:/tmp/
ssh homelab@<node> "sudo bash /tmp/bootstrap.sh Europe/Vienna homelab"

# Join Tailscale, update inventory, then deploy
make deploy-base --limit rpi-home
make restore-latest HOST=rpi-home
make deploy-apps target=rpi-home
```

### Austria Expansion (Adding New Heavy Server)
```bash
# 1. Both RPis continue running in India (rpi-home at your house, rpi-friend at friend's house)

# 2. Set up new Austria server with Unraid HDDs
# - Take only the hard disks from India Unraid box
# - Install on new Synology-like server in Austria
# - Bootstrap new node (austria-server or similar hostname)
# - Add to inventory/hosts.ini as new group [austria_nodes]

# 3. Deploy base services to Austria server
make deploy-base --limit austria-server

# 4. Create new stacks/austria/compose.yml for heavy services
# - Add media stack (Jellyfin, arr* stack, Immich, qBittorrent, Stash)
# - Add Nextcloud, Bookstack, Paperless-ngx
# - Add Home Assistant
# - Add Audiobookshelf with full library

# 5. Deploy Austria workloads
make deploy-apps target=austria-server

# 6. Final topology:
#    - rpi-home (India, your house) - primary light services
#    - rpi-friend (India, friend's house) - standby for rpi-home
#    - austria-server - heavy workloads with HDDs
```

### Data Corruption
```bash
make restore-test HOST=rpi-home  # Verify backup integrity first
make restore-latest HOST=rpi-home
```

## Important File Locations

**On Deployed Nodes:**
- `/opt/stacks/` - Docker Compose stacks
- `/opt/backups/` - Backup scripts and database dumps
- `/opt/stacks/env/` - Environment files (deployed by Ansible)
- `/var/log/backup.log` - Backup execution logs
- `/var/log/rclone-audiobooks.log` - Rclone mount logs
- `/mnt/audiobooks/` - Rclone mount point for cloud audiobooks
- `/home/homelab/.cache/rclone/` - Rclone VFS cache directory (max 50GB)
- `/etc/rclone-mounts.env` - Rclone mount configuration (deployed by Ansible)
- `/etc/systemd/system/rclone-audiobooks.service` - Rclone systemd service
- `/etc/fuse.conf` - FUSE configuration (user_allow_other enabled)
- `~/.ssh/authorized_keys` - SSH keys for homelab user

**In Repository:**
- `Makefile` - All operational commands
- `ansible/site.yml` - Main Ansible orchestration
- `ansible/roles/rclone-mount/` - Rclone mount deployment role
- `scripts/validate_setup.sh` - Pre-deployment validation
- `scripts/rclone-audiobooks.service` - Rclone systemd service template
- `inventory/hosts.ini` - Node definitions
- `env/secrets.env` - Credentials (NOT in git, create from example)
- `env/rclone-mounts.env` - Rclone mount configuration
- `.active-node` - Tracks which node is currently active (rpi-home or rpi-friend)

## Known Gotchas

### Node Hostnames
- Inventory names (`rpi-home`, `rpi-friend`) differ from Tailscale MagicDNS hostnames (`ub-house-green`, `ub-friend-blue`)
- If SSH to `rpi-home` fails, try `ssh homelab@ub-house-green` directly
- Tailscale must be running locally (`sudo tailscale up`) for MagicDNS to resolve

### Deployment
- `make check-health` only shows **base stack** containers — use `make check-urls HOST=rpi-home` to verify apps are actually responding
- `deploy-apps` takes **30-45 min on first run** due to image pulls; Ansible async timeout is 3600s — if it times out, check if containers started anyway with `docker ps` on the node
- Containers in `Created` state were **never started** and won't auto-start on reboot — run `cd /opt/stacks/apps && docker compose up -d` on the node or re-run `deploy-apps`
- When SSHing to run multi-part commands, put `&&` on the **same line** — newline-separated `&&` in a terminal is treated as separate commands

### Authentik (Removed)
- Authentik was removed April 2026 — consumed ~1GB RAM, SSO was never configured
- Do **not** re-add `authentik@file` middleware labels or OIDC env vars to n8n/paperless without intentionally setting up SSO first

## Troubleshooting Commands

```bash
# Ansible connectivity issues
ansible all -i inventory/hosts.ini -m ping -vvv --ask-vault-pass
ssh-add -l  # Verify SSH key loaded

# Vault password issues
ansible-vault view inventory/group_vars/rpi_nodes.yml  # Test decryption
echo 'ansible_sudo_pass: PASSWORD' | ansible-vault encrypt_string --stdin-name 'ansible_sudo_pass'

# Docker issues on node
ssh homelab@rpi-home "docker compose -f /opt/stacks/apps/compose.yml logs --tail=100"
ssh homelab@rpi-home "docker ps -a"  # Check stopped containers
ssh homelab@rpi-home "df -h"  # Check disk space

# Backup issues
ssh homelab@rpi-home "tail -n 100 /var/log/backup.log"
ssh homelab@rpi-home "rclone lsd b2-crypt:rpi-homelab-backup/"

# Rclone mount issues
ssh homelab@rpi-home "systemctl status rclone-audiobooks.service"
ssh homelab@rpi-home "journalctl -u rclone-audiobooks.service -n 50"
ssh homelab@rpi-home "cat /var/log/rclone-audiobooks.log | tail -100"
ssh homelab@rpi-home "ls -lah /mnt/audiobooks/"
ssh homelab@rpi-home "grep user_allow_other /etc/fuse.conf"
ssh homelab@rpi-home "du -sh /home/homelab/.cache/rclone"
ssh homelab@rpi-home "mount | grep rclone"

# Service accessibility
ssh homelab@rpi-home "tailscale status"
ssh homelab@rpi-home "curl http://127.0.0.1:9925"  # Test Mealie
```

## Key Implementation Details

### Apps Enabled Conditional
Applications only deploy to nodes where `apps_enabled` is true. This is controlled by:
1. Host variable in `inventory/host_vars/rpi-home.yml`
2. Local override in `/opt/stacks/env/local.env` on the node
3. Ansible conditional in `ansible/site.yml`: `when: apps_enabled | default(false) | bool`

### Port Strategy
- All services bind to `0.0.0.0` for Tailscale access
- Access via Tailscale VPN or cloud proxy only
- No ports forwarded on home router
- Port allocation: 9925 (Mealie), 8282 (Wallos), 8082 (Sterling PDF), 8083 (SearXNG), 8443 (VS Code), 8084 (Open WebUI), 13378 (Audiobookshelf), 5678 (n8n), 7575 (Homarr), 8000 (Paperless-ngx)

### Backup Schedule
Default cron schedule (set by backup-automation role):
- rpi-home: 2:00 AM daily
- rpi-friend: 3:00 AM daily
- india-box: 4:00 AM daily (if configured)

Staggered to avoid network congestion to B2.

## Documentation References

- **README.md**: Complete setup guide and operations manual
- **QUICKSTART.md**: 5-minute deployment guide
- **docs/OPERATIONS.md**: Detailed operational procedures
- **docs/DISASTER-RECOVERY.md**: DR runbooks and procedures
- **docs/TESTING.md**: Testing scenarios and validation
- **docs/CLOUD-PROXY-SETUP.md**: Optional public internet access setup
- **docs/AUTHENTIK-SETUP.md**: Authentik SSO setup and configuration guide
- **docs/SSH-SETUP.md**: Detailed SSH configuration guide
- **SECURITY.md**: Security model and threat analysis
