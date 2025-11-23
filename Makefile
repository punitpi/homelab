# Makefile for managing the homelab stacks

# Default target
all: help

# Variables
ANSIBLE_PLAYBOOK=ansible-playbook -i inventory/hosts.ini

.PHONY: help validate deploy-base deploy-apps deploy-cloud deploy-backup-automation deploy-rclone-mount deploy-all backup-now backup-all restore-latest restore-test watch-backup backup-status backup-log failover check-health show-resources show-logs update-packages configure-network configure-dns enable-tailscale-dns disable-tailscale-dns reboot-nodes pull-images update-images cleanup

help:
	@echo "Homelab Management Commands"
	@echo ""
	@echo "Note: All deployment commands will prompt for Ansible Vault password"
	@echo ""
	@echo "Validation & Testing:"
	@echo "  make validate                 - Validate homelab setup"
	@echo "  make check-health             - Check service health on all nodes"
	@echo ""
	@echo "Deployment:"
	@echo "  make deploy-base              - Deploy base stack (PostgreSQL, Redis) to RPi nodes"
	@echo "  make deploy-apps              - Deploy applications to specific RPi node"
	@echo "  make deploy-cloud             - Deploy cloud proxy (Authentik, Uptime Kuma) to cloud-node"
	@echo "  make deploy-backup-automation - Deploy automated backup cron jobs to all nodes"
	@echo "  make deploy-rclone-mount      - Deploy rclone cloud storage mounts"
	@echo "  make deploy-all               - Deploy everything (base + mounts + apps + backups)"
	@echo ""
	@echo "Docker Images:"
	@echo "  make pull-images              - Pre-pull all Docker images to all nodes"
	@echo "  make update-images            - Update all images to latest versions on all nodes"
	@echo ""
	@echo "Backup & Restore:"
	@echo "  make backup-now               - Trigger manual backup on a host"
	@echo "  make watch-backup             - Monitor backup progress in real-time"
	@echo "  make backup-log               - Show last 50 lines of backup log"
	@echo "  make backup-status            - Check if backup is currently running"
	@echo "  make backup-all               - Run backup on all nodes"
	@echo "  make restore-latest           - Restore backup (DESTRUCTIVE - use FROM= for cross-node)"
	@echo "  make restore-test             - Test restore to temp (use FROM= for cross-node)"
	@echo ""
	@echo "High Availability:"
	@echo "  make failover                 - Switch active node (restores data, stops old active)"
	@echo "  make failover SKIP_RESTORE=true - Fast switch without data restore"
	@echo "  make failover STOP_OLD_ACTIVE=false - Skip stopping services on old active"
	@echo ""
	@echo "Maintenance:"
	@echo "  make update-packages          - Update system packages on all nodes"
	@echo "  make configure-network        - Configure network priority (Ethernet over WiFi)"
	@echo "  make configure-dns            - Configure DNS with Tailscale + fallbacks"
	@echo "  make enable-tailscale-dns     - Enable Tailscale DNS on all nodes"
	@echo "  make disable-tailscale-dns    - Disable Tailscale DNS on all nodes"
	@echo "  make reboot-nodes             - Reboot all nodes (causes downtime)"
	@echo "  make cleanup target=<type>    - Clean up resources (cloud-base, docker, rpi-docker, cloud-docker)"
	@echo ""
	@echo "Monitoring:"
	@echo "  make show-logs                - Show recent Docker logs from a host"
	@echo "  make show-resources           - Show resource usage (CPU, memory, disk)"
	@echo ""
	@echo "Examples:"
	@echo "  make validate"
	@echo "  make deploy-base"
	@echo "  make deploy-apps target=rpi-home"
	@echo "  make deploy-all target=rpi-home                  # Full deployment with explicit target"
	@echo "  make deploy-all                                  # Uses .active-node file for target"
	@echo "  make deploy-cloud"
	@echo "  make backup-now HOST=rpi-home"
	@echo "  make watch-backup HOST=rpi-home"
	@echo "  make failover                                    # Full failover (restore + stop old)"
	@echo "  make failover SKIP_RESTORE=true                  # Fast switch without restore"
	@echo "  make failover STOP_OLD_ACTIVE=false              # DR mode (old node unreachable)"
	@echo "  make cleanup target=cloud-base"
	@echo "  make check-health"


