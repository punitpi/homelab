# Recovery log: rpi-home rebuilt as `merry` (22-23 Nov 2026)

What happened when the primary node died, the exact order of steps that brought it back, every problem hit on the way, and what is still open. Written from the recovery session itself. Where something was not verified, it says so.

Naming used throughout:

| Thing | Value |
| --- | --- |
| Inventory node name | `rpi-home` (keep this; backups are keyed by it) |
| New OS hostname / Tailscale name | `merry` |
| Tailscale IP | `100.77.112.37` |
| Old Tailscale name | `ub-house-green` (dead device) |
| Standby node | `rpi-friend` (`ub-friend-blue`), untouched |
| Service user | `homelab` |

## 1. Summary

- rpi-home died. A fresh Ubuntu was installed on it and the machine was named `merry`.
- It was rebuilt using `scripts/bootstrap.sh`, Tailscale, Ansible (`deploy-base`, `deploy-apps`) and a restore from B2 (rclone with a crypt remote).
- **The restored backup was from 3 Nov 2025.** Backups on both nodes silently stopped that day and nobody noticed for a year. Anything created after that (Homarr dashboard, Paperless data) was not in B2.
- The restore itself caused two follow-on breakages (stale stack files overwrote the deployed ones). Both were fixed.
- End state: all 10 app services respond, the dashboard loads over HTTPS, 9 Paperless documents were re-imported from an older B2 copy, and the real 2025 backups were archived so retention cannot delete them.

## 2. The order that worked (use this as the runbook)

Run from the Mac in the repo unless a step says "on the Pi". Tailscale must be running on the Mac (`sudo tailscale up`).

1. **Put your SSH key on the fresh OS** (`ssh-copy-id -i ~/.ssh/id_ed25519.pub <os-user>@<lan-ip>`). `<os-user>` is whatever user the Ubuntu installer created. It is not the hostname.
2. **Run bootstrap on the Pi.**
   ```bash
   scp scripts/bootstrap.sh <os-user>@<lan-ip>:/tmp/
   ssh <os-user>@<lan-ip>
   sudo bash /tmp/bootstrap.sh Asia/Kolkata <os-user>
   ```
   The last argument is the user whose `authorized_keys` get copied to `homelab`. When it asks for the `homelab` password, **use the same password that is in the Ansible vault** (`ansible_sudo_pass` in the group vars), otherwise Ansible sudo fails later. Bootstrap hardens SSH (no root login, no passwords) only if the key copy worked.
3. **Join Tailscale (on the Pi).**
   ```bash
   sudo tailscale up --ssh --accept-routes --authkey=<key from the Tailscale admin console>
   sudo tailscale set --accept-dns=false
   tailscale ip -4
   ```
4. **Point the inventory at the new name.** In `inventory/hosts.ini` set `rpi-home ansible_host=merry`. Keep the node name `rpi-home`.
5. **Accept the host key and verify hardening.**
   ```bash
   ssh homelab@merry "hostname; grep -E '^(PermitRootLogin|PasswordAuthentication)' /etc/ssh/sshd_config"
   ```
   Expect a key login, `merry`, and both sshd settings `no`.
6. **Recover the rclone config.** It is not managed by Ansible. It was copied from the other node without printing it:
   ```bash
   ssh homelab@ub-friend-blue "cat ~/.config/rclone/rclone.conf" | ssh homelab@merry "mkdir -p ~/.config/rclone && umask 077 && cat > ~/.config/rclone/rclone.conf"
   ssh homelab@merry "rclone lsd b2-crypt:rpi-homelab-backup/"
   ```
   Expect folders `rpi-home` and `rpi-friend`. The `b2-crypt` remote points at the `back:` remote's bucket.
7. **Validate and deploy base.**
   ```bash
   make validate
   make deploy-base
   ```
8. **Check what the backup actually contains before restoring.**
   ```bash
   ssh homelab@merry "rclone lsd b2-crypt:rpi-homelab-backup/rpi-home"
   make restore-test HOST=rpi-home
   ```
   This is where the year-old state should have been noticed. Look at the newest folder date.
9. **Restore.**
   ```bash
   ssh homelab@merry "cd /opt/stacks/base && docker compose down"
   make restore-latest HOST=rpi-home        # destructive, type yes
   ```
   **Warning:** this overwrites `/opt/stacks` (compose and `.env` files) with the backup's old versions. See problems 3 and 4.
10. **Re-run deploy-base after the restore** to put the repo's compose and env files back, then deploy apps and backup automation:
    ```bash
    make deploy-base
    make deploy-apps target=rpi-home      # 30-45 min first run (image pulls)
    make deploy-backup-automation
    make check-urls HOST=rpi-home
    make backup-now HOST=rpi-home
    ```
    In this recovery `deploy-base` was only re-run later, as part of the update step, which is when Traefik was fixed.

## 3. Problems hit and how each was fixed

