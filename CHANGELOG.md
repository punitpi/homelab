# Changelog

A brief record of operational changes and infrastructure decisions.

---

## 16-04-2026

### Deleted audiobooks from B2 (migrated to Filen)
Verified all 961 files existed on Filen before deleting. Filen is now the sole copy.
```bash
rclone check b2-crypt:data/media/audiobooks/ filen-crypt:/audiobooks/ --one-way
rclone delete b2-crypt:data/media/audiobooks/
```

### Pre-cached Mahabharata Vol 2 Part 1 for fast download
Forced rclone to pull the file into local VFS cache before downloading in Audiobookshelf.
```bash
cat '/mnt/audiobooks/Other/Bibek Debroy - translator/The Mahabharata/The Mahabharata, Volume 2, Part 1/'* > /dev/null &
```

---

## 06-04-2026

### Removed Authentik SSO from base stack
Consuming ~1GB RAM, SSO was never configured. Removed all 4 containers, middleware labels from all app routes, and OIDC env vars from n8n and paperless.
```bash
docker stop authentik authentik-worker authentik-db authentik-redis
docker rm authentik authentik-worker authentik-db authentik-redis
make deploy-base && make deploy-apps target=rpi-home
```
- Files: `stacks/base/compose.yml`, `stacks/apps/compose.yml`, `stacks/base/traefik-config/middlewares.yml`

### Started apps stack (containers were in Created state)
All app containers were in Created state — never started after initial deploy. Ansible timeout expired during first-run image pulls (30-45 min). Fixed by running compose up directly on the node.
```bash
ssh homelab@ub-house-green "cd /opt/stacks/apps && docker compose up -d"
```

### Bumped Ansible deploy timeout to 3600s
First-run image pulls take 30-45 min on RPi. Previous 1800s async/timeout caused false failures.
- File: `ansible/roles/compose-deploy/tasks/main.yml`

### Diagnosed Tailscale not running locally
Services appeared down but base stack was healthy. Root cause: Tailscale stopped on local machine, so MagicDNS hostnames couldn't resolve.
```bash
sudo tailscale up
make check-health        # base stack status
make check-urls HOST=rpi-home  # app service status
```

### Fixed stale documentation
- SSH hostnames updated (`rpi-home` → `ub-house-green`, `rpi-friend` → `ub-friend-blue`)
- Replaced restic references with rclone (actual backup tool)
- Fixed container names (`postgres` → `postgres-base`, `redis` → `redis-base`)
- Removed freshrss/adguard references (not in current stack)
- Removed Authentik setup guide (replaced with tombstone note)
- Removed `.github/workflows/` (deploy workflow broken for Tailscale setup, not needed)

### Removed .github/workflows from git history
Accidentally committed GitHub Actions workflows. Rewrote history to remove them entirely.
```bash
git reset --soft <prev-commit>
git rm -r --cached .github/
git commit -m "..."
git push --force origin main
```
