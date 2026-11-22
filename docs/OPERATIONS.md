# Operations Guide

Day-to-day operations and maintenance. Run `make help` for every command. In `ssh` examples, `merry` is the hostname of node `rpi-home` and `ub-friend-blue` is the hostname of node `rpi-friend` (see [GLOSSARY.md](../GLOSSARY.md)).

---

## Table of Contents

1. [Daily Operations](#daily-operations)
2. [Weekly Tasks](#weekly-tasks)
3. [Monthly Tasks](#monthly-tasks)
4. [Backup Management](#backup-management)
5. [Failover](#failover)
6. [Service Management](#service-management)
7. [Monitoring](#monitoring)
8. [Maintenance](#maintenance)
9. [Troubleshooting](#troubleshooting)

---

## Daily Operations

### Checking System Health

```bash
# Check base stack containers (traefik, postgres, redis)
make check-health

# Check app service URLs (use this to verify apps are actually responding)
make check-urls HOST=rpi-home

# Or manually check containers on the node
ssh homelab@merry "docker ps --format 'table {{.Names}}\t{{.Status}}'"
```

### Viewing Logs

```bash
# View logs from specific service
ssh homelab@merry "docker logs -f mealie"

# View all app logs
ssh homelab@merry "cd /opt/stacks/apps && docker compose logs -f"

# View backup logs
ssh homelab@merry "tail -f /var/log/backup.log"

# View system logs
ssh homelab@merry "journalctl -f"
```

### Accessing Services

All services are accessed via Tailscale (MagicDNS hostnames or direct ports):

```bash
# rpi-home Tailscale hostname: merry
# Access services directly by port:
# Mealie:         http://merry:9925
# Wallos:         http://merry:8282
# SterlingPDF:    http://merry:8082
# SearXNG:        http://merry:8083
# VS Code:        http://merry:8443
# OpenWebUI:      http://merry:8084
# Audiobookshelf: http://merry:13378
# n8n:            http://merry:5678
# Homarr:         http://merry:7575
# Paperless:      http://merry:8000
```

---

## Weekly Tasks

### Check Backup Status

```bash
# View recent backup logs
ssh homelab@merry "tail -n 100 /var/log/backup.log"

# List recent snapshots in B2
ssh homelab@merry "rclone lsd b2-crypt:rpi-homelab-backup/"

# Check B2 storage usage
ssh homelab@merry "rclone size b2-crypt:rpi-homelab-backup/"
```

### Review Disk Space

```bash
# Check disk usage on all nodes
ansible all -i inventory/hosts.ini -m shell -a "df -h /"

# Check Docker disk usage
ansible all -i inventory/hosts.ini -m shell -a "docker system df"

# Clean up if needed (removes unused images, containers, networks)
ssh homelab@merry "docker system prune -a -f"
```

### Update System Packages

```bash
# Update all nodes
ansible all -i inventory/hosts.ini -b -m apt -a "update_cache=yes upgrade=dist"

# Reboot if kernel was updated
ansible all -i inventory/hosts.ini -b -m reboot -a "reboot_timeout=300"
```

---

## Monthly Tasks

### Backup Integrity Test

** Critical: Do this monthly!**

```bash
# Run non-destructive restore test (restores to /tmp/rclone_restore_test/)
make restore-test HOST=rpi-friend

# Verify restored data
ssh homelab@ub-friend-blue "ls -lh /tmp/rclone_restore_test/"

# Clean up test data
ssh homelab@ub-friend-blue "rm -rf /tmp/rclone_restore_test/"
```

### Security Updates

```bash
# Check for security updates
ansible all -i inventory/hosts.ini -m shell -a "apt list --upgradable | grep -i security"

# Apply security updates
ansible all -i inventory/hosts.ini -b -m apt -a "upgrade=yes update_cache=yes"

# Check if reboot required
ansible all -i inventory/hosts.ini -m shell -a "[ -f /var/run/reboot-required ] && echo 'Reboot Required' || echo 'No Reboot Needed'"
```

### Review Logs for Issues

```bash
# Check for Docker errors
ssh homelab@merry "journalctl -u docker --since '1 month ago' | grep -i error"

# Check for failed systemd services
ssh homelab@merry "systemctl --failed"

# Check for SSH login attempts
ssh homelab@merry "grep 'Failed password' /var/log/auth.log | tail -n 20"
```

### Backup Retention Management

```bash
# List backup contents
ssh homelab@merry "rclone lsd b2-crypt:rpi-homelab-backup/"

# Check storage usage
ssh homelab@merry "rclone size b2-crypt:rpi-homelab-backup/"
```

---

## Backup Management

### Manual Backup

```bash
# Backup specific host
make backup-now HOST=rpi-home

# Backup all nodes
make backup-all
```

### View Backup History

```bash
# List backup directories in B2
ssh homelab@merry "rclone lsd b2-crypt:rpi-homelab-backup/"
```

### Restore Operations

#### Non-Destructive Test Restore

```bash
# Test restore to /tmp/rclone_restore_test/
make restore-test HOST=rpi-friend

# Verify data
ssh homelab@ub-friend-blue "ls -lh /tmp/rclone_restore_test/"
```

#### Destructive Full Restore

** WARNING: This will overwrite existing data!**

```bash
# Stop all services first
ssh homelab@merry "cd /opt/stacks/apps && docker compose down"
ssh homelab@merry "cd /opt/stacks/base && docker compose down"

# Restore from backup
make restore-latest HOST=rpi-home

# Restart services
ssh homelab@merry "cd /opt/stacks/base && docker compose up -d"
ssh homelab@merry "cd /opt/stacks/apps && docker compose up -d"

# Verify services are running
ssh homelab@merry "docker ps"
```

#### Selective Restore

```bash
# Restore specific app data using rclone
ssh homelab@merry
rclone copy b2-crypt:rpi-homelab-backup/appdata/mealie /tmp/restore/mealie
sudo cp -a /tmp/restore/mealie /srv/appdata/
```

### Backup Troubleshooting

#### Backup Fails to Connect

```bash
# Test B2 credentials via rclone
ssh homelab@merry "rclone lsd b2-crypt:rpi-homelab-backup/"

# Check backup logs
ssh homelab@merry "tail -n 100 /var/log/backup.log"
```

#### Backup Takes Too Long

```bash
# Check backup stats
ssh homelab@merry "tail -n 200 /var/log/backup.log"

# Exclude large directories (edit backup script)
ssh homelab@merry
sudo nano /opt/backups/backup_now.sh
# Add: --exclude="path/to/large/dir"
```

---

## Failover

`make failover` makes the standby the active node. The active node is tracked locally in `.active-node` (`rpi-home` or `rpi-friend`); failover always switches to the other node, so running it again switches back.

What it does, in order:

1. Restores the active node's latest backup set onto the other node (unless `SKIP_RESTORE=true`)
2. Writes `APPS_ENABLED=true` to the new node's `/opt/stacks/env/local.env`
3. Deploys the base stack, then the apps stack, to the new node
4. Updates `.active-node`
5. Stops the stacks on the old node (unless `STOP_OLD_ACTIVE=false`)

| Situation | Command |
| --- | --- |
| Planned switch with the latest data | `make failover` |
| Planned switch, data already in sync (much faster) | `make failover SKIP_RESTORE=true` |
| Old node is down or unreachable | `make failover STOP_OLD_ACTIVE=false` |
| Testing, keep both nodes running | `make failover SKIP_RESTORE=true STOP_OLD_ACTIVE=false` |

If the automatic failover fails part-way, the same steps by hand:

```bash
make restore-latest HOST=rpi-friend FROM=rpi-home
ssh homelab@ub-friend-blue "grep -q '^APPS_ENABLED=true' /opt/stacks/env/local.env || echo 'APPS_ENABLED=true' >> /opt/stacks/env/local.env"
make deploy-base
make deploy-apps target=rpi-friend
echo "rpi-friend" > .active-node
```

The restore overwrites the deployed compose and `.env` files with the backup's copies; run `make deploy-base` again afterwards (see the gotchas in `CLAUDE.md`).

---

## Service Management

### Starting/Stopping Services

```bash
# Stop all apps (for maintenance)
ssh homelab@merry "cd /opt/stacks/apps && docker compose down"

# Start apps
ssh homelab@merry "cd /opt/stacks/apps && docker compose up -d"

# Restart specific service
ssh homelab@merry "docker restart mealie"

# Stop specific service
ssh homelab@merry "cd /opt/stacks/apps && docker compose stop mealie"
```

### Updating Services

```bash
# Update all services on primary node
ssh homelab@merry "cd /opt/stacks/apps && docker compose pull"
ssh homelab@merry "cd /opt/stacks/apps && docker compose up -d"

# Update specific service
ssh homelab@merry "cd /opt/stacks/apps && docker compose pull mealie"
ssh homelab@merry "cd /opt/stacks/apps && docker compose up -d mealie"

# Or use Ansible (recommended - ensures config consistency)
make deploy-apps target=rpi-home
```

### Adding New Services

1. Edit `stacks/apps/compose.yml` on management machine
2. Add service configuration
3. Update `env/secrets.env` if needed
4. Deploy using Ansible:

```bash
make deploy-apps target=rpi-home
```

### Removing Services

1. Remove service from `stacks/apps/compose.yml`
2. Deploy changes:

```bash
make deploy-apps target=rpi-home
```

3. Clean up volumes (optional):

```bash
ssh homelab@merry "docker volume rm apps_<service>_data"
```

---

## Monitoring

### Container Health

```bash
# Check all containers
ssh homelab@merry "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"

# Check resource usage
ssh homelab@merry "docker stats --no-stream"

# Check for unhealthy containers
ssh homelab@merry "docker ps --filter 'health=unhealthy'"
```

### System Resources

```bash
# CPU and memory usage
ssh homelab@merry "top -bn1 | head -n 20"

# Disk usage
ssh homelab@merry "df -h"

# Network connections
ssh homelab@merry "netstat -tlnp"

# Temperature (Raspberry Pi)
ssh homelab@merry "vcgencmd measure_temp"
```

### Tailscale Status

```bash
# Check Tailscale connection
ssh homelab@merry "tailscale status"

# Check Tailscale IP
ssh homelab@merry "tailscale ip -4"

# Ping other nodes via Tailscale
ssh homelab@merry "tailscale ping rpi-friend"
```

### Database Health

```bash
# Check PostgreSQL
ssh homelab@merry "docker exec postgres-base psql -U postgres -c '\l'"

# Check database sizes
ssh homelab@merry "docker exec postgres-base psql -U postgres -c \"SELECT pg_database.datname, pg_size_pretty(pg_database_size(pg_database.datname)) AS size FROM pg_database;\""

# Check Redis
ssh homelab@merry "docker exec redis-base redis-cli PING"
ssh homelab@merry "docker exec redis-base redis-cli INFO memory"
```

---

## Maintenance

### Docker Cleanup

```bash
# Remove unused containers, networks, images
ssh homelab@merry "docker system prune -a -f"

# Remove unused volumes ( be careful!)
ssh homelab@merry "docker volume prune -f"

# View disk space before and after
ssh homelab@merry "docker system df"
```

### Log Rotation

```bash
# Check log sizes
ssh homelab@merry "du -sh /var/lib/docker/containers/*/*-json.log"

# Rotate Docker logs (configure in daemon.json)
ssh homelab@merry "sudo nano /etc/docker/daemon.json"
# Add:
# {
#   "log-driver": "json-file",
#   "log-opts": {
#     "max-size": "10m",
#     "max-file": "3"
#   }
# }

# Restart Docker daemon
ssh homelab@merry "sudo systemctl restart docker"
```

### Database Maintenance

```bash
# Vacuum PostgreSQL databases
ssh homelab@merry "docker exec postgres-base psql -U postgres -c 'VACUUM ANALYZE;'"

# Optimize Redis memory
ssh homelab@merry "docker exec redis-base redis-cli BGREWRITEAOF"
```

### Security Audits

```bash
# Check for outdated Docker images
ssh homelab@merry "docker images --format 'table {{.Repository}}\t{{.Tag}}\t{{.CreatedAt}}'"

# Update Docker daemon
ssh homelab@merry "sudo apt update && sudo apt install docker-ce docker-ce-cli"

# Check SSH security
ssh homelab@merry "sudo grep -E '(PermitRootLogin|PasswordAuthentication)' /etc/ssh/sshd_config"

# Review UFW rules
ssh homelab@merry "sudo ufw status verbose"
```

---

## Troubleshooting

### Service Won't Start

```bash
# Check logs
ssh homelab@merry "docker logs <service-name>"

# Check configuration
ssh homelab@merry "cd /opt/stacks/apps && docker compose config"

# Verify environment variables
ssh homelab@merry "docker exec <service-name> env"

# Check port conflicts
ssh homelab@merry "netstat -tlnp | grep <port>"
```

### Database Connection Issues

```bash
# Check if database is running
ssh homelab@merry "docker ps | grep postgres"

# Test database connection
ssh homelab@merry "docker exec postgres-base psql -U postgres -c 'SELECT 1;'"

# Check database logs
ssh homelab@merry "docker logs postgres-base"

# Restart database
ssh homelab@merry "docker restart postgres-base"
```

### Network Issues

```bash
# Check Tailscale connectivity
ssh homelab@merry "tailscale status"

# Restart Tailscale
ssh homelab@merry "sudo systemctl restart tailscaled"

# Check Docker network
ssh homelab@merry "docker network inspect apps_default"

# Check firewall
ssh homelab@merry "sudo ufw status"
```

### Disk Space Issues

```bash
# Find large files
ssh homelab@merry "du -h / | sort -rh | head -n 20"

# Clean Docker
ssh homelab@merry "docker system prune -a --volumes -f"

# Clean apt cache
ssh homelab@merry "sudo apt clean"

# Clean journal logs
ssh homelab@merry "sudo journalctl --vacuum-time=7d"
```

### Performance Issues

```bash
# Check system load
ssh homelab@merry "uptime"

# Check memory usage
ssh homelab@merry "free -h"

# Check disk I/O
ssh homelab@merry "iostat -x 1 5"

# Check for OOM kills
ssh homelab@merry "dmesg | grep -i 'killed process'"

# Restart services to clear memory
ssh homelab@merry "cd /opt/stacks/apps && docker compose restart"
```

---

## Emergency Procedures

### Complete System Failure

See [DISASTER-RECOVERY.md](DISASTER-RECOVERY.md) for full procedures.

Quick recovery:

```bash
# 1. Deploy base services to standby node
make failover

# 2. Restore data from backup
make restore-latest HOST=rpi-friend

# 3. Verify services
ssh homelab@ub-friend-blue "docker ps"
```

### Data Corruption

```bash
# 1. Stop affected service
ssh homelab@merry "docker stop <service>"

# 2. Restore from backup
make restore-latest HOST=rpi-home

# 3. Restart service
ssh homelab@merry "docker start <service>"
```

### Lost Access

If you lose SSH access:

1. Connect to node physically (keyboard + monitor)
2. Login as `homelab` user
3. Check SSH service: `sudo systemctl status ssh`
4. Check firewall: `sudo ufw status`
5. Re-add SSH keys if needed

---

## Maintenance Schedule

### Daily

-  Automated backups run (no action needed)
- 👁 Quick health check if desired

### Weekly

-  Check backup logs
-  Review disk space
-  Update system packages

### Monthly

-  **Test backup restoration** (critical!)
-  Apply security updates
-  Review logs for errors
-  Prune old backups
-  Database maintenance

### Quarterly

-  Full security audit
-  Review service usage
-  Update documentation
-  Test disaster recovery procedures

### Annually

-  Hardware inspection
-  Cable management
-  Review and update passwords
-  Full DR drill

---

## Additional Resources

- [DISASTER-RECOVERY.md](DISASTER-RECOVERY.md) - Emergency procedures
- [TESTING.md](TESTING.md) - Testing scenarios
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Detailed troubleshooting
- [SETUP.md](SETUP.md) - First-time setup
