# Homelab Infrastructure Plan

This repository contains the infrastructure-as-code for a personal homelab. It uses Docker, Ansible, and shell scripts to create a reproducible, resilient, and automated environment.

## Core Concepts

- **Local-First Approach**: Core services run on low-power Raspberry Pi devices on your local network. A cloud VM is used only for edge services (proxy, SSO, monitoring) to keep costs low.
- **Automation with Ansible**: Ansible is used for configuration management and application deployment. This ensures all nodes are configured identically and makes deployments repeatable and idempotent.
- **Containerization with Docker**: All services run in Docker containers, managed by Docker Compose. This isolates applications and makes them portable.
- **Secure Networking with Tailscale**: Tailscale creates a secure overlay network (a WireGuard mesh) connecting all your devices, whether they are at home or in the cloud. This allows services to communicate securely without exposing them directly to the internet.

> **💡 Quick Start**: New to this setup? Jump to [Section 1.5: Make Commands Reference](#15-make-commands-reference) for a complete list of deployment and management commands, or see [QUICKSTART.md](QUICKSTART.md) for a 5-minute setup guide.

---

## 0. Architecture Diagram & Placement

### Architecture Diagram (Local-First)

```ascii
                               +-------------------------+
                               |      Cloud (Linode)     |
                               |-------------------------|
                               |  - Traefik (Edge Proxy) |
                               |  - Authentik (SSO)      |
                               |  - Uptime-Kuma (Monitor)|
                               +-----------|-------------+
                                           | (Tailscale)
+------------------------------------------|-------------------------------------------+
|                                                                                      |
|  (Tailscale Overlay Network)                                                         |
|                                                                                      |
+------------|-------------------------|-----------------------------|-----------------+
             |                         |                             |
  +----------|---------+-+  +----------|---------+-+   +-------------|---------------+
  | RPi-Home (Primary)   |  | RPi-Friend (DR-Lite) |   | India Box (Backups)         |
  |----------------------|  |----------------------|   |-----------------------------|
  | - Base Services      |  | - Base Services      |   | - Restic/Rclone Target (Opt)|
  | - App Services       |  | (Apps disabled)      |   +-----------------------------+
  +----------------------+  +----------------------+


```

```

```

### Service Placement Table

| Service            | Location             | Database           | Port (Local)      | Exposure Path           |
| :----------------- | :------------------- | :----------------- | :---------------- | :---------------------- |
| **Cloud Services** |                      |                    |                   |                         |
| Traefik            | Cloud VM             | -                  | 80, 443           | Public Internet         |
| Authentik          | Cloud VM             | Embedded Postgres  | 9000, 9443        | Traefik (`auth.DOMAIN`) |
| Uptime-Kuma        | Cloud VM             | Embedded           | 3001              | Traefik (`kuma.DOMAIN`) |
| **Base Services**  |                      |                    |                   |                         |
| Tailscale          | All Nodes            | -                  | Host Network      | Tailscale Network       |
| AdGuard Home       | RPi-Home, RPi-Friend | -                  | 53, 3000          | LAN (via Tailscale DNS) |
| Kuma Agent         | RPi-Home, RPi-Friend | -                  | -                 | Push to Cloud Kuma      |
| Postgres           | RPi-Home, RPi-Friend | Self               | `127.0.0.1:5432`  | Localhost Only          |
| Redis              | RPi-Home, RPi-Friend | Self               | `127.0.0.1:6379`  | Localhost Only          |
| Backups (restic)   | All Nodes            | -                  | -                 | Cron / SSH              |
| **App Services**   |                      |                    |                   |                         |
| FreshRSS           | RPi-Home             | Postgres           | `127.0.0.1:8081`  | Traefik via Tailscale   |
| Mealie             | RPi-Home             | Postgres           | `127.0.0.1:9925`  | Traefik via Tailscale   |
| Wallos             | RPi-Home             | MariaDB (if added) | `127.0.0.1:8282`  | Traefik via Tailscale   |
| SterlingPDF        | RPi-Home             | -                  | `127.0.0.1:8082`  | Traefik via Tailscale   |
| SearXNG            | RPi-Home             | Redis              | `127.0.0.1:8083`  | Traefik via Tailscale   |
| VS Code Server     | RPi-Home             | -                  | `127.0.0.1:8443`  | Traefik via Tailscale   |
| OpenWebUI          | RPi-Home             | -                  | `127.0.0.1:8084`  | Traefik via Tailscale   |
| Audiobookshelf     | RPi-Home             | -                  | `127.0.0.1:13378` | Traefik via Tailscale   |

---

## 1. Environment Setup

This section covers how to set up the physical and virtual nodes for your homelab.

### Prerequisites

- **Management Machine**: A computer with `ansible`, `ssh`, and `git` installed.
- **Tailscale Account**: A free Tailscale account.
- **Cloud Provider Account**: A Linode account (or any other cloud provider).
- **Backblaze B2 Account**: For offsite backups.
- **Raspberry Pis**: Two Raspberry Pi 5s with SSDs.

### Node Bootstrap (for RPis and other Linux boxes)

This process prepares a fresh Debian-based system (like Raspberry Pi OS or Debian/Ubuntu on the India Box/Cloud VM) to be managed by our Ansible setup.

1. **Install OS**: Flash a fresh copy of Raspberry Pi OS Lite (64-bit) or Debian/Ubuntu onto your device's SSD/disk.
2. **Initial Login**: Log in to the device (e.g., via SSH with the default user or direct console access).
3. **Copy Bootstrap Script**: Copy the `scripts/bootstrap.sh` script from this repository to the device. You can use `scp`:

   ```bash
   scp scripts/bootstrap.sh default_user@<device_ip>:/tmp/bootstrap.sh
   ```

4. **Run the Script**: SSH into the device and run the script as root.

   ```bash
   ssh default_user@<device_ip>
   sudo bash /tmp/bootstrap.sh
   ```

   The script will:- Create a new `homelab` user for Ansible to use.

   - Harden SSH by disabling root login and password authentication.
   - Install essential software: Docker, Docker Compose, UFW (firewall), Fail2ban, and unattended security upgrades.
   - Install Tailscale.

5. **Reboot**: After the script finishes, reboot the node: `sudo reboot`.
6. **Join Tailscale Network**: After rebooting, log back in and run the `tailscale up` command printed by the script. You will need to generate an auth key from your Tailscale Admin Console (Settings -> Auth keys).

   ```bash
   # Example command shown by the script
   sudo tailscale up --ssh --accept-routes --accept-dns --authkey=tskey-auth-YOUR_KEY...
   ```

   **IMPORTANT**: Enable the `--ssh` flag. This allows Tailscale to manage SSH connections, so you can connect to your nodes using their Tailscale IP without worrying about local network changes.

7. **Authorize Node**: In the Tailscale admin console, authorize the new node. You may also want to disable key expiry for server-like devices.

Repeat this process for `RPi-Home`, `RPi-Friend`, and the `India Box`.

### SSH Access

Once a node is on the Tailscale network and has the `--ssh` flag enabled, you can connect to it from any other device in your Tailnet (like your management machine).

- **Find the Tailscale IP**: In the Tailscale admin console, find the IP address of the node you want to connect to (e.g., `100.X.X.X`).
- **SSH as `homelab` user**:

  ```bash
  ssh homelab@<tailscale_ip>
  ```

  This works because your management machine's SSH key (`~/.ssh/id_rsa.pub` or similar) was copied to the `homelab` user during the bootstrap process.

### Cloud VM (Linode) Setup

The cloud VM runs the "edge" services.

1. **Create VM**: In Linode, create a "Nanode" (1 GB RAM) instance running Ubuntu 22.04.
2. **Add SSH Key**: Add your public SSH key to the Linode instance during creation so you can log in as `root`.
3. **Bootstrap**: SSH into the new VM as `root` and follow the same **Node Bootstrap** process above.
4. **Deploy Edge Services**: The cloud services (Traefik, Authentik, Uptime-Kuma) are managed separately. You can copy the example `docker-compose.yml` from the "Cloud Edge Example" section of the old README, place it in `/root/cloud-edge/`, and run `docker compose up -d`.

---

## 1.5. Make Commands Reference

This repository includes a `Makefile` that provides convenient shortcuts for all common operations. Here's a complete reference of all available commands:

### 🔍 **Validation & Setup**

```bash
make validate
```

**Purpose**: Validates your homelab setup before deployment

- Checks all required files exist (configs, compose files, inventory)
- Verifies all required secrets are defined in `env/secrets.env`
- Validates Docker Compose syntax (if Docker is available)
- Validates Ansible playbook syntax
- **When to use**: Run this first before any deployment to catch configuration errors

### 🚀 **Deployment Commands**

```bash
make deploy-base
```

**Purpose**: Deploy core infrastructure to all nodes

- Installs base services: Tailscale, AdGuard, PostgreSQL, Redis
- Sets up networking and security
- Configures shared databases
- **Target**: All nodes in inventory (`rpi-home`, `rpi-friend`, `india-box`)
- **Safe to re-run**: Yes (idempotent)

```bash
make deploy-apps target=rpi-home
```

**Purpose**: Deploy application stack to a specific node

- Installs applications: FreshRSS, Mealie, Wallos, VS Code Server, etc.
- **Required parameter**: `target=<hostname>` (e.g., `rpi-home`, `rpi-friend`)
- **When to use**: After `deploy-base`, only on nodes where you want apps running
- **Example**: `make deploy-apps target=rpi-home`

```bash
make deploy-backup-automation
```

**Purpose**: Set up automated backup cron jobs on all nodes

- Installs backup scripts (`backup_now.sh`, `restore_latest.sh`)
- Configures daily cron jobs for automated backups
- Sets up Restic repositories and Rclone for cloud storage
- **Target**: All nodes
- **Schedule**: Runs at different times per node to avoid conflicts

### 💾 **Backup & Recovery Commands**

```bash
make backup-now HOST=rpi-home
```

**Purpose**: Trigger an immediate backup on a specific host

- Dumps databases, backs up Docker volumes and configurations
- Uploads encrypted backup to Backblaze B2 (and optionally Linode)
- **Required parameter**: `HOST=<hostname>`
- **Example**: `make backup-now HOST=rpi-home`
- **Duration**: ~5-15 minutes depending on data size

```bash
make restore-latest HOST=rpi-friend
```

**Purpose**: **🚨 DESTRUCTIVE** - Restore latest backup to a host

- **Stops all containers** and restores data from most recent backup
- Restores databases, Docker volumes, and configurations
- **Use cases**: Disaster recovery, migrating data between nodes
- **⚠️ Warning**: This will overwrite all existing data on the target host
- **Required parameter**: `HOST=<hostname>`

```bash
make restore-test HOST=rpi-friend
```

**Purpose**: **NON-DESTRUCTIVE** - Test restore to temporary directory

- Downloads and extracts latest backup to `/tmp/restic_restore_test/`
- Does NOT affect running services or existing data
- **Use for**: Verifying backup integrity before actual restore
- **Required parameter**: `HOST=<hostname>`
- **Cleanup**: Remove `/tmp/restic_restore_test/` when done

### ⚡ **High Availability Commands**

```bash
make promote-friend
```

**Purpose**: Promote `rpi-friend` from standby to primary app host

- Enables applications on `rpi-friend`
- **Use cases**:
  - When `rpi-home` is offline/broken
  - During planned maintenance
  - When shipping `rpi-home` to Austria
- **Note**: You may want to disable apps on `rpi-home` first to avoid conflicts

### 🔧 **Alternative: Direct SSH Commands**

If you prefer running commands directly via SSH instead of using `make`:

```bash
# Deploy base services manually
ansible-playbook -i inventory/hosts.ini ansible/site.yml --tags "base"

# Deploy apps to specific host
ansible-playbook -i inventory/hosts.ini ansible/site.yml --tags "apps" --limit rpi-home

# Manual backup on specific host
ssh homelab@<host-ip> "cd /opt/homelab && ./scripts/backup_now.sh"

# Manual restore test
ssh homelab@<host-ip> "cd /opt/homelab && ./scripts/restore_latest.sh --dry-run"
```

### 📋 **Command Cheat Sheet**

| Task                      | Command                                                                 | Notes                          |
| ------------------------- | ----------------------------------------------------------------------- | ------------------------------ |
| **First-time setup**      | `make validate && make deploy-base && make deploy-apps target=rpi-home` | Complete initial deployment    |
| **Add backup automation** | `make deploy-backup-automation`                                         | Set up automated daily backups |
| **Manual backup**         | `make backup-now HOST=rpi-home`                                         | Immediate backup               |
| **Test restore**          | `make restore-test HOST=rpi-friend`                                     | Non-destructive backup test    |
| **Failover**              | `make promote-friend`                                                   | Switch to standby node         |
| **Disaster recovery**     | `make restore-latest HOST=rpi-home`                                     | ⚠️ Destructive restore         |
| **Check setup**           | `make validate`                                                         | Pre-flight validation          |

### 🎯 **Common Workflows**

**Initial Setup (Austria):**

```bash
make validate
make deploy-base
make deploy-apps target=rpi-home
make deploy-backup-automation
```

**Monthly Backup Test:**

```bash
make restore-test HOST=rpi-friend
# SSH in and verify /tmp/restic_restore_test/
```

**Migration to Austria:**

```bash
# Before shipping rpi-home
make promote-friend

# After setting up rpi-home in Austria
make restore-latest HOST=rpi-home
make deploy-apps target=rpi-home
```

---

## 2. Repository Structure & File Explanations

This is a breakdown of what each file and directory is for.

```
homelab/
├── Makefile                # Shortcuts for common Ansible commands (deploy, backup, etc.).
├── README.md               # This file.
├── ansible/
│   ├── roles/
│   │   ├── common/         # Ansible role to set up directories and copy files.
│   │   └── compose-deploy/ # Ansible role to deploy a Docker Compose stack.
│   └── site.yml            # The main Ansible playbook that orchestrates deployments.
├── env/
│   ├── common.env          # Non-secret environment variables (TZ, PUID, paths).
│   ├── local.env           # Local overrides for a specific machine (e.g., APPS_ENABLED).
│   └── secrets.example.env # A template for your secrets. Copy to secrets.env.
├── inventory/
│   └── hosts.ini           # Ansible inventory. Defines your nodes and their IPs.
├── scripts/
│   ├── backup_now.sh       # Performs backups using Restic.
│   ├── bootstrap.sh        # Prepares a new node for management.
│   ├── db_dump.sh          # Dumps databases before a backup.
│   ├── promote_friend.sh   # Promotes the DR node to primary.
│   └── restore_latest.sh   # Restores data from a Restic backup.
└── stacks/
    ├── apps/
    │   └── compose.yml     # Docker Compose file for the main applications.
    ├── base/
    │   └── compose.yml     # Docker Compose file for base services (DBs, Tailscale).
    └── overrides/
        ├── cloud.traefik.yml # Example config for exposing services via the cloud proxy.
        └── local.private.yml # Override to ensure services only bind to localhost.
```

---

## Operational Guide: From Setup to Disaster Recovery

This guide provides detailed, step-by-step instructions for setting up, managing, and maintaining your homelab.

### Part 1: Understanding the Configuration

#### How the Environment Files Work (`common.env`, `local.env`, `secrets.env`)

You do **not** need to create these files on every node. You manage **one central copy** of these files in the `env/` directory of this repository. When you run Ansible, it copies these files to each target node.

- `env/secrets.env`:

  - **What it is**: For all your secrets: API keys, passwords, etc.
  - **Example**: `RESTIC_PASSWORD=your-strong-password`, `B2_APP_KEY=...`
  - **How it's used**: You must copy `secrets.example.env` to `secrets.env` and fill it out. This file is listed in `.gitignore` and **must never be committed to git**.

- `env/common.env`:

  - **What it is**: For non-secret variables that are the **same for all nodes**.
  - **Example**: `TZ=Asia/Kolkata`, `PUID=1000`, `APPDATA_PATH=/srv/appdata`.
  - **How it's used**: Ansible copies this file to every node. All containers on all nodes will use these values.

- `env/local.env`:

  - **What it is**: For variables that might **differ between nodes**. The most important one is `APPS_ENABLED`.
  - **Example**: `APPS_ENABLED=true`.
  - **How it's used**: This is the key to controlling which machine is the "primary."
    - To make `rpi-home` the primary app server, you would set `APPS_ENABLED=true` in this file, then run the deployment for `rpi-home`.
    - To make `rpi-friend` the primary, you would do the same for `rpi-friend`.
    - The `promote_friend.sh` script automates changing this value on the remote machine.

#### How `APPS_ENABLED` Works

The main Ansible playbook (`ansible/site.yml`) has a special condition for deploying the applications:

```yaml
- name: Deploy Application Stack
  hosts: all
  # ...
  when: APPS_ENABLED | default(false) | bool
```

This means the "Deploy Application Stack" part of the playbook will **only run** if Ansible finds `APPS_ENABLED=true` in the environment files for that specific host. If it's `false` or not set, the entire app deployment is skipped for that host.

#### How `make deploy-apps target=rpi-home` Works

This is a breakdown of the magic:

1. You run `make deploy-apps target=rpi-home`.
2. The `Makefile` translates this into a full Ansible command:
   `ansible-playbook ansible/site.yml --tags "apps" --limit rpi-home`
3. Let's break down the Ansible command:
   - `ansible-playbook ansible/site.yml`: Run the main playbook.
   - `--tags "apps"`: Only run the parts of the playbook tagged with "apps".
   - `--limit rpi-home`: **Only run against the `rpi-home` host** from your `inventory/hosts.ini` file. `rpi-friend` and other hosts are ignored for this command.
4. Ansible connects to `rpi-home`, reads the environment files it finds there (which it previously copied), sees `APPS_ENABLED=true`, and proceeds to deploy the application containers.

### Part 2: Step-by-Step Scenarios

Here are detailed walkthroughs for common operational tasks. **Run these commands from your management machine**, in the root of this repository.

---

#### Scenario 1: Initial Setup From Scratch

This is what you do when you have brand new, freshly bootstrapped nodes.

**Goal**: Deploy base services to all nodes and application services only to `rpi-home`.

**Order of Commands:**

1. **Set `rpi-home` as the App Host**:
   Edit `env/local.env` and make sure it contains:

   ```
   APPS_ENABLED=true
   ```

2. **Deploy Base Services to ALL Nodes**:
   This command connects to `rpi-home` and `rpi-friend` (and any other hosts in your inventory) and deploys the `base` stack (Postgres, Redis, Tailscale, etc.).

   ```bash
   make deploy-base
   ```

3. **Deploy App Services to `rpi-home` ONLY**:
   This command targets **only** `rpi-home` and, because `APPS_ENABLED` is true, deploys the application stack (FreshRSS, Mealie, etc.).

   ```bash
   make deploy-apps target=rpi-home
   ```

4. **(Optional) Deploy Backup Automation**:
   If you want to set up automated backups immediately, make sure `BACKUP_AUTOMATION_ENABLED=true` is set in `env/local.env` for `rpi-home`, then run:

   ```bash
   make deploy-backup-automation
   ```

**Result**: `rpi-home` is running both base and app services with optional automated backups. `rpi-friend` is running only base services, acting as a warm standby.

---

#### Scenario 2: Performing a Manual Backup

**Goal**: Trigger a backup of `rpi-home`'s data to Backblaze B2.

**Order of Commands:**

1. **Standard Backup**:

   **Primary Method (Recommended):**

   ```bash
   make backup-now HOST=rpi-home
   ```

   **Manual Method (for reference):**

   ```bash
   ssh rpi-home "sudo /opt/backups/backup_now.sh"
   ```

2. **(Optional) Pre-Move Full Backup**:
   If you are about to move and want to include all your media files, use the `--with-media` flag.

   **Manual Method (no make shortcut for this variant):**

   ```bash
   ssh homelab@<rpi_home_ip> "sudo /opt/backups/backup_now.sh --with-media"
   ```

**Result**: The script on `rpi-home` will dump the databases, then Restic will back up the app data and DB dumps to your encrypted B2 bucket.

---

#### Scenario 3: Validating Backups (Disaster Recovery Drill)

**Goal**: Test your backups by restoring them to `rpi-friend` **without** interrupting the live services on `rpi-home`. This is the most critical maintenance task you can perform.

**Order of Commands:**

1. **Run a Non-Destructive Restore on `rpi-friend`**:

   **Primary Method (Recommended):**

   ```bash
   make restore-test HOST=rpi-friend
   ```

   **Manual Method (for reference):**

   ```bash
   ssh rpi-friend "sudo /opt/backups/restore_latest.sh --test"
   ```

2. **Verify the Restored Data**:
   The script will restore the latest backup to a temporary directory: `/tmp/restic_restore_test`. SSH into `rpi-friend` and inspect the contents.

   ```bash
   ssh homelab@<rpi_friend_ip>
   sudo ls -l /tmp/restic_restore_test/srv/appdata
   sudo ls -l /tmp/restic_restore_test/tmp/db_dumps
   exit
   ```

   Check that the file names and dates look correct.

3. **Clean Up the Test Restore**:
   Once you are satisfied, remove the temporary directory.

   ```bash
   ssh homelab@<rpi_friend_ip> "sudo rm -rf /tmp/restic_restore_test"
   ```

**Result**: You have successfully verified that your backups are working and can be restored, all with zero downtime.

---

#### Scenario 4: Full Disaster Recovery (Promoting `rpi-friend`)

**Goal**: `rpi-home` has died. You need to make `rpi-friend` the new primary application server.

**Order of Commands:**

1. **Perform a Full Restore on `rpi-friend`**:
   **Warning: This is a destructive action** that will stop services and overwrite data on `rpi-friend`.

   **Primary Method (Recommended):**

   ```bash
   make restore-latest HOST=rpi-friend
   ```

   **Manual Method (for reference):**

   ```bash
   ssh rpi-friend "sudo /opt/backups/restore_latest.sh"
   ```

   This restores the latest application data and database dumps to their proper locations (`/srv/appdata`, etc.).

2. **Promote `rpi-friend`**:
   From your management machine, run the promotion script.

   ```bash
   bash scripts/promote_friend.sh
   ```

   This script does two things automatically:
   a. It SSHes into `rpi-friend` and changes its `/opt/stacks/env/local.env` to `APPS_ENABLED=true`.
   b. It runs `make deploy-apps target=rpi-friend` to start the application stack using the newly restored data.

3. **Update DNS/Proxy (If Necessary)**:
   If your cloud Traefik instance was pointing to `rpi-home`'s Tailscale IP, you must now update it to point to `rpi-friend`'s Tailscale IP.

**Result**: `rpi-friend` is now your live, primary application server. Downtime is limited to the time it takes to restore and deploy the apps.

---

#### Scenario 5: Adding a New Application

**Goal**: You want to add a new service, for example, `Gitea`.

**Order of Commands:**

1. **Edit the Apps Compose File**:
   Open `stacks/apps/compose.yml` and add the service definition for Gitea. Make sure to bind its port to `127.0.0.1` and define its volumes under `${APPDATA_PATH}/gitea`.
2. **Add Secrets (If Needed)**:
   If Gitea needs a database password or other secrets, add the variables to `env/secrets.env`.
3. **Re-run the App Deployment**:
   Deploy the changes to your primary server (`rpi-home`).

   ```bash
   make deploy-apps target=rpi-home
   ```

   Docker Compose will see the new service definition and start only the Gitea container, leaving all other running services untouched.

**Result**: Your new application is now running, managed by the same automated workflow.

---

#### Scenario 6: Setting Up Automated Backups with Ansible

**Goal**: Deploy automated backup cron jobs to your primary node (`rpi-home`) using Ansible.

**Order of Commands:**

1.  **Configure Backup Variables**:
    Edit `env/local.env` to enable backup automation for your primary node:

    ```bash
    # Edit the local environment file
    nano env/local.env
    ```

    Add or modify these variables:

    ```
    BACKUP_AUTOMATION_ENABLED=true
    BACKUP_MIRROR_ENABLED=false  # Set to true if you want Linode mirroring
    BACKUP_WITH_MEDIA_ENABLED=true  # Set to true for pre-move period
    ```

2.  **Deploy Backup Automation**:

    **Primary Method (Recommended):**

    ```bash
    make deploy-backup-automation
    ```

    **Manual Method (for reference):**

    ```bash
    ansible-playbook -i inventory/hosts.ini ansible/site.yml --tags "backup-automation"
    ```

3.  **Verify Installation**:
    Check that the cron jobs were properly installed on the target node:

    ```bash
    ssh rpi-home "sudo crontab -l"
    ```

4.  **Test the Backup**:
    Manually trigger a backup to ensure everything is working:
    ```bash
    make backup-now HOST=rpi-home
    ```

**Result**: Your primary node now has automated daily backups, weekly repository checks, and optional features like Linode mirroring and monthly full backups, all managed through Ansible.

**Post-Move Adjustments**: After moving to Austria, update `env/local.env` to set `BACKUP_WITH_MEDIA_ENABLED=false` and re-run `make deploy-backup-automation` to disable the monthly full backup with media.

---

#### Scenario 7: Using the India Box for Offsite Backups

**Goal**: The `India Box` is primarily an offsite target for backups, providing an extra layer of redundancy. This scenario details how to use it for backup validation.

**Setup**:

1. **Bootstrap the India Box**: Follow the same bootstrap procedure as the Raspberry Pi nodes.
2. **Add to Inventory**: Add the `india-box` and its Tailscale IP to `inventory/hosts.ini`.
3. **Deploy Base Services**: Run `make deploy-base`. This is important as it ensures `restic` and other necessary tools are available on the box via the Ansible deployment. Note that `APPS_ENABLED` should be `false` for this node.

**Execution**:
You can treat the India Box as another DR node, similar to `rpi-friend`. You can validate your main backups by restoring them to this box.

1. **Run a Non-Destructive Restore on `india-box`**:
   This command is identical to the DR drill for `rpi-friend`, but targets the `india-box`.

   **Primary Method (Recommended):**

   ```bash
   make restore-test HOST=india-box
   ```

   **Manual Method (for reference):**

   ```bash
   ssh india-box "sudo /opt/backups/restore_latest.sh --test"
   ```

2. **Verify and Clean Up**:
   SSH into the `india-box`, check the restored files in `/tmp/restic_restore_test`, and then remove the directory.

   ```bash
   ssh homelab@<india_box_ip>
   sudo ls -l /tmp/restic_restore_test/srv/appdata
   sudo rm -rf /tmp/restic_restore_test
   exit
   ```

**Result**: You have now used your dedicated offsite backup node to validate the integrity of your primary backups without touching your hot standby (`rpi-friend`). This is a robust DR strategy.

---

## 6. Automated Backup Setup

To ensure your data is automatically backed up, you can use Ansible to deploy cron jobs to your nodes. This section covers the complete automation setup using both Ansible and manual methods.

### Setting Up Automated Backups

**Goal**: Configure automatic daily backups with weekly repository checks and optional mirroring to Linode.

#### Method 1: Ansible-Based Deployment (Recommended)

This method uses Ansible to consistently deploy backup automation across your nodes.

**Step 1: Configure Backup Automation Variables**

Edit your `env/local.env` file for the specific node where you want to enable backups (typically `rpi-home`):

```bash
# Enable automated backup cron jobs (set to true for primary nodes)
BACKUP_AUTOMATION_ENABLED=true
# Enable weekly mirroring to Linode Object Storage (optional)
BACKUP_MIRROR_ENABLED=false
# Enable monthly full backup with media (for pre-move period only)
BACKUP_WITH_MEDIA_ENABLED=true
```

**Step 2: Deploy Backup Automation**

**Primary Method (Recommended):**

```bash
make deploy-backup-automation
```

**Manual Method (for reference):**

```bash
ansible-playbook -i inventory/hosts.ini ansible/site.yml --tags "backup-automation"
```

**Step 3: Verify Deployment**

Check that the cron jobs were installed:

```bash
ssh rpi-home "sudo crontab -l"
```

#### Method 2: Manual SSH Setup (Alternative)

If you prefer to set up cron jobs manually without Ansible:

**Step 1: SSH into your primary node and edit the root crontab:**

```bash
ssh rpi-home
sudo crontab -e
```

**Step 2: Add the following cron job entries:**

```cron
# Daily backup at 3:00 AM (important data only, no media)
0 3 * * * /opt/backups/backup_now.sh >> /var/log/restic_backup.log 2>&1

# Weekly repository check at 4:00 AM on Sundays
0 4 * * 0 restic -r $(grep RESTIC_REPOSITORY /opt/stacks/env/common.env | cut -d= -f2) check >> /var/log/restic_check.log 2>&1

# Weekly copy to Linode mirror at 5:00 AM on Sundays (optional)
0 5 * * 0 /opt/backups/backup_now.sh --copy-to-linode >> /var/log/restic_copy.log 2>&1

# Monthly backup with media (first Sunday of each month at 6:00 AM) - for pre-move period only
0 6 1-7 * * 0 /opt/backups/backup_now.sh --with-media >> /var/log/restic_backup_full.log 2>&1
```

#### Step 2: Set Up Log Rotation

Create a logrotate configuration to prevent log files from growing too large:

```bash
ssh rpi-home
sudo tee /etc/logrotate.d/homelab-backups << 'EOF'
/var/log/restic_*.log {
    daily
    missingok
    rotate 30
    compress
    notifempty
    create 0644 root root
}
EOF
```

#### Step 3: Test the Automated Backup

Manually trigger the backup script to ensure it works correctly:

**Primary Method (from management machine):**

```bash
make backup-now HOST=rpi-home
```

**Manual Method:**

```bash
ssh rpi-home "sudo /opt/backups/backup_now.sh"
```

Check the log file to verify it ran successfully:

```bash
ssh rpi-home "sudo tail -f /var/log/restic_backup.log"
```

### Backup Schedule Explanation

- **Daily at 3:00 AM**: Standard backup of application data and database dumps (excludes media)
- **Weekly on Sunday at 4:00 AM**: Repository integrity check using `restic check`
- **Weekly on Sunday at 5:00 AM**: Optional copy to Linode Object Storage for additional redundancy
- **Monthly (first Sunday at 6:00 AM)**: Full backup including media (disable this after your move to Austria)

### Post-Move Adjustments

After you've moved to Austria and set up your new main homelab server:

1. **Disable the monthly full backup** by commenting out or removing that cron line
2. **Run a one-time media cleanup**:
   ```bash
   ssh rpi-home "sudo /opt/backups/backup_now.sh --prune-media"
   ```
3. **Continue with daily important-data-only backups**

### Monitoring Backup Status

To check if your backups are running successfully:

1. **Check recent backup logs**:

   ```bash
   ssh rpi-home "sudo tail -20 /var/log/restic_backup.log"
   ```

2. **List recent snapshots**:

   ```bash
   ssh rpi-home "restic -r \$(grep RESTIC_REPOSITORY /opt/stacks/env/common.env | cut -d= -f2) snapshots --latest 5"
   ```

3. **Check repository statistics**:
   ```bash
   ssh rpi-home "restic -r \$(grep RESTIC_REPOSITORY /opt/stacks/env/common.env | cut -d= -f2) stats"
   ```

### Troubleshooting Common Issues

**Backup fails with permission errors**: Ensure the backup script has executable permissions:

```bash
ssh rpi-home "sudo chmod +x /opt/backups/*.sh"
```

**Repository not found error**: Verify your secrets are correctly set:

```bash
ssh rpi-home "sudo cat /opt/stacks/env/secrets.env | grep -E '(RESTIC|B2)'"
```

**Cron job not running**: Check if the cron service is active:

```bash
ssh rpi-home "sudo systemctl status cron"
```

---

## 7. Security Overview

- **SSO Everywhere**: Use Traefik + Authentik forward-auth for all web services.
- **Local Binds**: All container ports are bound to `127.0.0.1` by default.
- **No Cross-Site DB Calls**: Databases are co-located with their applications.
- **SSH Keys Only**: The bootstrap script disables password authentication.
- **Secret Management**: `env/secrets.env` is in `.gitignore`. Consider using `sops` for encryption at rest.
- **Periodic Updates**: `unattended-upgrades` is enabled. Periodically pull new container images.
- **Container Pinning**: For production, change image tags from `:latest` to specific versions.
- **Least-Privilege DB Users**: Create dedicated database users for each application.
- **Firewall Enabled**: UFW denies all incoming traffic except for SSH and Tailscale.
- **AdGuard UI Restriction**: After setup, bind the AdGuard Home UI to `127.0.0.1` and access via SSH port forwarding.

---

## 7. 30-Day Migration Timeline

- **Week 0–1 (Setup & Baseline)**

  - [ ] Bootstrap both RPis and bring them up on Tailscale.
  - [ ] Configure Ansible (`inventory/hosts.ini`, `env/secrets.env`).
  - [ ] Run `make deploy-base` for both nodes.
  - [ ] Set `APPS_ENABLED=true` on `RPi-Home` and run `make deploy-apps target=rpi-home`.
  - [ ] Configure AdGuard Home, then restrict its UI.

- **Week 2 (Backups & Monitoring)**

  - [ ] Set up the cloud VM (Traefik, Authentik, Uptime-Kuma).
  - [ ] Configure Authentik and expose a test service.
  - [ ] Run a manual backup test: `sudo /opt/backups/backup_now.sh --with-media`.
  - [ ] Set up the daily backup cron job.
  - [ ] Add monitors in Uptime-Kuma.

- **Week 3 (DR Drill)**

  - [ ] On `RPi-Friend`, perform a non-destructive restore test: `sudo /opt/backups/restore_latest.sh --test`.
  - [ ] Verify the restored data, then clean up the test directory.

- **Move Week (Final Backup & Transition)**

  - [ ] Pause non-essential services.
  - [ ] Run a final, verified full backup: `sudo /opt/backups/backup_now.sh --with-media`.
  - [ ] Run `restic check` to ensure repository integrity.
  - [ ] Shut down and pack `RPi-Home`.

- **Arrival in Austria (New Steady-State)**

  - [ ] Set up the new main homelab server.
  - [ ] Restore media and heavy workloads from Backblaze B2.
  - [ ] Switch all nodes to "important-only" backups (without `--with-media`).
  - [ ] Prune the old media backups to save cost: `sudo /opt/backups/backup_now.sh --prune-media`.