# --- Validation Target ---

validate:
	@echo "Running homelab setup validation..."
	./scripts/validate_setup.sh

# --- Deployment Targets ---

deploy-base:
	@echo "Deploying base services to all nodes..."
	$(ANSIBLE_PLAYBOOK) ansible/site.yml --tags "base" --ask-vault-pass

deploy-apps:
	@if [ -z "$(target)" ]; then \
		echo "ERROR: Must specify target host, e.g., 'make deploy-apps target=rpi-home'"; \
		exit 1; \
	fi
	@echo "Deploying applications to $(target)..."
	$(ANSIBLE_PLAYBOOK) ansible/site.yml --tags "apps" --limit $(target) --ask-vault-pass

deploy-cloud:
	@echo "Deploying cloud proxy services (Authentik, Uptime Kuma) to cloud-node..."
	@echo "Note: Cloud proxy is optional. Traefik runs on RPi for Tailscale-only HTTPS."
	$(ANSIBLE_PLAYBOOK) ansible/site.yml --tags "cloud" --limit cloud_nodes --ask-vault-pass

deploy-backup-automation:
	@echo "Deploying backup automation to all nodes..."
	$(ANSIBLE_PLAYBOOK) ansible/site.yml --tags "backup-automation" --ask-vault-pass

deploy-rclone-mount:
	@if [ -z "$(target)" ]; then \
		if [ -f .active-node ]; then \
			TARGET=$$(cat .active-node | tr -d '[:space:]'); \
		else \
			echo "ERROR: Must specify target host or have .active-node file"; \
			echo "Usage: make deploy-rclone-mount target=rpi-home"; \
			exit 1; \
		fi; \
	else \
		TARGET="$(target)"; \
	fi; \
	echo "Deploying rclone mounts to $$TARGET..."; \
	$(ANSIBLE_PLAYBOOK) ansible/site.yml --tags "rclone-mount" --limit $$TARGET --ask-vault-pass

deploy-all:
	@if [ -z "$(target)" ]; then \
		if [ -f .active-node ]; then \
			TARGET=$$(cat .active-node | tr -d '[:space:]'); \
		else \
			echo "ERROR: Must specify target host or have .active-node file"; \
			echo "Usage: make deploy-all target=rpi-home"; \
			exit 1; \
		fi; \
	else \
		TARGET="$(target)"; \
	fi; \
	echo "Full deployment to $$TARGET: base + rclone mounts + apps + backups..."; \
	make deploy-base && \
	make deploy-rclone-mount && \
	make deploy-apps target=$$TARGET && \
	make deploy-backup-automation; \
	echo "Full deployment complete"; \
	echo ""; \
	echo "To enable optional cloud proxy: make deploy-cloud"

# --- Backup & Restore Targets ---

backup-now:
	@if [ -z "$(HOST)" ]; then \
		echo "ERROR: Must specify HOST, e.g., 'make backup-now HOST=rpi-home'"; \
		exit 1; \
	fi
	@echo "Starting backup on $(HOST) in background..."
	@ansible $(HOST) -i inventory/hosts.ini -m shell -a "sudo systemd-run --unit=homelab-backup-manual /opt/backups/backup_now.sh" --ask-vault-pass
	@echo "Backup started in background on $(HOST)"
	@echo "To monitor progress: make watch-backup HOST=$(HOST)"
	@echo "To check if backup is running: make backup-status HOST=$(HOST)"

backup-all:
	@echo "Running backup on all nodes..."
	@ansible all -i inventory/hosts.ini -m shell -a "sudo /opt/backups/backup_now.sh" --ask-vault-pass
	@echo "Backup complete on all nodes"