1. **Restore was a year old.** Newest rpi-home backup was `2025-11-03_13-18-36`; rpi-friend's last was `2025-11-03_22-37-36`. Cause of the backup stop is **unknown and unverified** (the old node's `/var/log/backup.log` was not available). Effects: Homarr started empty, Paperless had no data.
2. **Services "DOWN" right after deploy.** Mealie, Sterling PDF and Open WebUI were just slow to start on the Pi (load average above 5). They were fine a few minutes later.
3. **Paperless crash loop: `Role "paperless" does not exist`.** Postgres only runs its init script when the data directory is empty. The restore put a cluster there first, so the role and database were never created. Fix: created the role and database manually in `postgres-base`.
4. **Paperless still failing: password authentication failed.** The base `.env` had been overwritten by the 2025 restore and lacked `PAPERLESS_DB_PASSWORD`, so the Postgres container saw an empty value and the role was created with an empty password. Fix: `ALTER ROLE paperless PASSWORD` using the value from the Paperless container's own environment, piped without printing it, then restarted Paperless. First-run migrations take a couple of minutes on the Pi.
5. **`https://dashboard.igh.one` returned 404 for every hostname.** The restore had also put back the Oct 2025 base compose, which pins `traefik:v3.0` (running 3.0.4). Docker Engine 29.10 on the fresh Ubuntu has a minimum API of 1.40; Traefik 3.0 negotiated 1.24, so its Docker provider failed with `client version 1.24 is too old` and it loaded no routes. DNS and ports were fine. Fix: `make deploy-base` redeployed the repo's pinned `traefik:v3.6`, now running 3.6.25. Known issue reported on the [Traefik forum](https://community.traefik.io/t/traefik-stops-working-it-uses-old-api-version-1-24/29019) and the [Docker forum](https://forums.docker.com/t/docker-29-increased-minimum-api-version-breaks-traefik-reverse-proxy/150384).
5a. **DNS.** The `igh.one` records were changed to the new Tailscale IP `100.77.112.37` by hand. These names only work with Tailscale running.
6. **Retention would have deleted the real backups.** `backup_now.sh` keeps the last 7 backups by count. After the rebuild rpi-home had 6 real backups plus fresh ones, so each new run deletes the oldest real one. Fix: copied the six 2025 backups to `rpi-homelab-backup/_archive-2025/rpi-home/` in B2 (server-side `rclone copy`). The first loop stopped after one backup and was re-run to completion (`ALL-DONE`). Verified afterwards: five of the six archive copies match the sizes of the originals still in place. The `2025-10-29` original had already been pruned by the next backup, so its archive copy (42.0 MiB) is now the only copy and could not be compared.
7. **Paperless documents.** B2 holds an older Paperless media folder (`docs/paperless/media`, 9 original documents, 62 MB, from the Unraid era) with no database. Paperless cannot adopt it directly. Fix: copied the 9 originals into the Paperless consume folder and let it OCR and import them as new documents (about 2 minutes each on the Pi). Old tags and correspondents are not recoverable. At the last check 8 of 9 had been consumed and 1 was still queued.
8. **Stray file in the repo.** `homelab@192.168.8.127`, an untracked copy of `bootstrap.sh` (an `scp` without a trailing colon). Deleted.

## 4. Updates applied

`make deploy-base`, `make backup-now HOST=rpi-home`, `make update-packages`, `make update-images HOST=rpi-home` were run. No reboot was required. Note: `update-images` pulled new images but its output shows the app containers as "Running", meaning they were not recreated, so newer images are not live until `docker compose up -d` is run in `/opt/stacks/apps`. Postgres and Traefik were recreated. The app images are mostly unpinned (`:latest`, `:main`), so a recreate can bring major version jumps.

## 5. Where things stand

Verified during the session:
- All 10 services respond (n8n and Homarr answer with redirects or 404 on some paths, which is normal). Mealie, Wallos, Sterling PDF, SearXNG, Code Server, Open WebUI, Audiobookshelf, n8n and Paperless containers are up; Paperless is healthy.
- `https://dashboard.igh.one` returns 307 (login redirect) from the Mac.
- SSH: key-only, root login off.
- B2: `_archive-2025` holds all six 2025 backups.

Not verified:
- Whether the backups made on merry after the rebuild completed successfully (`2026-11-23_02-07-59` and `2026-11-23_02-34-53` exist in B2; their contents were not inspected).
- That the daily backup cron is installed and running on merry, and why backups stopped in Nov 2025.
- That the old `ub-house-green` device was removed from the Tailscale admin console.
- The state of rpi-friend (it was not touched; it may also run Traefik 3.0 and break the same way on Docker 29).
- That app data restored from the 2025 backup (Mealie, Audiobookshelf, etc.) is complete.

## 6. Still to do

- [ ] Set up Homarr: first visit to `https://dashboard.igh.one` runs the onboarding wizard (create the admin user), then add the apps. Its database was created fresh.
- [ ] Create the Paperless admin user if it does not exist, and confirm the 9 documents imported.
- [ ] Confirm the backup cron and a successful run on merry (`/var/log/backup.log`), and before the next scheduled backup make sure retention cannot prune anything else you need.
- [ ] Remove the dead `ub-house-green` device in Tailscale.
- [ ] Run `make deploy-base` on rpi-friend (it runs base too) and check its Traefik and backups.
- [ ] If the old Pi's disk is readable, copy its `/srv/appdata`, `/opt/stacks/env` and `/var/log/backup.log`; it is the only place newer data can exist.
- [ ] Delete `_archive-2025` from B2 once a verified newer backup exists.
- [ ] Decide on restarting app containers onto the pulled images.

## 7. Lessons (tracked in the spec)

The defects above are scoped in GitHub issue #1 (monitored backups, safe retention, a restore that does not overwrite deployed stack files, idempotent DB role creation, a single rebuild runbook). `docs/DISASTER-RECOVERY.md` is stale (restic, FreshRSS, AdGuard) and should not be followed; use section 2 here until #1 replaces it.
