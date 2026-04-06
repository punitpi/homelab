# 🚨 Disaster Recovery Guide

Complete disaster recovery procedures for various failure scenarios.

---

## Table of Contents

1. [Overview](#overview)
2. [Failure Scenarios](#failure-scenarios)
3. [Recovery Procedures](#recovery-procedures)
4. [DR Testing](#dr-testing)
5. [Prevention](#prevention)

---

## Overview

### Recovery Time Objectives (RTO)

| Scenario               | Target RTO | Expected Downtime      |
| ---------------------- | ---------- | ---------------------- |
| Single service failure | 5 minutes  | Restart service        |
| Primary node failure   | 15 minutes | Promote standby        |
| Complete site failure  | 2-4 hours  | Rebuild + restore      |
| Data corruption        | 1-2 hours  | Restore from backup    |
| Both RPis lost         | 4-8 hours  | New hardware + restore |

### Recovery Point Objectives (RPO)

| Data Type        | Backup Frequency   | Max Data Loss     |
| ---------------- | ------------------ | ----------------- |
| Application data | Daily (3 AM)       | 24 hours          |
| Databases        | Daily (pre-backup) | 24 hours          |
| Configuration    | On deploy          | Until last deploy |

### Prerequisites for DR

-  Valid backups in Backblaze B2
-  Backup encryption password (`RESTIC_PASSWORD`)
-  B2 credentials (`B2_KEY_ID`, `B2_APP_KEY`)
-  Copy of this repository
-  Ansible installed on management machine
-  SSH access to at least one functioning node

---

## Failure Scenarios

### 1. Single Service Failure

**Symptoms:**

- One Docker container crashed
- Service not responding
- Error logs in `docker logs <service>`

**Impact:** Low - Other services continue running

**Recovery:** [Procedure 1](#procedure-1-recover-single-service)

---

### 2. Primary Node (rpi-home) Offline

**Symptoms:**

- Cannot SSH to rpi-home
- Services not accessible
- Tailscale shows node offline

**Impact:** Medium - All services down, data intact on standby

**Recovery:** [Procedure 2](#procedure-2-promote-standby-node)

---

### 3. Database Corruption

**Symptoms:**

- Services report database errors
- PostgreSQL won't start
- Database integrity check fails

**Impact:** Medium - Services down until database restored

**Recovery:** [Procedure 3](#procedure-3-restore-database)

---

### 4. Complete Data Loss on Primary

**Symptoms:**

- Disk failure on rpi-home
- Filesystem corruption
- Accidental deletion

**Impact:** High - Full restore required

**Recovery:** [Procedure 4](#procedure-4-full-node-restore)

---

### 5. Both RPis Lost/Destroyed

**Symptoms:**

- Physical damage (fire, theft, etc.)
- Both nodes unrecoverable
- Complete hardware loss

**Impact:** Critical - New hardware + full restore

**Recovery:** [Procedure 5](#procedure-5-rebuild-from-scratch)

---

### 6. Backup System Failure

**Symptoms:**

- Backups haven't run in days
- Cannot connect to B2
- Backup logs show errors

**Impact:** Critical - No recovery possible if data also lost

**Recovery:** [Procedure 6](#procedure-6-fix-backup-system)

---

### 7. Tailscale Network Failure

**Symptoms:**

- Cannot connect to services via Tailscale
- Nodes show offline in Tailscale admin
- Local access works, Tailscale doesn't

**Impact:** Medium - Services running but not accessible

**Recovery:** [Procedure 7](#procedure-7-restore-tailscale)

---

## Recovery Procedures

### Procedure 1: Recover Single Service

**Time:** 5 minutes  
**Skill Level:** Easy

```bash
# 1. Check service status
ssh homelab@rpi-home "docker ps -a | grep <service>"

# 2. View error logs
ssh homelab@rpi-home "docker logs <service>"

# 3. Restart service
ssh homelab@rpi-home "docker restart <service>"

# 4. If restart fails, recreate
ssh homelab@rpi-home "cd /opt/stacks/apps && docker compose up -d <service>"

# 5. Verify service is running
ssh homelab@rpi-home "docker ps | grep <service>"
ssh homelab@rpi-home "docker logs -f <service>"

# 6. Test service
curl http://<tailscale-ip>:<port>
```

**If still failing:**

- Check disk space: `df -h`
- Check memory: `free -h`
- Redeploy: `make deploy-apps target=rpi-home`
- Restore from backup if data corrupted

---

### Procedure 2: Promote Standby Node

**Time:** 15 minutes  
**Skill Level:** Intermediate

**Scenario:** rpi-home is offline, need services back online ASAP

```bash
# 1. Verify rpi-home is truly offline
ansible rpi-home -i inventory/hosts.ini -m ping
# Expected: Failure

# 2. Verify rpi-friend is online
ansible rpi-friend -i inventory/hosts.ini -m ping
# Expected: SUCCESS

# 3. Check rpi-friend has base services running
ssh homelab@rpi-friend "docker ps"
# Should see: postgres, redis, tailscale, adguard

# 4. Promote rpi-friend to primary
make failover

# 5. Verify apps are starting
ssh homelab@rpi-friend "docker ps"
# Should see: freshrss, mealie, etc.

# 6. Wait for services to be healthy (2-3 minutes)
ssh homelab@rpi-friend "docker ps --format 'table {{.Names}}\t{{.Status}}'"

# 7. Get rpi-friend's Tailscale IP
ssh homelab@rpi-friend tailscale ip -4

# 8. Update DNS/bookmarks to use rpi-friend's IP

# 9. Test services
curl http://<rpi-friend-tailscale-ip>:8081  # FreshRSS
curl http://<rpi-friend-tailscale-ip>:9925  # Mealie

# 10. Monitor logs for errors
ssh homelab@rpi-friend "cd /opt/stacks/apps && docker compose logs -f"
```

**Note:** This uses rpi-friend's existing database (from last backup). Recent data on rpi-home will be lost unless you restore.

**To restore latest data from backup:**

```bash
# Stop apps
ssh homelab@rpi-friend "cd /opt/stacks/apps && docker compose down"

# Restore from rpi-home's last backup
make restore-latest HOST=rpi-friend

# Start apps
ssh homelab@rpi-friend "cd /opt/stacks/apps && docker compose up -d"
```

---

### Procedure 3: Restore Database

**Time:** 30 minutes  
**Skill Level:** Intermediate

**Scenario:** PostgreSQL corrupted, services can't connect

```bash
# 1. Stop all services using the database
ssh homelab@rpi-home "cd /opt/stacks/apps && docker compose down"

# 2. Stop and remove database container
ssh homelab@rpi-home "cd /opt/stacks/base && docker compose stop postgres"
ssh homelab@rpi-home "docker rm postgres"

# 3. Backup corrupted data (just in case)
ssh homelab@rpi-home "sudo mv /opt/docker/volumes/postgres_data /opt/docker/volumes/postgres_data.corrupted.$(date +%Y%m%d)"

# 4. Create fresh database volume
ssh homelab@rpi-home "sudo mkdir -p /opt/docker/volumes/postgres_data"

# 5. Restore database from backup
ssh homelab@rpi-home
export RESTIC_PASSWORD=your-restic-password
restic -r b2:your-bucket restore latest \
  --target /tmp/restore \
  --include /docker_volumes/postgres_data

# 6. Copy restored data to volume
sudo cp -a /tmp/restore/docker_volumes/postgres_data/* /opt/docker/volumes/postgres_data/

# 7. Fix permissions
sudo chown -R 999:999 /opt/docker/volumes/postgres_data

# 8. Start database
cd /opt/stacks/base && docker compose up -d postgres

# 9. Wait for database to be ready
docker logs -f postgres
# Wait for: "database system is ready to accept connections"

# 10. Start applications
cd /opt/stacks/apps && docker compose up -d

# 11. Verify services
docker ps
docker compose logs -f
```

**Alternative: Restore from SQL dumps**

```bash
# If Restic restore fails, use SQL dumps
ssh homelab@rpi-home
restic -r b2:your-bucket restore latest \
  --target /tmp/restore \
  --include /databases

# Restore each database
docker exec -i postgres psql -U postgres < /tmp/restore/databases/freshrss.sql
docker exec -i postgres psql -U postgres < /tmp/restore/databases/mealie.sql
```

---

### Procedure 4: Full Node Restore

**Time:** 1-2 hours  
**Skill Level:** Advanced

**Scenario:** rpi-home disk failed, replaced with new SSD

```bash
# 1. Flash fresh Raspberry Pi OS to new SSD

# 2. Boot and get IP address
# Check your router or use: nmap -sn 192.168.1.0/24

# 3. Copy SSH key to new system
ssh-copy-id pi@<new-rpi-ip>

# 4. Run bootstrap script
scp scripts/bootstrap.sh pi@<new-rpi-ip>:/tmp/
ssh pi@<new-rpi-ip>
sudo bash /tmp/bootstrap.sh Europe/Vienna pi

# 5. Join Tailscale network
ssh homelab@<new-rpi-ip>
sudo tailscale up --ssh --accept-routes --accept-dns --authkey=tskey-auth-XXXXX

# 6. Get new Tailscale IP and update inventory
ssh homelab@<new-rpi-ip> tailscale ip -4
# Update inventory/hosts.ini with new IP

# 7. Deploy base services
make deploy-base --limit rpi-home

# 8. Wait for base services to start
ssh homelab@rpi-home "docker ps"

# 9. Stop base services to restore data
ssh homelab@rpi-home "cd /opt/stacks/base && docker compose down"

# 10. Restore from backup
make restore-latest HOST=rpi-home

# 11. Restart base services
ssh homelab@rpi-home "cd /opt/stacks/base && docker compose up -d"

# 12. Deploy applications
make deploy-apps target=rpi-home

# 13. Verify everything is running
ssh homelab@rpi-home "docker ps --format 'table {{.Names}}\t{{.Status}}'"

# 14. Test services
curl http://<tailscale-ip>:8081  # FreshRSS
curl http://<tailscale-ip>:9925  # Mealie

# 15. Check logs for errors
ssh homelab@rpi-home "cd /opt/stacks/apps && docker compose logs"
```

**Total downtime:** 1-2 hours (bootstrap ~30min, restore ~30min, deploy ~15min, verification ~15min)

---

### Procedure 5: Rebuild from Scratch

**Time:** 4-8 hours  
**Skill Level:** Advanced

**Scenario:** Both RPis destroyed, new hardware purchased

```bash
# === On Management Machine ===

# 1. Verify backups exist
# Login to Backblaze B2 console
# Verify bucket contains recent backups

# 2. Clone repository (if needed)
git clone <your-repo-url> homelab-recovery
cd homelab-recovery

# 3. Verify secrets file
cat env/secrets.env
# Must have: RESTIC_PASSWORD, B2 credentials

# === Prepare New Hardware ===

# 4. Flash both new RPis with Raspberry Pi OS Lite (64-bit)

# 5. Boot both RPis, find their IPs

# 6. Setup SSH keys
ssh-copy-id pi@<new-rpi-home-ip>
ssh-copy-id pi@<new-rpi-friend-ip>

# 7. Bootstrap both nodes
for ip in <new-rpi-home-ip> <new-rpi-friend-ip>; do
  scp scripts/bootstrap.sh pi@$ip:/tmp/
  ssh pi@$ip "sudo bash /tmp/bootstrap.sh Europe/Vienna pi"
done

# 8. Join both to Tailscale
# Get auth key from: https://login.tailscale.com/admin/settings/keys
ssh homelab@<new-rpi-home-ip> "sudo tailscale up --ssh --accept-routes --accept-dns --authkey=tskey-auth-XXXXX"
ssh homelab@<new-rpi-friend-ip> "sudo tailscale up --ssh --accept-routes --accept-dns --authkey=tskey-auth-XXXXX"

# 9. Get Tailscale IPs
ssh homelab@<new-rpi-home-ip> tailscale ip -4
ssh homelab@<new-rpi-friend-ip> tailscale ip -4

# 10. Update inventory with new Tailscale IPs
nano inventory/hosts.ini

# 11. Test Ansible connectivity
ansible all -i inventory/hosts.ini -m ping

# === Deploy Infrastructure ===

# 12. Validate configuration
make validate

# 13. Deploy base services to both nodes
make deploy-base

# 14. Verify base services running
ansible all -i inventory/hosts.ini -m shell -a "docker ps"

# === Restore Data ===

# 15. Stop base services on rpi-home
ssh homelab@rpi-home "cd /opt/stacks/base && docker compose down"

# 16. Restore rpi-home from last backup
make restore-latest HOST=rpi-home

# 17. Restart base services
ssh homelab@rpi-home "cd /opt/stacks/base && docker compose up -d"

# 18. Wait for services to be ready
ssh homelab@rpi-home "docker ps"

# === Deploy Applications ===

# 19. Deploy apps to rpi-home
make deploy-apps target=rpi-home

# 20. Verify apps starting
ssh homelab@rpi-home "docker ps --format 'table {{.Names}}\t{{.Status}}'"

# === Verification ===

# 21. Test all services
for port in 8081 9925 8282 8082 8083 8443 8084 13378; do
  curl -I http://<rpi-home-tailscale-ip>:$port
done

# 22. Check service logs
ssh homelab@rpi-home "cd /opt/stacks/apps && docker compose logs"

# 23. Setup backups again
make deploy-backup-automation

# 24. Run test backup
make backup-now HOST=rpi-home
make backup-now HOST=rpi-friend

# 25. Verify backup worked
ssh homelab@rpi-home "tail -n 50 /var/log/backup.log"
```

**Checklist:**

- [ ] Both nodes bootstrapped
- [ ] Tailscale connected
- [ ] Base services running
- [ ] Data restored from backup
- [ ] Applications deployed
- [ ] All services accessible
- [ ] Backup automation working
- [ ] Monitoring configured

---

### Procedure 6: Fix Backup System

**Time:** 30 minutes  
**Skill Level:** Intermediate

**Scenario:** Backups haven't run for days

```bash
# 1. Check backup cron status
ssh homelab@rpi-home "sudo systemctl status cron"

# 2. Check backup log
ssh homelab@rpi-home "tail -n 100 /var/log/backup.log"

# 3. Test B2 connection
ssh homelab@rpi-home
export B2_ACCOUNT_ID=<your-key-id>
export B2_ACCOUNT_KEY=<your-app-key>
rclone lsd b2:your-bucket

# 4. Test Restic connection
export RESTIC_PASSWORD=<your-password>
restic -r b2:your-bucket snapshots

# 5. If credentials invalid, update secrets
# On management machine:
nano env/secrets.env
make deploy-backup-automation

# 6. Run manual backup to test
make backup-now HOST=rpi-home

# 7. Verify backup succeeded
ssh homelab@rpi-home "tail -n 50 /var/log/backup.log | grep 'snapshot'"

# 8. Check cron job exists
ssh homelab@rpi-home "sudo crontab -l | grep backup"

# 9. If cron job missing, redeploy
make deploy-backup-automation

# 10. Verify daily backups resume
# Wait 24 hours and check
ssh homelab@rpi-home "tail -n 100 /var/log/backup.log"
```

**Common issues:**

- Invalid B2 credentials: Update secrets.env and redeploy
- Disk full: Clean up space, adjust backup exclusions
- Network issues: Check Tailscale, check internet connection
- Restic lock: `restic -r b2:bucket unlock`

---

### Procedure 7: Restore Tailscale

**Time:** 15 minutes  
**Skill Level:** Easy

**Scenario:** Tailscale not working, can't connect to services

```bash
# 1. Check Tailscale status on node (via local SSH)
ssh homelab@<local-ip> "tailscale status"

# 2. Check if Tailscale container running
ssh homelab@<local-ip> "docker ps | grep tailscale"

# 3. Restart Tailscale container
ssh homelab@<local-ip> "docker restart tailscale"

# 4. Check Tailscale logs
ssh homelab@<local-ip> "docker logs tailscale"

# 5. If still not working, rejoin network
ssh homelab@<local-ip>
sudo tailscale down
sudo tailscale up --ssh --accept-routes --accept-dns --authkey=tskey-auth-XXXXX

# 6. Verify connection
tailscale status
tailscale ping rpi-friend

# 7. If container missing, redeploy base
make deploy-base --limit rpi-home
```

---

## DR Testing

### Monthly DR Test

**Test backup restoration without disrupting production:**

```bash
# 1. Run restore test on standby node
make restore-test HOST=rpi-friend

# 2. Verify restored data
ssh homelab@rpi-friend "ls -lh /tmp/restic_restore_test/"

# 3. Check database dumps
ssh homelab@rpi-friend "file /tmp/restic_restore_test/databases/*.sql"

# 4. Verify Docker volumes
ssh homelab@rpi-friend "ls -lh /tmp/restic_restore_test/docker_volumes/"

# 5. Clean up
ssh homelab@rpi-friend "rm -rf /tmp/restic_restore_test/"

# 6. Document results
echo "$(date): Backup test successful" >> dr_test_log.txt
```

### Quarterly Full DR Drill

**Simulate complete failure:**

```bash
# 1. Stop apps on primary (simulate failure)
ssh homelab@rpi-home "cd /opt/stacks/apps && docker compose down"

# 2. Promote standby
make failover

# 3. Time how long until services available
# Target: < 15 minutes

# 4. Verify all services work on standby

# 5. Restore primary and fail back
make restore-latest HOST=rpi-home
make deploy-apps target=rpi-home

# 6. Stop apps on standby
ssh homelab@rpi-friend "cd /opt/stacks/apps && docker compose down"

# 7. Document lessons learned
```

### Annual Complete Rebuild Test

**Full disaster scenario:**

1. Setup spare SD card or use test hardware
2. Follow [Procedure 5](#procedure-5-rebuild-from-scratch)
3. Time the entire process
4. Document any issues
5. Update procedures based on findings

---

## Prevention

### Avoid Disasters

1. **Automated Backups**

   - Ensure daily backups running
   - Monitor backup logs weekly
   - Test restores monthly

2. **Monitoring**

   - Setup Uptime Kuma alerts
   - Monitor disk space
   - Check service health daily

3. **Documentation**

   - Keep this repo updated
   - Document any custom changes
   - Maintain runbook

4. **High Availability**

   - Keep standby node ready
   - Regular failover tests
   - Automated promotion

5. **Security**

   - Keep systems updated
   - Strong passwords
   - SSH key only access
   - Firewall configured

6. **Hardware**
   - Use quality SSDs
   - Keep spare SD cards
   - Backup power (UPS)
   - Temperature monitoring

### Backup Best Practices

```bash
# 1. Multiple backup targets
# Add second backup location (optional)
export RESTIC_REPOSITORY2=b2:second-bucket
restic -r $RESTIC_REPOSITORY2 backup ...

# 2. Verify backups
# Weekly verification
restic -r b2:bucket check

# 3. Test restores
# Monthly test restore
make restore-test HOST=rpi-friend

# 4. Offsite copies
# Store backup password in password manager
# Keep copy of secrets.env in secure location

# 5. Monitor storage
restic -r b2:bucket stats
```

---

## Recovery Checklist Template

Use this for any DR event:

```markdown
## DR Event: [Date] [Scenario]

### Initial Assessment

- [ ] Identify failure type
- [ ] Assess scope of impact
- [ ] Determine recovery procedure
- [ ] Notify stakeholders (if applicable)

### Recovery Actions

- [ ] Follow procedure: [Procedure #]
- [ ] Start time: [HH:MM]
- [ ] Actions taken:
  - [ ] Action 1
  - [ ] Action 2
  - [ ] Action 3

### Verification

- [ ] All services running
- [ ] Data integrity checked
- [ ] Backups working
- [ ] Monitoring restored
- [ ] End time: [HH:MM]
- [ ] Total downtime: [X hours/minutes]

### Post-Incident

- [ ] Root cause identified
- [ ] Documentation updated
- [ ] Prevention measures implemented
- [ ] Lessons learned documented
```

---

## Emergency Contacts

```markdown
### Repository Information

- Repo URL: [your-repo-url]
- Branch: main
- Last updated: [date]

### Critical Credentials

- Stored in: [password manager]
- Backup location: [secure location]
- Access: [who has access]

### Hardware Information

- Primary: Raspberry Pi 5 (8GB) + 1TB SSD
- Standby: Raspberry Pi 5 (8GB) + 1TB SSD
- Purchase link: [where to buy replacements]

### Service Providers

- Tailscale: https://login.tailscale.com
- Backblaze: https://www.backblaze.com/b2/
- Cloud Provider: [your provider]
```

---

## Additional Resources

- [OPERATIONS.md](OPERATIONS.md) - Day-to-day operations
- [TESTING.md](TESTING.md) - Testing procedures
- Main [README.md](../README.md) - Setup guide
- [MIGRATION.md](MIGRATION.md) - Migration planning