restore-latest:
	@if [ -z "$(HOST)" ]; then \
		echo "ERROR: Must specify HOST, e.g., 'make restore-latest HOST=rpi-friend'"; \
		exit 1; \
	fi
	@if [ -n "$(FROM)" ]; then \
		echo "WARNING: This will overwrite data on $(HOST) with $(FROM)'s backup!"; \
	else \
		echo "WARNING: This will overwrite data on $(HOST)!"; \
	fi
	@read -p "Type 'yes' to confirm: " confirm && [ "$$confirm" = "yes" ] || (echo "Cancelled" && exit 1)
	@ANSIBLE_HOST=$$(grep "^$(HOST)" inventory/hosts.ini | awk '{print $$2}' | cut -d'=' -f2); \
	if [ -z "$$ANSIBLE_HOST" ]; then \
		echo "ERROR: Could not resolve host $(HOST) in inventory/hosts.ini"; \
		exit 1; \
	fi; \
	if [ -n "$(FROM)" ]; then \
		echo "Restoring $(FROM)'s backup to $(HOST)..."; \
		ssh -t homelab@$$ANSIBLE_HOST "sudo /opt/backups/restore_latest.sh $(FROM)"; \
	else \
		echo "Restoring latest backup to $(HOST)..."; \
		ssh -t homelab@$$ANSIBLE_HOST "sudo /opt/backups/restore_latest.sh"; \
	fi

restore-test:
	@if [ -z "$(HOST)" ]; then \
		echo "ERROR: Must specify HOST, e.g., 'make restore-test HOST=rpi-friend'"; \
		exit 1; \
	fi
	@ANSIBLE_HOST=$$(grep "^$(HOST)" inventory/hosts.ini | awk '{print $$2}' | cut -d'=' -f2); \
	if [ -z "$$ANSIBLE_HOST" ]; then \
		echo "ERROR: Could not resolve host $(HOST) in inventory/hosts.ini"; \
		exit 1; \
	fi; \
	if [ -n "$(FROM)" ]; then \
		echo "Running non-destructive test restore on $(HOST) from $(FROM)'s backup..."; \
		ssh -t homelab@$$ANSIBLE_HOST "sudo /opt/backups/restore_latest.sh $(FROM) --test"; \
	else \
		echo "Running non-destructive test restore on $(HOST)..."; \
		ssh -t homelab@$$ANSIBLE_HOST "sudo /opt/backups/restore_latest.sh --test"; \
	fi

watch-backup:
	@if [ -z "$(HOST)" ]; then \
		echo "ERROR: Must specify HOST, e.g., 'make watch-backup HOST=rpi-home'"; \
		exit 1; \
	fi
	@echo "Watching backup log on $(HOST)... (Ctrl+C to exit)"
	@ANSIBLE_HOST=$$(grep "^$(HOST)" inventory/hosts.ini | awk '{print $$2}' | cut -d'=' -f2); \
	if [ -z "$$ANSIBLE_HOST" ]; then \
		echo "ERROR: Could not resolve host $(HOST) in inventory/hosts.ini"; \
		exit 1; \
	fi; \
	ssh homelab@$$ANSIBLE_HOST "tail -f /var/log/backup.log"

backup-status:
	@if [ -z "$(HOST)" ]; then \
		echo "ERROR: Must specify HOST, e.g., 'make backup-status HOST=rpi-home'"; \
		exit 1; \
	fi
	@echo "Checking backup status on $(HOST)..."
	@ansible $(HOST) -i inventory/hosts.ini -m shell -a "systemctl status homelab-backup-manual 2>/dev/null || pgrep -fa backup_now.sh || echo 'No backup currently running'" --ask-vault-pass

backup-log:
	@if [ -z "$(HOST)" ]; then \
		echo "ERROR: Must specify HOST, e.g., 'make backup-log HOST=rpi-home'"; \
		exit 1; \
	fi
	@echo "Recent backup log from $(HOST)..."
	@ansible $(HOST) -i inventory/hosts.ini -m shell -a "tail -n 50 /var/log/backup.log" --ask-vault-pass

# --- High Availability Targets ---

