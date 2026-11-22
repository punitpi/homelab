# Homelab Infrastructure

> Infrastructure-as-code for self-hosted apps on Raspberry Pis, with encrypted off-site backups and a standby node ready to take over.

Ansible and Docker Compose deploy everything; nodes talk over a Tailscale mesh; rclone with crypt backs up to Backblaze B2. Terms used across the docs (node name, hostname, active node, backup set) are defined in [GLOSSARY.md](GLOSSARY.md).

## Nodes

| Node name    | Role                                  | Hostname         |
| ------------ | ------------------------------------- | ---------------- |
| `rpi-home`   | Primary: base stack and apps          | `merry`          |
| `rpi-friend` | Standby: base stack only              | `ub-friend-blue` |
| `cloud-node` | Optional public edge proxy (disabled) | n/a              |

A future server in Austria will take the heavy workloads (media, Nextcloud, Home Assistant).

```
 Your devices (Tailscale client)
          │  HTTPS *.igh.one via Traefik, or <hostname>:<port>
          ▼
 ┌──────────────── Tailscale mesh ─────────────────┐
 │                                                 │
 │  rpi-home (primary)        rpi-friend (standby) │
 │  ├─ base: Traefik,         ├─ base: Traefik,    │
 │  │  Postgres, Redis        │  Postgres, Redis   │
 │  └─ apps                   └─ apps on failover  │
 │                                                 │
 └──────────────────────┬──────────────────────────┘
                        │ nightly, encrypted (rclone crypt)
                        ▼
                  Backblaze B2
```

Nothing is exposed to the internet: no router port forwards, UFW default deny, SSH keys only. Postgres and Redis listen on `127.0.0.1`.

**Apps:** Mealie, Wallos, Sterling PDF, SearXNG, Code Server, Open WebUI, Audiobookshelf, n8n, Homarr, Paperless-ngx.

## Quick start

Full walkthrough: [docs/SETUP.md](docs/SETUP.md).

```bash
cp env/secrets.example.env env/secrets.env   # fill in every value
# edit inventory/hosts.ini, create the vault (docs/ANSIBLE-SUDO-SETUP.md)
make validate
make deploy-base
make deploy-apps target=rpi-home            # node needs APPS_ENABLED=true in its local.env
make deploy-backup-automation
make check-urls HOST=rpi-home
```

Every deploy prompts for the Ansible Vault password.

## Common commands

Run `make help` for the full list.

| Command                                   | Purpose                                            |
| ----------------------------------------- | -------------------------------------------------- |
| `make validate`                           | Check files, secrets, compose and playbook syntax  |
| `make deploy-all`                         | Base, rclone mounts, apps, backup automation       |
| `make deploy-base` / `make deploy-apps target=<node>` | Deploy one stack                       |
| `make check-health` / `make check-urls HOST=<node>` | Base containers / app endpoints          |
| `make backup-now HOST=<node>`             | Run a backup now                                   |
| `make restore-test HOST=<node>`           | Non-destructive restore into `/tmp` on the node    |
| `make failover`                           | Switch the apps to the other node                  |
| `make update-images`                      | Pull new images and recreate changed containers    |

## Documentation

**Getting started**
- [docs/SETUP.md](docs/SETUP.md): first-time setup, step by step
- [QUICKSTART.md](QUICKSTART.md): the short version
- [docs/SSH-SETUP.md](docs/SSH-SETUP.md), [docs/ANSIBLE-SUDO-SETUP.md](docs/ANSIBLE-SUDO-SETUP.md): access and the vault

**Running it**
- [docs/OPERATIONS.md](docs/OPERATIONS.md): daily tasks, backups, failover, maintenance
- [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md): common problems and fixes
- [docs/RCLONE-MOUNTS.md](docs/RCLONE-MOUNTS.md): cloud storage mounts for Audiobookshelf
- [docs/TESTING.md](docs/TESTING.md): test scenarios; partly out of date (restore sections describe restic and removed apps)

**Recovery**
- [docs/RECOVERY-LOG-2026-11-rpi-home.md](docs/RECOVERY-LOG-2026-11-rpi-home.md): the steps that worked when rebuilding `rpi-home` in November 2026
- [docs/DISASTER-RECOVERY.md](docs/DISASTER-RECOVERY.md): out of date (describes restic and removed apps); being rewritten

**Networking and TLS**
- [docs/TRAEFIK-HTTPS-SETUP.md](docs/TRAEFIK-HTTPS-SETUP.md), [docs/TAILSCALE-TLS-SETUP.md](docs/TAILSCALE-TLS-SETUP.md), [docs/DNS-CONFIGURATION.md](docs/DNS-CONFIGURATION.md)
- [docs/CLOUD-PROXY-SETUP.md](docs/CLOUD-PROXY-SETUP.md): optional public access through a cloud edge proxy

**Reference and planning**
- [SECURITY.md](SECURITY.md): security model
- [docs/DOCKER-PULL-STRATEGY.md](docs/DOCKER-PULL-STRATEGY.md), [docs/REGISTRY-AUTH.md](docs/REGISTRY-AUTH.md): image pulls and rate limits
- [docs/MIGRATION.md](docs/MIGRATION.md): plan for the Austria phase
- [CHANGELOG.md](CHANGELOG.md): operational changes and decisions
- [CONTRIBUTING.md](CONTRIBUTING.md)

## Repository layout

```
ansible/          site.yml and roles: common, compose-deploy, rclone-mount, backup-automation
  playbooks/      one-off playbooks (DNS, network priority)
inventory/        hosts.ini, group_vars (all.yml is vault-encrypted)
env/              common.env, local.env, secrets.env (not in git), rclone-mounts.env
stacks/           base, apps, cloud compose files; overrides/
scripts/          bootstrap, validate, backup, restore, health checks
docs/             guides (see above)
containers/       reference container configs from the old setup
```

## License

[MIT](LICENSE)
