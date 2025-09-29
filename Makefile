# Makefile for managing the homelab stacks

# Default target
all: help

# Variables
ANSIBLE_PLAYBOOK=ansible-playbook -i inventory/hosts.ini

.PHONY: help validate deploy-base deploy-apps deploy-backup-automation backup-now restore-latest restore-test promote-friend

help:
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  validate                 - Validate the homelab setup (files, syntax, secrets)."
	@echo "  deploy-base              - Deploy the base stack (Tailscale, DBs, etc.) to all nodes."
	@echo "  deploy-apps              - Deploy the application stack to nodes where APPS_ENABLED=true."
	@echo "  deploy-backup-automation - Deploy automated backup cron jobs to all nodes."
	@echo "  backup-now               - Trigger a manual backup on a specified host."
	@echo "  restore-latest           - (DESTRUCTIVE) Restore the latest backup to a specified host."
	@echo "  restore-test             - (NON-DESTRUCTIVE) Run a test restore to temp directory on a host."
	@echo "  promote-friend           - Promote rpi-friend to become the primary app host."
	@echo ""
	@echo "Examples:"
	@echo "  make validate"
	@echo "  make deploy-base"
	@echo "  make deploy-apps target=rpi-home"
	@echo "  make deploy-backup-automation"
	@echo "  make backup-now HOST=rpi-home"
	@echo "  make restore-test HOST=rpi-friend"


# --- Validation Target ---

validate:
	@echo "Running homelab setup validation..."
	./scripts/validate_setup.sh

# --- Deployment Targets ---

deploy-base:
	$(ANSIBLE_PLAYBOOK) ansible/site.yml --tags "base"

deploy-apps:
	@if [ -z "$(target)" ]; then \
		echo "ERROR: Must specify target host, e.g., 'make deploy-apps target=rpi-home'"; \
		exit 1; \
	fi
	$(ANSIBLE_PLAYBOOK) ansible/site.yml --tags "apps" --limit $(target)

# --- Script Execution Targets ---

backup-now:
	@if [ -z "$(HOST)" ]; then \
		echo "ERROR: Must specify HOST, e.g., 'make backup-now HOST=rpi-home'"; \
		exit 1; \
	fi
	@echo "Running backup on $(HOST)..."
	ssh $(HOST) "sudo /opt/backups/backup_now.sh"

restore-latest:
	@if [ -z "$(HOST)" ]; then \
		echo "ERROR: Must specify HOST, e.g., 'make restore-latest HOST=rpi-friend'"; \
		exit 1; \
	fi
	@echo "Restoring latest backup to $(HOST)..."
	ssh $(HOST) "sudo /opt/backups/restore_latest.sh"

restore-test:
	@if [ -z "$(HOST)" ]; then \
		echo "ERROR: Must specify HOST, e.g., 'make restore-test HOST=rpi-friend'"; \
		exit 1; \
	fi
	@echo "Running NON-DESTRUCTIVE test restore on $(HOST)..."
	ssh $(HOST) "sudo /opt/backups/restore_latest.sh --test"

# --- Backup Automation Deployment ---

deploy-backup-automation:
	$(ANSIBLE_PLAYBOOK) ansible/site.yml --tags "backup-automation"

promote-friend:
	@echo "Promoting rpi-friend to primary app host..."
	# 1. Update local.env on rpi-friend to enable apps
	ssh rpi-friend "echo 'APPS_ENABLED=true' > /opt/stacks/env/local.env"
	# 2. Run the app deployment playbook against rpi-friend
	$(ANSIBLE_PLAYBOOK) ansible/site.yml --tags "apps" --limit rpi-friend
	@echo "Promotion complete. rpi-friend is now running the application stack."