failover:
	@if [ ! -f .active-node ]; then \
		echo "ERROR: .active-node file not found"; \
		echo "Creating default with rpi-home as active..."; \
		echo "rpi-home" > .active-node; \
	fi
	@ACTIVE=$$(cat .active-node | tr -d '[:space:]'); \
	if [ "$$ACTIVE" = "rpi-home" ]; then \
		TARGET="rpi-friend"; \
	elif [ "$$ACTIVE" = "rpi-friend" ]; then \
		TARGET="rpi-home"; \
	else \
		echo "ERROR: Unknown active node '$$ACTIVE' in .active-node"; \
		echo "Must be 'rpi-home' or 'rpi-friend'"; \
		exit 1; \
	fi; \
	echo "Failover Operation"; \
	echo "===================="; \
	echo "From: $$ACTIVE (current active)"; \
	echo "To:   $$TARGET (new active)"; \
	if [ "$(SKIP_RESTORE)" = "true" ]; then \
		echo "Mode: SKIP_RESTORE=true (no data restore)"; \
	fi; \
	if [ "$(STOP_OLD_ACTIVE)" = "false" ]; then \
		echo "Mode: STOP_OLD_ACTIVE=false (old active stays running)"; \
	fi; \
	echo ""; \
	read -p "Continue with failover? (yes/no): " confirm && [ "$$confirm" = "yes" ] || (echo "Cancelled" && exit 1); \
	echo ""; \
	if [ "$(SKIP_RESTORE)" != "true" ]; then \
		echo "Step 1: Restoring $$ACTIVE's latest backup to $$TARGET..."; \
		ANSIBLE_HOST=$$(grep "^$$TARGET" inventory/hosts.ini | awk '{print $$2}' | cut -d'=' -f2); \
		ssh -t homelab@$$ANSIBLE_HOST "sudo /opt/backups/restore_latest.sh $$ACTIVE"; \
		echo ""; \
	else \
		echo "Step 1: Skipping restore (SKIP_RESTORE=true)"; \
		echo ""; \
	fi; \
	echo "Step 2: Enabling apps on $$TARGET..."; \
	ansible $$TARGET -i inventory/hosts.ini -m shell -a "grep -q 'APPS_ENABLED=true' /opt/stacks/env/local.env || echo 'APPS_ENABLED=true' >> /opt/stacks/env/local.env" --ask-vault-pass; \
	echo ""; \
	echo "Step 3: Deploying base stack to $$TARGET..."; \
	$(ANSIBLE_PLAYBOOK) ansible/site.yml --tags "base" --limit $$TARGET --ask-vault-pass; \
	echo ""; \
	echo "Step 4: Deploying applications to $$TARGET..."; \
	$(ANSIBLE_PLAYBOOK) ansible/site.yml --tags "apps" --limit $$TARGET --ask-vault-pass; \
	echo ""; \
	echo "Step 5: Updating active node tracker..."; \
	echo "$$TARGET" > .active-node; \
	echo ""; \
	if [ "$(STOP_OLD_ACTIVE)" != "false" ]; then \
		echo "Step 6: Stopping services on old active ($$ACTIVE)..."; \
		ANSIBLE_HOST=$$(grep "^$$ACTIVE" inventory/hosts.ini | awk '{print $$2}' | cut -d'=' -f2); \
		(ssh homelab@$$ANSIBLE_HOST "cd /opt/stacks/apps && docker compose down && cd /opt/stacks/base && docker compose down" && \
		echo "Services stopped on $$ACTIVE") || \
		echo "WARNING: Could not reach $$ACTIVE to stop services (node may be down)"; \
		echo ""; \
	else \
		echo "Step 6: Skipping shutdown of old active (STOP_OLD_ACTIVE=false)"; \
		echo ""; \
	fi; \
	echo "Failover complete. $$TARGET is now the active node."; \
	echo ""; \
	echo "Next steps:"; \
	echo "  - Test applications on $$TARGET"; \
	echo "  - Previous active ($$ACTIVE) is now standby"; \
	echo "  - Next 'make failover' will switch back to $$ACTIVE"

# --- Monitoring & Health Check Targets ---

check-health:
	@echo "Checking health of all services..."
	@ansible all -i inventory/hosts.ini -m shell -a "docker ps --format 'table {{.Names}}\t{{.Status}}'" --ask-vault-pass

