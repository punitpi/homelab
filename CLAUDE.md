# CLAUDE.md

Guidance for Claude Code in this repo. Kept to navigation pointers and non-obvious gotchas: commands live in the Makefile (`make help`), details in `docs/`.

## What this is

Homelab infrastructure-as-code: Ansible + Docker Compose on Raspberry Pis, Tailscale mesh, rclone-with-crypt backups to Backblaze B2. Local-first (heavy work on cheap local hardware), databases collocated with their apps, cloud footprint minimal. Phase 1 is India (two RPis); phase 2 adds an Austria server for heavy workloads (media, Nextcloud, Home Assistant).

| Node | Role | Notes |
| --- | --- | --- |
| `rpi-home` | Primary, runs apps (`APPS_ENABLED=true` in its `local.env`) | Rebuilt Nov 2026. OS hostname and Tailscale name are now **`merry`**; the inventory name stays `rpi-home`. |
| `rpi-friend` | Standby, base stack only | Tailscale name `ub-friend-blue`. Promote with `make failover`. |
| `cloud-node` | Optional edge (Traefik, Uptime Kuma) | Commented out in `inventory/hosts.ini`. |
| Austria server | Future heavy workloads | Not built yet. |

## Where to look

- **Rebuilding or recovering a node, restoring from B2:** `docs/RECOVERY-LOG-2026-11-rpi-home.md` has the ordered steps that worked, plus every problem hit. `docs/DISASTER-RECOVERY.md` is **stale** (restic, FreshRSS, AdGuard): do not follow it.
- **First-time setup of a node:** `docs/SETUP.md` (the README is now an overview and docs map).
- **Rclone cloud mounts (audiobooks):** `docs/RCLONE-MOUNTS.md`
- **Backup and restore code:** `scripts/backup_now.sh`, `scripts/restore_latest.sh`, `ansible/roles/backup-automation/`
- **Cloud proxy:** `docs/CLOUD-PROXY-SETUP.md` · **DNS and TLS:** `docs/DNS-CONFIGURATION.md`, `docs/TAILSCALE-TLS-SETUP.md`, `docs/TRAEFIK-HTTPS-SETUP.md`
- **SSH and sudo setup:** `docs/SSH-SETUP.md`, `docs/ANSIBLE-SUDO-SETUP.md`
- **Operations, troubleshooting, testing:** `docs/OPERATIONS.md`, `docs/TROUBLESHOOTING.md`, `docs/TESTING.md`
- **Security model:** `SECURITY.md`
- **Planned reliability work:** GitHub issue #1 (backup, restore and rebuild) and its sub-issues.

## How it fits together

- **Stacks:** `stacks/base` (Traefik, Postgres, Redis) goes to every RPi node; `stacks/apps` (Mealie, Wallos, Sterling PDF, SearXNG, Code Server, Open WebUI, Audiobookshelf, n8n, Homarr, Paperless-ngx) only to nodes whose `/opt/stacks/env/local.env` contains `APPS_ENABLED=true` (`make failover` writes it; there is no inventory variable for this); `stacks/cloud` to the cloud node.
- **Inventory vars:** `inventory/group_vars/rpi_nodes.yml` holds only variables a role reads. The `[primary]`/`[standby]` groups in `hosts.ini` are labels only; which node is live is tracked by `.active-node`. Terms are defined in `GLOSSARY.md`.
- **Ansible roles** (`ansible/site.yml`, tags `base`, `rclone-mount`, `apps`, `backup-automation`): common, compose-deploy, rclone-mount, backup-automation. `make deploy-all` runs base, rclone mounts, apps, backup automation, in that order, using `.active-node` (or `target=`).
- **Env files:** `env/common.env`, then `env/secrets.env` (not in git), then `env/local.env`. The node's `secrets.env` is written from `vault_stack_secrets` in the vault when that is set, else copied from the local `env/secrets.env` (`docs/ANSIBLE-SUDO-SETUP.md`). Personal values (`ACME_EMAIL`) belong in secrets, not `common.env`: the repo is public. Ansible merges them into `/opt/stacks/<stack>/.env` on each node, so containers restart cleanly after a reboot without a redeploy. Never read `env/secrets.env`; ask the user to run any check on it.
- **Network and security:** Tailscale only, no router port forwards, UFW default deny, SSH keys only, sudo password in Ansible Vault (every deploy prompts for the vault password). Apps bind `0.0.0.0` and are reached over Tailscale or Traefik (`*.igh.one`); Postgres and Redis bind `127.0.0.1`.
- **Backups:** rclone crypt remote `b2-crypt`, stored under `rpi-homelab-backup/<inventory node name>/<timestamp>`. The daily cron is hardcoded to 03:00 in the backup-automation role.

## Gotchas

- **Names differ:** inventory `rpi-home` vs OS/Tailscale `merry`; the old `ub-house-green` device is dead. Backups are keyed by the **inventory** name (`NODE_NAME`), not the hostname. Tailscale must be running on the Mac for MagicDNS names to resolve.
- **`restore_latest.sh` overwrites `/opt/stacks`**, including compose files and `.env`, with the backup's old copies. Run `make deploy-base` again after a restore. (This downgraded Traefik and dropped a DB password in Nov 2026.)
- **Postgres init runs only on an empty data directory.** After a restore, app roles and databases (Paperless) must be created by hand until issue #3 lands. Never create a role from an unset or empty password variable.
- **Traefik must be v3.6 or newer with Docker Engine 29+;** the compose file pins `traefik:v3.6`. Symptom of an old one: every hostname returns 404 and the log says `client version 1.24 is too old`.
- **`rclone.conf` (B2 and crypt secrets) is not managed by Ansible.** It lives at `/home/homelab/.config/rclone/rclone.conf` on each node; copy it from another node when rebuilding.
- **Retention keeps the last 7 backups by count,** so a fresh empty backup after a rebuild starts deleting the real ones (issue #7 replaces this). Archive real backups before running `make backup-now` on a rebuilt node.
- **Most app images are unpinned** (`:latest`, `:main`); `make update-images` can jump major versions.
- **Health checks:** `make check-health` shows base containers only; `make check-urls HOST=rpi-home` checks the apps, retrying while they start.
- **First `deploy-apps` takes 30-45 minutes** (image pulls, Ansible async timeout 3600 s). Containers in `Created` state never started: run `cd /opt/stacks/apps && docker compose up -d` on the node.
- **Multi-command over ssh:** put `&&` on the same line.
- **Authentik was removed in April 2026.** Do not re-add `authentik@file` labels or OIDC variables unless SSO is being set up on purpose. The `authentik-*` Makefile targets are stale.

## Agent skills

### Issue tracker

Issues are tracked in GitHub Issues for `punitpi/homelab` (via the `gh` CLI). See `docs/agents/issue-tracker.md`.

### Triage labels

Default five-label vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `GLOSSARY.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
