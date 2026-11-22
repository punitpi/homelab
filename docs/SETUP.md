# Setup Guide

First-time setup of the homelab from a management machine (your laptop). For rebuilding a node that died, see the recovery notes linked from the [README](../README.md#documentation) instead. Terms such as node name, hostname and active node are defined in [GLOSSARY.md](../GLOSSARY.md).

## Prerequisites

### Hardware

| Device             | Purpose                         | Specs                 | Quantity |
| ------------------ | ------------------------------- | --------------------- | -------- |
| Raspberry Pi 5     | Primary (runs the apps)         | 8GB RAM, external SSD | 1        |
| Raspberry Pi 5     | Standby (base stack only)       | 8GB RAM, external SSD | 1        |
| Cloud VPS          | Optional public edge proxy      | 1-2GB RAM, 1 CPU      | 0-1      |
| Management machine | Runs Ansible and `make`         | Linux/macOS with SSH  | 1        |

### Accounts

- **Tailscale** (free tier): the private network all nodes and clients join
- **Backblaze B2**: encrypted off-site backups
- **Domain name with Cloudflare DNS**: HTTPS hostnames for the apps (`*.<your domain>`)
- **Cloud provider** (optional): only if you add the public edge proxy, see [CLOUD-PROXY-SETUP.md](CLOUD-PROXY-SETUP.md)

### Software on the management machine

```bash
# macOS
brew install ansible git

# Ubuntu/Debian
sudo apt update && sudo apt install -y ansible git python3-pip

ansible --version
```

## Step 1: Prepare the nodes

### 1.1 Flash and boot

1. Flash Raspberry Pi OS Lite (64-bit) or Ubuntu Server to each Pi, with SSH enabled.
2. Boot the nodes on your network and find their LAN addresses (router DHCP leases, or `nmap -sn 192.168.1.0/24`).

### 1.2 SSH key access

You must have key-based SSH access before bootstrapping. See [SSH-SETUP.md](SSH-SETUP.md) for details.

```bash
ssh-keygen -t ed25519 -C "homelab-key"     # if you do not have a key yet
eval "$(ssh-agent -s)" && ssh-add ~/.ssh/id_ed25519

ssh-copy-id pi@<rpi-home-ip>
ssh-copy-id pi@<rpi-friend-ip>
ssh pi@<rpi-home-ip> "echo SSH working"
```

### 1.3 Run the bootstrap script on each node

```bash
scp scripts/bootstrap.sh pi@<rpi-home-ip>:/tmp/
ssh pi@<rpi-home-ip>
sudo bash /tmp/bootstrap.sh Europe/Vienna pi   # args: timezone, user whose SSH keys are copied
# Repeat for rpi-friend (and the cloud VM, if you have one)
```

Bootstrap creates the `homelab` user with sudo, copies the SSH keys to it, installs Docker and Tailscale, enables UFW and hardens SSH (no root login, no password auth). Afterwards, log in as `homelab` only:

```bash
ssh homelab@<rpi-home-ip>
```

Set the `homelab` user's password to the sudo password you will store in the vault (Step 2.4).

### 1.4 Join Tailscale

On each node:

```bash
sudo tailscale up --ssh --accept-routes --accept-dns --authkey=tskey-auth-XXXXX
tailscale ip -4
```

In the Tailscale admin console, give each node a clear hostname and disable key expiry. The inventory addresses nodes by these MagicDNS hostnames, which can differ from the node name (for example node `rpi-home` has hostname `merry`). Tailscale must be running on the management machine for the names to resolve.

## Step 2: Configure the repository

### 2.1 Clone

```bash
git clone <your-repo-url> homelab && cd homelab
```

### 2.2 Secrets

```bash
cp env/secrets.example.env env/secrets.env
# Fill in every variable from the example file.
```

`env/secrets.env` is git-ignored. Keep a copy in your password manager. Ansible merges `env/common.env`, `env/secrets.env` and `env/local.env` (in that order) into each stack's `.env` on the node.

### 2.3 Inventory

Edit `inventory/hosts.ini`. The left column is the node name; `ansible_host` is the Tailscale hostname (or IP):

```ini
[rpi_nodes]
rpi-home ansible_host=<rpi-home tailscale hostname>
rpi-friend ansible_host=<rpi-friend tailscale hostname>

[cloud_nodes]
; cloud-node ansible_host=<cloud tailscale hostname>   # optional

[primary]
rpi-home

[standby]
rpi-friend
```

Check connectivity:

```bash
ansible rpi_nodes -i inventory/hosts.ini -m ping
```

### 2.4 Sudo passwords (Ansible Vault)

Create the encrypted `inventory/group_vars/all.yml` with the sudo and WiFi passwords. Follow [ANSIBLE-SUDO-SETUP.md](ANSIBLE-SUDO-SETUP.md). Every deploy command prompts for the vault password.

### 2.5 rclone configuration

The B2 and crypt credentials are in `/home/homelab/.config/rclone/rclone.conf` on each node. Ansible does not manage this file. Create it with `rclone config` (a `b2` remote plus a `crypt` remote named `b2-crypt`), or copy it from another node.

## Step 3: Validate

```bash
make validate
```

This checks required files, required secrets, compose file syntax and playbook syntax. Fix any errors before deploying.

## Step 4: Pre-pull images (optional)

```bash
make pull-images
```

Pulls images to the nodes once, to avoid Docker Hub rate limits (100 anonymous pulls per 6 hours) during the first deploy.

## Step 5: Deploy

### 5.1 Base stack (every RPi node)

```bash
make deploy-base
```

Traefik, PostgreSQL and Redis. Tailscale runs as a system service, not in Docker.

### 5.2 Apps (primary only)

The apps play only deploys to a node whose `/opt/stacks/env/local.env` contains `APPS_ENABLED=true`. Set it on the primary once:

```bash
ssh homelab@<rpi-home host> "grep -q '^APPS_ENABLED=true' /opt/stacks/env/local.env || echo 'APPS_ENABLED=true' >> /opt/stacks/env/local.env"
make deploy-apps target=rpi-home
```

Deploys Mealie, Wallos, Sterling PDF, SearXNG, Code Server, Open WebUI, Audiobookshelf, n8n, Homarr and Paperless-ngx. The first run pulls every image and can take 30-45 minutes. If containers are left in `Created` state, run `cd /opt/stacks/apps && docker compose up -d` on the node.

The standby does not run apps; `make failover` enables them there (see [OPERATIONS.md](OPERATIONS.md#failover)).

### 5.3 Backup automation

```bash
make deploy-backup-automation
```

Installs the backup scripts and the daily backup cron job (03:00) with log rotation.

### 5.4 Rclone cloud mounts (optional)

```bash
make deploy-rclone-mount
```

Mounts cloud storage (audiobooks) at `/mnt/audiobooks` for Audiobookshelf. See [RCLONE-MOUNTS.md](RCLONE-MOUNTS.md).

## Step 6: Verify

### 6.1 Health

```bash
make check-health                # base containers on all nodes
make check-urls HOST=rpi-home    # every app endpoint, retrying while they start
```

### 6.2 Service URLs

Via Traefik over HTTPS (Tailscale connected):

| Service        | URL                          |
| -------------- | ---------------------------- |
| Mealie         | `https://mealie.igh.one`     |
| Wallos         | `https://wallos.igh.one`     |
| Sterling PDF   | `https://pdf.igh.one`        |
| SearXNG        | `https://search.igh.one`     |
| Code Server    | `https://code.igh.one`       |
| Open WebUI     | `https://chat.igh.one`       |
| Audiobookshelf | `https://books.igh.one`      |
| n8n            | `https://n8n.igh.one`        |
| Homarr         | `https://dashboard.igh.one`  |
| Paperless-ngx  | `https://paperless.igh.one`  |
| Traefik        | `https://traefik.igh.one`    |

Or directly on the node's Tailscale address: Mealie `:9925`, Wallos `:8282`, Sterling PDF `:8082`, SearXNG `:8083`, Code Server `:8443`, Open WebUI `:8084`, Audiobookshelf `:13378`, n8n `:5678`, Homarr `:7575`, Paperless-ngx `:8000`.

### 6.3 Backups

```bash
make backup-now HOST=rpi-home       # first backup
make restore-test HOST=rpi-friend   # non-destructive restore into /tmp/rclone_restore_test on the node
```