show-resources:
	@echo "Resource usage on all nodes..."
	@ansible all -i inventory/hosts.ini -m shell -a "echo '=== CPU & Memory ===' && top -bn1 | head -n 5 && echo '' && echo '=== Disk Usage ===' && df -h /" --ask-vault-pass

show-logs:
	@if [ -z "$(HOST)" ]; then \
		echo "ERROR: Must specify HOST, e.g., 'make show-logs HOST=rpi-home'"; \
		exit 1; \
	fi
	@echo "Recent Docker logs from $(HOST)..."
	@ansible $(HOST) -i inventory/hosts.ini -m shell -a "cd /opt/stacks/apps && docker compose logs --tail=50" --ask-vault-pass

# --- Maintenance Targets ---

update-packages:
	@echo "Updating packages on all nodes..."
	@ansible all -i inventory/hosts.ini -b -m apt -a "update_cache=yes upgrade=dist" --ask-vault-pass

configure-network:
	@echo "Configuring network priority (Ethernet over WiFi) on RPi nodes..."
	$(ANSIBLE_PLAYBOOK) ansible/playbooks/configure-network-priority.yml -l rpi_nodes --ask-vault-pass
	@echo "Network configuration complete"

configure-dns:
	@echo "Configuring DNS with Tailscale + fallbacks on RPi nodes..."
	$(ANSIBLE_PLAYBOOK) ansible/playbooks/configure-dns.yml --limit rpi_nodes --ask-vault-pass
	@echo "DNS configuration complete"

enable-tailscale-dns:
	@echo "Enabling Tailscale DNS on RPi nodes..."
	$(ANSIBLE_PLAYBOOK) ansible/playbooks/enable-tailscale-dns.yml --limit rpi_nodes --ask-vault-pass
	@echo "Tailscale DNS enabled"

disable-tailscale-dns:
	@echo "Disabling Tailscale DNS on RPi nodes..."
	$(ANSIBLE_PLAYBOOK) ansible/playbooks/disable-tailscale-dns.yml --limit rpi_nodes --ask-vault-pass
	@echo "Tailscale DNS disabled"

reboot-nodes:
	@echo "WARNING: This will reboot ALL nodes!"
	@read -p "Type 'yes' to confirm: " confirm && [ "$$confirm" = "yes" ] || (echo "Cancelled" && exit 1)
	@echo "Rebooting all nodes..."
	@ansible all -i inventory/hosts.ini -b -m reboot -a "reboot_timeout=300" --ask-vault-pass

cleanup:
	@if [ -z "$(target)" ]; then \
		echo "ERROR: Must specify target"; \
		echo ""; \
		echo "Available cleanup targets:"; \
		echo "  make cleanup target=cloud-base    - Remove duplicate base stack from cloud-node"; \
		echo "  make cleanup target=docker         - Clean up unused Docker resources on all nodes"; \
		echo "  make cleanup target=rpi-docker     - Clean up Docker resources on RPi nodes only"; \
		echo "  make cleanup target=cloud-docker   - Clean up Docker resources on cloud-node only"; \
		exit 1; \
	fi
	@if [ "$(target)" = "cloud-base" ]; then \
		echo "Removing duplicate base stack from cloud-node..."; \
		ansible cloud-node -i inventory/hosts.ini -b -m shell -a "cd /opt/stacks/base && docker compose down -v || echo 'Base stack already removed'" --ask-vault-pass; \
		echo "Cloud-vm base stack removed"; \
	elif [ "$(target)" = "docker" ]; then \
		echo "Cleaning up Docker resources on all nodes..."; \
		ansible all -i inventory/hosts.ini -b -m shell -a "docker system prune -af" --ask-vault-pass; \
		echo "Docker cleanup complete on all nodes"; \
	elif [ "$(target)" = "rpi-docker" ]; then \
		echo "Cleaning up Docker resources on RPi nodes..."; \
		ansible rpi_nodes -i inventory/hosts.ini -b -m shell -a "docker system prune -af" --ask-vault-pass; \
		echo "Docker cleanup complete on RPi nodes"; \
	elif [ "$(target)" = "cloud-docker" ]; then \
		echo "Cleaning up Docker resources on cloud-node..."; \
		ansible cloud_nodes -i inventory/hosts.ini -b -m shell -a "docker system prune -af" --ask-vault-pass; \
		echo "Docker cleanup complete on cloud-node"; \
	else \
		echo "ERROR: Unknown cleanup target '$(target)'"; \
		echo "Valid targets: cloud-base, docker, rpi-docker, cloud-docker"; \
		exit 1; \
	fi

