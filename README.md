# Homelab Infrastructure

> Infrastructure-as-code for running self-hosted applications on Raspberry Pi with automated backups and disaster recovery

## Table of Contents

1. [Overview](#1-overview)
2. [Quick Start](#2-quick-start)
3. [Prerequisites](#3-prerequisites)
4. [Setup Guide](#4-setup-guide)
5. [Operations](#5-operations)
6. [Architecture](#6-architecture)
7. [Repository Structure](#7-repository-structure)
8. [Additional Documentation](#8-additional-documentation)
9. [Troubleshooting](#9-troubleshooting)

---

## 1. Overview

### What This Does

This homelab setup provides:

- Self-hosted applications (RSS reader, recipe manager, PDF tools, code server, etc.)
- Automated daily backups to cloud storage (Backblaze B2)
- Disaster recovery with one-command restoration
- High availability with standby node promotion
- Secure networking via Tailscale VPN mesh
- Infrastructure as code - reproducible, version-controlled setup

### Core Principles

- **Local-First**: Core services run on low-power Raspberry Pis at home
- **Automation**: Ansible manages all deployments and configurations
- **Containerization**: Everything runs in Docker for portability
- **Security**: Tailscale mesh network, no exposed ports to internet
- **Resilience**: Automated backups, standby nodes, easy recovery

### Service Architecture

```
                    Internet
                       │
                       │ (Public HTTPS)
                       ↓
              ┌────────────────┐
              │   Cloud VM     │  ← Edge proxy & monitoring
              │  (Linode/DO)   │
              │                │
              │  - Traefik     │  ← Reverse proxy
              │  - Uptime Kuma │  ← Monitoring
              │  - AdGuard     │  ← DNS/Ad blocking
              └────────┬───────┘
                       │
                       │ (Tailscale VPN Mesh)
                       ↓
         ┌─────────────┴──────────────┬─────────────┐
         │                            │             │
    ┌────┴─────┐                 ┌───┴──────┐  ┌───┴────────┐
    │ RPi-Home │                 │RPi-Friend│  │ India-Box  │
    │(Primary) │                 │(Standby) │  │ (Backups)  │
    │          │                 │          │  │ (Optional) │
    │ Apps+DBs │                 │DBs Only  │  │            │
    └──────────┘                 └──────────┘  └────────────┘
```

**4-Node Architecture:**

- **Cloud VM**: Edge proxy for public internet access (Traefik + Uptime Kuma)
- **RPi-Home**: Primary node running all applications
- **RPi-Friend**: Standby node (ready for promotion)
- **India-Box**: Optional backup target

**All nodes connect via Tailscale VPN** - services never exposed directly to internet.

---

## 2. Quick Start

**Total Time: Approximately 30 minutes for complete setup**

```bash
# 1. Clone this repository
git clone <your-repo-url> homelab && cd homelab

# 2. Set up secrets
cp env/secrets.example.env env/secrets.env
nano env/secrets.env  # Add your actual credentials

# 3. Update inventory with your node IPs
nano inventory/hosts.ini

# 4. Validate setup
make validate

# 5. Pre-pull Docker images (avoids rate limits)
make pull-images                   # Pull all images (~10 min)

# 6. Deploy everything
make deploy-base                   # Deploy to all nodes (~5 min)
make deploy-apps target=rpi-home   # Deploy apps (~3 min)
make deploy-backup-automation      # Setup backups (~1 min)

# 7. Test backup system
make backup-now HOST=rpi-home      # Run first backup
make restore-test HOST=rpi-friend  # Test restoration
```

 **Done!** Your homelab is now running with automated backups.

See [QUICKSTART.md](QUICKSTART.md) for detailed quick start guide.

---

## 3. Prerequisites

### Required Hardware

| Device             | Purpose                  | Specs                 | Quantity |
| ------------------ | ------------------------ | --------------------- | -------- |
| Raspberry Pi 5     | Primary application host | 8GB RAM, external SSD | 1        |
| Raspberry Pi 5     | Standby/DR host          | 8GB RAM, external SSD | 1        |
| Cloud VPS          | Edge proxy & monitoring  | 1-2GB RAM, 1 CPU      | 1        |
| Linux Box/VPS      | Backup target (optional) | Any specs             | 0-1      |
| Management Machine | To run Ansible           | Linux/macOS with SSH  | 1        |

### Required Accounts

- ️ **Tailscale** (free tier) - For secure VPN mesh
-  **Backblaze B2** (free 10GB) - For backup storage
-  **Cloud Provider** (Linode/DigitalOcean/Vultr) - For edge proxy VM (~$5-10/month)
- 📧 **Domain name** - For public access to services (e.g., yourdomain.com)

### Required Software (Management Machine)

```bash
# macOS
brew install ansible git

# Ubuntu/Debian
sudo apt update && sudo apt install -y ansible git python3-pip

# Verify installation
ansible --version
git --version
```

### Required Knowledge

-  Basic Linux command line
-  SSH key authentication
-  Basic understanding of Docker (optional but helpful)
-  No programming experience required
-  No deep networking knowledge needed

---

## 4. Setup Guide

Follow these steps **in order** for a successful deployment.

### Step 1: Prepare Your Nodes

#### 1.1 Hardware Setup

1. **Flash Raspberry Pi OS Lite (64-bit)** to both RPis

   ```bash
   # Use Raspberry Pi Imager
   # Enable SSH in advanced options
   # Set hostname: rpi-home, rpi-friend
   ```

2. **Boot nodes** and connect them to your network
3. **Find their IP addresses**

   ```bash
   # Check your router's DHCP leases or use:
   nmap -sn 192.168.1.0/24 | grep -B 2 "Raspberry Pi"
   ```

#### 1.2 SSH Key Setup (FROM YOUR MANAGEMENT MACHINE)

This is **critical** - you must have SSH key access before proceeding!

```bash
# Generate SSH key if you don't have one
ssh-keygen -t ed25519 -C "homelab-key"
# Accept default location: ~/.ssh/id_ed25519
# Set a passphrase (recommended)

# Start SSH agent
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519

# Copy SSH key to all nodes (use default user)
ssh-copy-id pi@<rpi-home-ip>       # For Raspberry Pi OS
ssh-copy-id pi@<rpi-friend-ip>
# Optional: ssh-copy-id user@<india-box-ip>  # If you have backup node

# Test SSH access (should work without password)
ssh pi@<rpi-home-ip> "echo 'SSH working!'"
ssh pi@<rpi-friend-ip> "echo 'SSH working!'"
```

**Troubleshooting:**

- If ssh-copy-id fails: `ssh-add -l` to verify key is loaded
- If permission denied: Check if password auth is enabled on target
- See [docs/SSH-SETUP.md](docs/SSH-SETUP.md) for detailed guide

#### 1.3 Run Bootstrap Script on Each Node

The bootstrap script prepares nodes for Ansible management.

```bash
# Copy bootstrap script to first node
scp scripts/bootstrap.sh pi@<rpi-home-ip>:/tmp/

# SSH in and run bootstrap
ssh pi@<rpi-home-ip>
sudo bash /tmp/bootstrap.sh Europe/Vienna pi
# Timezone: Europe/Vienna (or your timezone)
# Source user: pi (the current user with SSH keys)

# Repeat for second node
scp scripts/bootstrap.sh pi@<rpi-friend-ip>:/tmp/
ssh pi@<rpi-friend-ip>
sudo bash /tmp/bootstrap.sh Europe/Vienna pi

# Repeat for Cloud VM
scp scripts/bootstrap.sh root@<cloud-vm-ip>:/tmp/
ssh root@<cloud-vm-ip>
sudo bash /tmp/bootstrap.sh Europe/Vienna root

# Optional: Repeat for india-box if you have it
# scp scripts/bootstrap.sh user@<india-box-ip>:/tmp/
# ssh user@<india-box-ip>
# sudo bash /tmp/bootstrap.sh Europe/Vienna user
```

**What bootstrap does:**

-  Creates `homelab` user with sudo access
-  Copies SSH keys from source user to homelab user
-  Installs Docker & Docker Compose
-  Installs Tailscale
-  Configures firewall (UFW)
-  Hardens SSH (disables root login, password auth)

**️ Important:** After bootstrap, you MUST use `homelab` user:

```bash
ssh homelab@<rpi-home-ip>     #  Correct
ssh pi@<rpi-home-ip>          #  Won't work (disabled)
ssh root@<cloud-vm-ip>        #  Won't work (disabled)
```

#### 1.4 Join Tailscale Network

On **each node**, join your Tailscale network:

```bash
# SSH into node as homelab user
ssh homelab@<node-ip>

# Get auth key from Tailscale admin console:
# https://login.tailscale.com/admin/settings/keys

# Join Tailscale network
sudo tailscale up --ssh --accept-routes --accept-dns --authkey=tskey-auth-XXXXX

# Get your Tailscale IP
tailscale ip -4
# Example output: 100.101.102.103
```

**Record these Tailscale IPs** - you'll need them for inventory setup!

Optional: In Tailscale admin console, disable key expiry for server nodes.

### Step 2: Configure Your Repository

Back on your **management machine**:

#### 2.1 Clone Repository

```bash
git clone <your-repo-url> homelab
cd homelab
```

#### 2.2 Set Up Secrets

```bash
# Copy the example file
cp env/secrets.example.env env/secrets.env

# Edit with your actual credentials
nano env/secrets.env
```

**Required secrets:**

```bash
# Tailscale (from https://login.tailscale.com/admin/settings/keys)
TAILSCALE_AUTH_KEY=tskey-auth-XXXXX

# Domain & DNS
DOMAIN=yourdomain.com
CF_DNS_API_TOKEN=your-cloudflare-token

# Backblaze B2 (from Backblaze console - used by rclone for backups)
B2_KEY_ID=your-key-id
B2_APP_KEY=your-app-key
B2_BUCKET=your-bucket-name

# Database passwords (generate strong passwords)
PG_PASSWORD=postgres-password
MEALIE_DB_PASSWORD=mealie-password
PAPERLESS_DB_PASSWORD=paperless-password

# Admin passwords
CODE_PASSWORD=code-server-password
MEALIE_DEFAULT_PASSWORD=admin-password
```

**Security tips:**

- Use a password manager to generate strong passwords
- Never commit `secrets.env` to git (it's in .gitignore)
- Store a backup copy in your password manager

#### 2.3 Update Inventory

```bash
nano inventory/hosts.ini
```

Replace the placeholder IPs with your **Tailscale IPs** from Step 1.4:

```ini
[rpi_nodes]
rpi-home ansible_host=100.101.102.103
rpi-friend ansible_host=100.101.102.104

[cloud_nodes]
cloud-vm ansible_host=100.101.102.105

[backup_nodes]
india-box ansible_host=100.101.102.106  # Optional

[primary]
rpi-home

[all:vars]
ansible_user=homelab
ansible_ssh_private_key_file=~/.ssh/id_ed25519
```

**Note:** India-box is optional. Cloud VM is required for public access.

**Verify Ansible can connect:**

```bash
ansible all -i inventory/hosts.ini -m ping
```

Expected output: All nodes return `pong` with `"changed": false`

#### 2.4 Configure Sudo Passwords (Required for Ansible)

Since Ansible needs sudo access to manage your nodes, you need to configure encrypted sudo passwords. This setup allows different passwords for different node groups (rpi_nodes vs cloud_nodes).

**Step 1: Encrypt RPi Nodes Sudo Password**

```bash
# Generate encrypted password for rpi_nodes
echo 'ansible_sudo_pass: YOUR_RPI_SUDO_PASSWORD' | ansible-vault encrypt_string --stdin-name 'ansible_sudo_pass'
```

**Step 2: Add to rpi_nodes.yml**

Copy the encrypted output and add it to `inventory/group_vars/rpi_nodes.yml`:

```yaml
# Ansible Authentication
ansible_sudo_pass: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  [YOUR_ENCRYPTED_PASSWORD_OUTPUT]
```

**Step 3: Encrypt Cloud Nodes Sudo Password**

```bash
# Generate encrypted password for cloud_nodes
echo 'ansible_sudo_pass: YOUR_CLOUD_SUDO_PASSWORD' | ansible-vault encrypt_string --stdin-name 'ansible_sudo_pass'
```

**Step 4: Add to cloud_nodes.yml**

Add the encrypted output to `inventory/group_vars/cloud_nodes.yml`:

```yaml
# Ansible Authentication
ansible_sudo_pass: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  [YOUR_ENCRYPTED_PASSWORD_OUTPUT]
```

**Step 5: Test Configuration**

```bash
# Test RPi nodes
ansible rpi_nodes -i inventory/hosts.ini -m shell -a "sudo whoami" --ask-vault-pass

# Test Cloud nodes
ansible cloud_nodes -i inventory/hosts.ini -m shell -a "sudo whoami" --ask-vault-pass
```

**Security Notes:**

-  Passwords are encrypted using Ansible Vault
-  Different passwords for different node groups
-  Vault password protects all encrypted secrets
- ️ Remember your vault password - you'll need it for all deployments
-  Store vault password in your password manager

### Step 3: Validate Setup

Before deploying, validate everything is configured correctly:

```bash
make validate
```

This checks:

-  All required files exist
-  All secrets are defined (no placeholders)
-  Docker Compose syntax is valid
-  Ansible playbook syntax is valid
-  Inventory is accessible

**Fix any errors before proceeding!**

### Step 4: Pre-Pull Docker Images (Recommended)

Before deployment, pre-pull all Docker images to avoid hitting Docker Hub rate limits:

```bash
make pull-images
```

**Why this matters:**
- Docker Hub has rate limits (100 pulls per 6 hours for anonymous users)
- This command pulls all images once to all nodes
- Future deployments use cached images (no rate limit issues)
- Takes ~5-10 minutes depending on your internet speed

**What it does:**
- Pulls base images (PostgreSQL, Redis) to all nodes
- Pulls app images (Mealie, Wallos, etc.) to RPi nodes
- Pulls cloud images (Traefik, Authentik, etc.) to cloud VM
- All images are cached locally on each node

**Note:** This step is optional but **highly recommended** for smooth deployments.

### Step 5: Deploy Infrastructure

Now deploy everything using Ansible (via Make commands):

#### 5.1 Deploy Base Services (All Nodes)

```bash
make deploy-base
```

**What this deploys:**

- PostgreSQL database
- Redis cache

**Time:** ~2-5 minutes
**Target:** All nodes (rpi-home, rpi-friend, and optionally india-box)

**Note:** Tailscale runs as a system service (already installed by bootstrap script).

#### 5.2 Deploy Applications (Primary Node Only)

```bash
make deploy-apps target=rpi-home
```

**What this deploys:**

- Mealie (recipe manager)
- Wallos (subscription tracker)
- Sterling PDF (PDF tools)
- SearXNG (search engine)
- VS Code Server
- Open WebUI (AI interface)
- Audiobookshelf (audiobook/podcast server)
- n8n (workflow automation)
- Homarr (dashboard)
- Paperless-ngx (document management)

**Time:** ~3-5 minutes
**Target:** Only rpi-home (primary node)

**Note:** rpi-friend (standby node) does NOT run apps by default. See [High Availability](#high-availability) for promotion.

#### 5.3 Deploy Backup Automation

```bash
make deploy-backup-automation
```

**What this sets up:**

- Installs backup scripts to all nodes
- Configures daily cron jobs (different times per node)
- Tests Rclone connection to B2
- Configures encrypted backups with rclone crypt

**Time:** ~1-2 minutes
**Target:** All nodes

#### 5.4 Deploy Rclone Cloud Mounts (Optional)

```bash
make deploy-rclone-mount
```

**What this sets up:**

- Mounts cloud storage (audiobooks, etc.) to `/mnt/audiobooks`
- Creates systemd service for auto-mount on boot
- Configures 50GB cache with 10-day retention for smooth streaming
- Enables audiobookshelf to access cloud audiobooks without downloading

**Time:** ~1 minute
**Target:** RPi nodes

**Configuration:**
- Edit `env/rclone-mounts.env` to add more mounts (podcasts, ebooks, etc.)
- Mount path: `b2-crypt:data/media/audiobooks` → `/mnt/audiobooks`

**Note:** This is optional - only needed if you want to stream media from cloud storage.

### Step 6: Verify Deployment

#### 6.1 Check Services are Running

```bash
# SSH into primary node
ssh homelab@rpi-home

# Check all containers are running
docker ps --format "table {{.Names}}\t{{.Status}}"

# Should see 15-20 containers in "Up" state
```

#### 6.2 Service URLs

All services can be accessed two ways:

**Via Domain Names (Traefik HTTPS):**

| Service        | URL                          | Description                    |
| -------------- | ---------------------------- | ------------------------------ |
| Authentik      | `https://auth.igh.one`       | SSO/Authentication (login)     |
| Mealie         | `https://mealie.igh.one`     | Recipe manager                 |
| Wallos         | `https://wallos.igh.one`     | Subscription tracker           |
| Sterling PDF   | `https://pdf.igh.one`        | PDF tools                      |
| SearXNG        | `https://search.igh.one`     | Private search engine          |
| Code Server    | `https://code.igh.one`       | VS Code in browser             |
| Open WebUI     | `https://chat.igh.one`       | AI chat interface              |
| Audiobookshelf | `https://books.igh.one`      | Audiobook/podcast server       |
| n8n            | `https://n8n.igh.one`        | Workflow automation            |
| Homarr         | `https://dashboard.igh.one`  | Dashboard                      |
| Paperless-ngx  | `https://paperless.igh.one`  | Document management            |
| Traefik        | `https://traefik.igh.one`    | Reverse proxy dashboard        |

**Via Direct Ports (Tailscale IP):**

```bash
# Get rpi-home's Tailscale IP
ssh homelab@rpi-home tailscale ip -4
# Example: 100.101.102.103

# Access via IP:port
http://<tailscale-ip>:9925   # Mealie
http://<tailscale-ip>:8282   # Wallos
http://<tailscale-ip>:8082   # Sterling PDF
http://<tailscale-ip>:8083   # SearXNG
http://<tailscale-ip>:8443   # Code Server
http://<tailscale-ip>:8084   # Open WebUI
http://<tailscale-ip>:13378  # Audiobookshelf
http://<tailscale-ip>:5678   # n8n
http://<tailscale-ip>:7575   # Homarr
http://<tailscale-ip>:8000   # Paperless-ngx
```

**Check Service Health:**

```bash
make check-health   # Check container status on all nodes
make check-urls     # Check if all service URLs are responding
```

#### 6.3 Verify Backup System

```bash
# Run first backup manually
make backup-now HOST=rpi-home

# Check backup succeeded (look for "snapshot saved")
# Backup should take 2-10 minutes depending on data size

# Test restoration (non-destructive)
make restore-test HOST=rpi-friend

# Verify test restore
ssh homelab@rpi-friend
ls -lh /tmp/rclone_restore_test/
# Should see backed up data here
```

**🎉 Congratulations! Your homelab is fully operational!**

---

## 5. Operations

Daily operations and maintenance tasks.

### Available Commands

All operations use `make` commands. Run `make help` to see all options.

**🔐 Important:** All deployment commands will prompt for your **Ansible Vault password** to decrypt sudo credentials. This is the password you set when configuring encrypted sudo passwords in Section 2.4.

| Command                         | Purpose                              | Example                             |
| ------------------------------- | ------------------------------------ | ----------------------------------- |
| `make validate`                 | Validate configuration               | `make validate`                     |
| `make deploy-base`              | Deploy base services                 | `make deploy-base`                  |
| `make deploy-apps`              | Deploy applications                  | `make deploy-apps target=rpi-home`  |
| `make deploy-backup-automation` | Setup automated backups              | `make deploy-backup-automation`     |
| `make backup-now`               | Run manual backup                    | `make backup-now HOST=rpi-home`     |
| `make restore-test`             | Test backup restore                  | `make restore-test HOST=rpi-friend` |
| `make restore-latest`           | Restore from backup (️ destructive) | `make restore-latest HOST=rpi-home` |
| `make failover`                 | Promote standby to primary           | `make failover`                     |
| `make pull-images`              | Pre-pull all Docker images           | `make pull-images`                  |
| `make update-images`            | Update images and restart services   | `make update-images`                |

### Common Operations

#### Running Manual Backups

```bash
# Backup specific host
make backup-now HOST=rpi-home
make backup-now HOST=rpi-friend

# Backups are encrypted and uploaded to B2
# Check B2 console to verify uploads
```

#### Testing Backup Integrity

**⚡ Do this monthly!**

```bash
# Non-destructive test - downloads and extracts to /tmp
make restore-test HOST=rpi-friend

# Verify the restore
ssh homelab@rpi-friend
ls -lh /tmp/restic_restore_test/docker_volumes/
ls -lh /tmp/restic_restore_test/databases/

# Clean up test data
rm -rf /tmp/restic_restore_test/
```

#### Updating Applications

```bash
# Option 1: Update all images and services at once (recommended)
make update-images

# Option 2: Update specific stack manually
ssh homelab@rpi-home
cd /opt/stacks/apps
docker compose pull
docker compose up -d

# Option 3: Redeploy via Ansible (uses cached images)
make deploy-apps target=rpi-home
```

**Note:** `make update-images` will:
- Pull fresh images from registries
- Restart all services with new images
- Work across all nodes (base, apps, cloud stacks)
- Prompt for confirmation before proceeding

#### Viewing Logs

```bash
ssh homelab@rpi-home

# View logs for specific service
docker logs freshrss
docker logs mealie

# Follow logs in real-time
docker logs -f freshrss

# View logs for all services
cd /opt/stacks/apps
docker compose logs -f
```

#### Checking Disk Space

```bash
ssh homelab@rpi-home

# Check disk usage
df -h

# Check Docker disk usage
docker system df

# Clean up unused Docker resources
docker system prune -a
```

### High Availability

The homelab supports **automatic failover** between nodes with a single command. Active node tracking is maintained in `.active-node` file locally.

#### Smart Failover System

The system automatically determines which node is active and switches to the other:

**Full Production Failover** (with data restore and shutdown):
```bash
make failover
```
- Restores latest backup from active node to standby
- Deploys base + apps on new active node
- Stops all services on old active node
- Updates `.active-node` tracker

**Fast Planned Switch** (no restore, but clean shutdown):
```bash
make failover SKIP_RESTORE=true
```
- Skips backup restore (use when data is already synced)
- Deploys base + apps on new active node
- Stops all services on old active node
- Faster switchover (~2 minutes instead of ~10 minutes)

**Disaster Recovery Mode** (old node is DOWN/unreachable):
```bash
make failover STOP_OLD_ACTIVE=false
```
- Restores latest backup from active node
- Deploys base + apps on new active node
- Skips attempting to stop old node (gracefully handles unreachable nodes)
- Use when primary node has crashed or is offline

**Development/Testing Mode** (both nodes running):
```bash
make failover SKIP_RESTORE=true STOP_OLD_ACTIVE=false
```
- Fast switch without data movement
- Leaves both nodes running (for testing)

#### How It Works

1. **Active Node Tracking**: `.active-node` file tracks current active (rpi-home or rpi-friend)
2. **Automatic Target Selection**: Failover automatically switches to the OTHER node
3. **Bidirectional**: Run `make failover` again to switch back
4. **State Management**: Automatically updates tracker after successful failover

**Example Flow:**
```bash
# Initial state: rpi-home is active
cat .active-node
# Output: rpi-home

# Switch to rpi-friend
make failover
# Switches from rpi-home → rpi-friend

cat .active-node
# Output: rpi-friend

# Switch back to rpi-home
make failover
# Switches from rpi-friend → rpi-home
```

#### Manual Recovery (if needed)

If automatic failover fails, manual recovery:

```bash
# Restore specific backup to a node
make restore-latest HOST=rpi-friend FROM=rpi-home

# Deploy services
make deploy-base
make deploy-apps target=rpi-friend

# Manually update active tracker
echo "rpi-friend" > .active-node
```

### Monitoring

#### Service Health

```bash
# Check container status
ssh homelab@rpi-home "docker ps --format 'table {{.Names}}\t{{.Status}}'"

# Check container resource usage
ssh homelab@rpi-home "docker stats --no-stream"
```

#### Backup Status

```bash
# View recent backup logs
make backup-log HOST=rpi-home

# Check if backup is currently running
make backup-status HOST=rpi-home

# Watch backup progress in real-time
make watch-backup HOST=rpi-home

# List backups in B2
rclone lsd b2-crypt:rpi-homelab-backup/rpi-home/

# View cron job status
ssh homelab@rpi-home "systemctl status cron"
```

#### Manual Backup Operations

```bash
# Trigger immediate backup (runs in background)
make backup-now HOST=rpi-home

# Backup all nodes
make backup-all

# Test restore to temporary directory (non-destructive)
make restore-test HOST=rpi-home

# Cross-node restore test (DR testing)
make restore-test HOST=rpi-friend FROM=rpi-home
```

---

## 6. Architecture

### Network Architecture

```
Internet (Optional - if you add cloud proxy)
   │
   └─── Tailscale VPN Mesh (100.x.x.x network)
        │
        ├─── RPi-Home (Primary)
        │    ├─── Base Services (PostgreSQL, Redis)
        │    └─── App Services (FreshRSS, Mealie, etc.)
        │
        ├─── RPi-Friend (Standby)
        │    └─── Base Services Only (ready for promotion)
        │
        └─── India-Box (Optional)
             └─── Backup target
```

**Access Method:** All services accessed via Tailscale IPs (100.x.x.x). You must be connected to Tailscale VPN to access services.

**No Public Exposure:** Services are NOT exposed to the internet. This is more secure than having a public-facing proxy.

### Network Architecture

```
Internet
   │
   │ (HTTPS via domain)
   ↓
┌──────────────┐
│  Cloud VM    │  ← Public entry point
│  Traefik     │
│  Authentik   │
└──────┬───────┘
       │
       │ Tailscale VPN (100.x.x.x)
       ↓
┌──────┴────────────┬──────────────┐
│                   │              │
RPi-Home      RPi-Friend      India-Box
(Primary)      (Standby)      (Optional)
```

**How it works:**

1. User accesses `freshrss.yourdomain.com`
2. DNS points to Cloud VM public IP
3. Traefik (on Cloud VM) receives request
4. Authentik validates user authentication
5. Traefik proxies request via Tailscale to RPi-Home
6. Service responds back through same path

**Note:** Cloud VM provides public access with SSO. Services on RPis are NEVER exposed directly to internet.

### Service Placement

| Service          | RPi-Home | RPi-Friend | Cloud VM | India-Box |
| ---------------- | -------- | ---------- | -------- | --------- |
| Tailscale        |        | ✅         | ✅       | ✅\*      |
| PostgreSQL       |        | ✅         | ❌       | ❌        |
| Redis            |        | ✅         | ❌       | ❌        |
| Traefik          |        | ✅         | ✅       | ❌        |
| Authentik (SSO)  |        | ✅         | ❌       | ❌        |
| Uptime Kuma      |        | ❌         | ✅       | ❌        |
| AdGuard Home     |        | ❌         | ✅       | ❌        |
| Mealie           |        | ⏸️         | ❌       | ❌        |
| Wallos           |        | ⏸️         | ❌       | ❌        |
| Sterling PDF     |        | ⏸️         | ❌       | ❌        |
| SearXNG          |        | ⏸️         | ❌       | ❌        |
| VS Code Server   |        | ⏸️         | ❌       | ❌        |
| Open WebUI       |        | ⏸️         | ❌       | ❌        |
| Audiobookshelf   |        | ⏸️         | ❌       | ❌        |
| n8n              |        | ⏸️         | ❌       | ❌        |
| Homarr           |        | ⏸️         | ❌       | ❌        |
| Paperless-ngx    |        | ⏸️         | ❌       | ❌        |
| Backups (Rclone) |        | ✅         | ✅\*     | ✅\*      |

**Legend:**

-  Always running
- ⏸ Installed but disabled (can be enabled with `make failover`)
-  Not installed
- \* Optional (India-Box only)

**Notes:**
- **Tailscale** runs as system service on all nodes (not in Docker)
- **Cloud VM** is REQUIRED - provides public access via Traefik, Authentik SSO, and Uptime Kuma monitoring
- **India-Box** is optional - provides additional backup target

### Data Flow

```
User Device (in Tailscale)
    ↓
Tailscale VPN (encrypted tunnel)
    ↓
RPi-Home:8081 (FreshRSS)
    ↓
PostgreSQL (127.0.0.1:5432)
    ↓
Nightly Backup → B2 Storage (encrypted)
```

### Security Model

1. **No Direct Internet Exposure**

   - All services bind to `127.0.0.1` or Tailscale IPs only
   - No ports forwarded on home router

2. **Tailscale VPN Mesh**

   - All inter-node communication encrypted
   - Zero-config WireGuard tunnels
   - Access from anywhere via Tailscale client

3. **SSH Hardening**

   - Root login disabled
   - Password authentication disabled
   - Key-based auth only

4. **Firewall (UFW)**

   - Default deny incoming
   - Only SSH, Tailscale ports allowed

5. **Encrypted Backups**

   - Rclone crypt with client-side encryption
   - Data encrypted before leaving network

---

## 7. Repository Structure

```
homelab/
├── README.md                 # This file
├── QUICKSTART.md            # 5-minute setup guide
├── SECURITY.md              # Security policies
├── CONTRIBUTING.md          # Contribution guidelines
│
├── Makefile                 # Automation commands
│
├── docs/                    # Additional documentation
│   ├── OPERATIONS.md        # Detailed operations guide
│   ├── DISASTER-RECOVERY.md # DR procedures
│   ├── TESTING.md           # Testing scenarios
│   ├── MIGRATION.md         # 20-day migration plan
│   └── SSH-SETUP.md         # Detailed SSH setup
│
├── ansible/                 # Ansible automation
│   ├── site.yml            # Main playbook
│   └── roles/
│       ├── common/         # Common tasks (directories, env files)
│       ├── compose-deploy/ # Deploy Docker Compose stacks
│       └── backup-automation/ # Setup backup cron jobs
│
├── env/                     # Environment configuration
│   ├── common.env          # Common variables (timezone, paths)
│   ├── local.env           # Node-specific overrides
│   ├── secrets.env         # Secrets (NOT in git)
│   └── secrets.example.env # Template for secrets
│
├── inventory/               # Ansible inventory
│   ├── hosts.ini           # Node definitions
│   ├── group_vars/
│   │   └── rpi_nodes.yml   # RPi-specific variables
│   └── host_vars/
│       ├── rpi-home.yml    # rpi-home specific vars
│       └── rpi-friend.yml  # rpi-friend specific vars
│
├── scripts/                 # Utility scripts
│   ├── bootstrap.sh        # Bootstrap new nodes
│   ├── validate_setup.sh   # Pre-deployment validation
│   ├── backup_now.sh       # Manual backup script
│   ├── restore_latest.sh   # Restore from backup
│   ├── db_dump.sh          # Database backup helper
│
└── stacks/                  # Docker Compose stacks
    ├── base/
    │   └── compose.yml     # Base services
    ├── apps/
    │   └── compose.yml     # Application services
    └── overrides/
        ├── cloud.traefik.yml    # Cloud proxy config (optional - see docs/CLOUD-PROXY-SETUP.md)
        └── local.private.yml    # Localhost-only binding
```

### Key Files Explained

**Makefile**

- Provides convenient commands for all operations
- Wraps Ansible playbooks and SSH commands
- Run `make help` to see all commands

**ansible/site.yml**

- Main Ansible playbook
- Orchestrates all deployments
- Uses tags for selective deployment

**env/secrets.env**

- Contains all passwords and API keys
- Must be created from `secrets.example.env`
- Never committed to git

**inventory/hosts.ini**

- Defines your nodes and their IPs
- Must be updated with actual Tailscale IPs
- Used by all Ansible commands

**scripts/bootstrap.sh**

- Prepares fresh nodes for management
- Installs Docker, Tailscale, security tools
- Creates `homelab` user

**stacks/base/compose.yml**

- Core infrastructure services
- Deployed to all nodes
- Includes databases (PostgreSQL, Redis)
- Note: Tailscale runs as system service, not in Docker

**stacks/apps/compose.yml**

- User-facing applications
- Deployed only to primary node (or promoted standby)
- All apps bind to localhost for security

---

## 8. Additional Documentation

Detailed guides for specific scenarios:

### Core Documentation

- **[QUICKSTART.md](QUICKSTART.md)** - 5-minute setup guide for first-time deployment
- **[docs/OPERATIONS.md](docs/OPERATIONS.md)** - Comprehensive operations and maintenance guide
- **[docs/DISASTER-RECOVERY.md](docs/DISASTER-RECOVERY.md)** - DR procedures and runbooks

### Scenario Guides

- **[docs/TESTING.md](docs/TESTING.md)** - Testing scenarios and validation procedures
  - From-scratch setup testing
  - Backup and restore testing
  - Disaster recovery simulation
  - High availability testing
  - Network failure scenarios

### Planning & Migration

- **[docs/MIGRATION.md](docs/MIGRATION.md)** - 20-day migration plan for Austria deployment
  - Week-by-week tasks
  - Risk assessment
  - Rollback procedures
  - Timeline and milestones

### Security

- **[SECURITY.md](SECURITY.md)** - Security overview and best practices
  - Security model
  - Threat analysis
  - Hardening checklist
  - Incident response

### Reference

- **[docs/SSH-SETUP.md](docs/SSH-SETUP.md)** - Detailed SSH key setup guide
- **[docs/DOCKER-PULL-STRATEGY.md](docs/DOCKER-PULL-STRATEGY.md)** - Docker image caching and rate limit avoidance
- **[docs/SERVICES.md](docs/SERVICES.md)** - Complete service documentation
- **[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)** - Common issues and solutions

### Authentication & Security

- **[docs/AUTHENTIK-SETUP.md](docs/AUTHENTIK-SETUP.md)** - Authentik SSO setup and configuration
  - Initial deployment and admin setup
  - Forward auth for apps without OIDC
  - Native OIDC for n8n and Paperless
  - User management and MFA
  - Troubleshooting guide

### Optional Components

- **[docs/CLOUD-PROXY-SETUP.md](docs/CLOUD-PROXY-SETUP.md)** - Adding public internet access via cloud edge proxy
  - When to add cloud proxy vs. Tailscale-only
  - Complete setup guide (Traefik + Authentik)
  - Cost analysis (~$6-11/month)
  - Security considerations
  - Cloudflare Tunnel alternative

---

## 9. Troubleshooting

### Common Issues

#### "SSH connection failed"

```bash
# Verify SSH key is loaded
ssh-add -l

# Test connection manually
ssh -v homelab@<tailscale-ip>

# Re-copy SSH key if needed
ssh-copy-id homelab@<tailscale-ip>
```

#### "Ansible ping fails"

```bash
# Test direct SSH
ssh homelab@rpi-home "echo 'Connection OK'"

# Check inventory syntax
ansible-inventory -i inventory/hosts.ini --list

# Try with verbose mode
ansible rpi-home -i inventory/hosts.ini -m ping -vvv
```

#### "Ansible sudo password fails"

```bash
# Error: "Missing sudo password" or "Incorrect sudo password"
# Solution: Check encrypted passwords are configured correctly

# Test vault decryption
ansible-vault view inventory/group_vars/rpi_nodes.yml

# Verify sudo password manually
ssh homelab@rpi-home
sudo whoami  # Should prompt for password, then work

# Re-encrypt password if needed
echo 'ansible_sudo_pass: YOUR_CORRECT_PASSWORD' | ansible-vault encrypt_string --stdin-name 'ansible_sudo_pass'
```

#### "Vault password prompt issues"

```bash
# Error: "Vault password required"
# Solution: All deployment commands need --ask-vault-pass (handled by Makefile)

# Test vault password manually
ansible rpi_nodes -i inventory/hosts.ini -m shell -a "sudo whoami" --ask-vault-pass

# If you forgot vault password, re-encrypt all vault files:
ansible-vault rekey inventory/group_vars/rpi_nodes.yml
ansible-vault rekey inventory/group_vars/cloud_nodes.yml
```

#### "Docker containers not starting"

```bash
# Check logs
ssh homelab@rpi-home
docker compose -f /opt/stacks/apps/compose.yml logs

# Verify secrets are loaded
docker compose -f /opt/stacks/apps/compose.yml config | grep -i password

# Restart stack
docker compose -f /opt/stacks/apps/compose.yml down
docker compose -f /opt/stacks/apps/compose.yml up -d
```

#### "Backup failing"

```bash
# Check backup log
ssh homelab@rpi-home
tail -n 100 /var/log/backup.log

# Test B2 connection and list backups
rclone lsd b2-crypt:rpi-homelab-backup/

# Test specific node backups
rclone lsd b2-crypt:rpi-homelab-backup/rpi-home/
```

#### "Can't access services"

```bash
# Verify Tailscale is connected
ssh homelab@rpi-home tailscale status

# Check service is listening
ssh homelab@rpi-home "netstat -tlnp | grep 8081"

# Test from node itself
ssh homelab@rpi-home "curl http://127.0.0.1:8081"
```

### Getting Help

1. Check logs: `docker compose logs -f`
2. Run validation: `make validate`
3. See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for detailed solutions
4. Create an issue with:
   - Error message
   - Output of `make validate`
   - Relevant logs

---

## License

[Your License Here]

---

## Acknowledgments

Built with:

- [Ansible](https://www.ansible.com/) - Automation
- [Docker](https://www.docker.com/) - Containerization
- [Tailscale](https://tailscale.com/) - VPN mesh networking
- [Rclone](https://rclone.org/) - Backup and sync solution
- [Backblaze B2](https://www.backblaze.com/b2/) - Cloud storage

Inspired by the homelab and self-hosting communities.