# --- Docker Image Management Targets ---

pull-images:
	@echo "Pre-pulling all Docker images to all nodes..."
	@echo "This avoids Docker Hub rate limits during deployment"
	@echo ""
	@echo "Pulling base images..."
	@ansible all -i inventory/hosts.ini -m shell -a "docker pull postgres:16-alpine" --ask-vault-pass
	@ansible all -i inventory/hosts.ini -m shell -a "docker pull redis:7-alpine" --ask-vault-pass
	@echo ""
	@echo "Pulling app images to primary/standby nodes..."
	@ansible rpi_nodes -i inventory/hosts.ini -m shell -a "docker pull ghcr.io/mealie-recipes/mealie:latest" --ask-vault-pass
	@ansible rpi_nodes -i inventory/hosts.ini -m shell -a "docker pull bellamy/wallos:latest" --ask-vault-pass
	@ansible rpi_nodes -i inventory/hosts.ini -m shell -a "docker pull frooodle/s-pdf:latest" --ask-vault-pass
	@ansible rpi_nodes -i inventory/hosts.ini -m shell -a "docker pull searxng/searxng:latest" --ask-vault-pass
	@ansible rpi_nodes -i inventory/hosts.ini -m shell -a "docker pull linuxserver/code-server:latest" --ask-vault-pass
	@ansible rpi_nodes -i inventory/hosts.ini -m shell -a "docker pull ghcr.io/open-webui/open-webui:main" --ask-vault-pass
	@ansible rpi_nodes -i inventory/hosts.ini -m shell -a "docker pull ghcr.io/advplyr/audiobookshelf" --ask-vault-pass
	@ansible rpi_nodes -i inventory/hosts.ini -m shell -a "docker pull n8nio/n8n:latest" --ask-vault-pass
	@echo ""
	@echo "Pulling cloud images to cloud VM..."
	@ansible cloud_nodes -i inventory/hosts.ini -m shell -a "docker pull traefik:v3.0" --ask-vault-pass
	@ansible cloud_nodes -i inventory/hosts.ini -m shell -a "docker pull postgres:15-alpine" --ask-vault-pass
	@ansible cloud_nodes -i inventory/hosts.ini -m shell -a "docker pull redis:alpine" --ask-vault-pass
	@ansible cloud_nodes -i inventory/hosts.ini -m shell -a "docker pull ghcr.io/goauthentik/server:latest" --ask-vault-pass
	@ansible cloud_nodes -i inventory/hosts.ini -m shell -a "docker pull louislam/uptime-kuma:latest" --ask-vault-pass
	@echo ""
	@echo "All images pre-pulled successfully"
	@echo "Future deployments will use cached images"

update-images:
	@echo "Updating all Docker images to latest versions..."
	@echo "WARNING: This will pull fresh images and restart services"
	@read -p "Type 'yes' to confirm: " confirm && [ "$$confirm" = "yes" ] || (echo "Cancelled" && exit 1)
	@echo ""
	@echo "Updating base stacks..."
	@ansible rpi_nodes -i inventory/hosts.ini -m shell -a "cd /opt/stacks/base && docker compose pull && docker compose up -d" --ask-vault-pass
	@echo ""
	@echo "Updating app stacks on primary node..."
	@ansible rpi-home -i inventory/hosts.ini -m shell -a "cd /opt/stacks/apps && docker compose pull && docker compose up -d" --ask-vault-pass
	@echo ""
	@echo "Updating cloud stack..."
	@ansible cloud_nodes -i inventory/hosts.ini -m shell -a "cd /opt/stacks/cloud && docker compose pull && docker compose up -d" --ask-vault-pass
	@echo ""
	@echo "All services updated and restarted"

