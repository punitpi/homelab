# 🧪 Testing Scenarios

Comprehensive testing procedures for validating your homelab infrastructure.

---

## Table of Contents

1. [Overview](#overview)
2. [Pre-Deployment Testing](#pre-deployment-testing)
3. [Post-Deployment Testing](#post-deployment-testing)
4. [Backup & Restore Testing](#backup--restore-testing)
5. [High Availability Testing](#high-availability-testing)
6. [Disaster Recovery Testing](#disaster-recovery-testing)
7. [Security Testing](#security-testing)
8. [Performance Testing](#performance-testing)
9. [Automated Testing](#automated-testing)

---

## Overview

### Testing Philosophy

- **Test Before Deploy**: Validate configuration before applying
- **Test After Deploy**: Verify deployment succeeded
- **Regular Testing**: Monthly backup/restore tests
- **Chaos Testing**: Quarterly disaster scenarios
- **Document Results**: Track all test outcomes

### Test Environment

Most tests can run on:

-  Production standby node (rpi-friend)
-  Temporary test VM
-  Avoid testing on primary node during business hours

---

## Pre-Deployment Testing

### Test 1: Configuration Validation

**Purpose:** Ensure all configuration files are valid before deployment

**Frequency:** Before every deployment

**Duration:** 2 minutes

```bash
# Run validation script
make validate

# Expected output:
#  All required files exist
#  All secrets defined
#  Docker Compose syntax valid
#  Ansible playbook syntax valid
#  Inventory accessible
```

**Success Criteria:**

- All checks pass
- No placeholder values in secrets
- No syntax errors

**Troubleshooting:**

```bash
# If Docker Compose syntax fails
docker compose -f stacks/base/compose.yml config
docker compose -f stacks/apps/compose.yml config

# If Ansible syntax fails
ansible-playbook --syntax-check ansible/site.yml

# If secrets validation fails
grep -r "your-" env/secrets.env  # Should return nothing
```

---

### Test 2: Ansible Connectivity

**Purpose:** Verify Ansible can connect to all nodes

**Frequency:** Before deployments, after inventory changes

**Duration:** 1 minute

```bash
# Test connectivity to all nodes
ansible all -i inventory/hosts.ini -m ping

# Expected: All nodes return "pong"

# Test sudo access
ansible all -i inventory/hosts.ini -b -m shell -a "whoami"

# Expected: All return "root"

# Test with verbose output
ansible all -i inventory/hosts.ini -m ping -vvv
```

**Success Criteria:**

- All nodes respond with `"pong"`
- No authentication errors
- No timeout errors

**Troubleshooting:**

```bash
# If SSH fails
ssh homelab@<node-tailscale-ip>

# Check SSH key
ssh-add -l

# Check inventory
cat inventory/hosts.ini

# Test direct connection
ansible rpi-home -i inventory/hosts.ini -m ping -vvv
```

---

### Test 3: SSH Key Authentication

**Purpose:** Verify passwordless SSH access works

**Frequency:** After bootstrap, after key changes

**Duration:** 2 minutes

```bash
# Test SSH to all nodes
for host in rpi-home rpi-friend india-box; do
  echo "Testing $host..."
  ssh homelab@$host "echo 'SSH to $host: OK'" || echo "Failed: $host"
done

# Test sudo without password
ssh homelab@rpi-home "sudo whoami"

# Expected: "root" without password prompt
```

**Success Criteria:**

- SSH connects without password
- Sudo works without password
- No "Permission denied" errors

---

### Test 4: Docker Compose Syntax

**Purpose:** Validate Docker Compose files before deployment

**Frequency:** After editing compose files

**Duration:** 1 minute

```bash
# Validate base stack
docker compose -f stacks/base/compose.yml config > /dev/null && echo "Base: OK" || echo "Base: FAILED"

# Validate apps stack
docker compose -f stacks/apps/compose.yml config > /dev/null && echo "Apps: OK" || echo "Apps: FAILED"

# Check for environment variable substitution
docker compose -f stacks/apps/compose.yml config | grep -i "variable"
# Should not find any unsubstituted ${VARIABLE} strings
```

**Success Criteria:**

- Both stacks validate successfully
- All variables resolved
- No syntax errors

---

## Post-Deployment Testing

### Test 5: Service Health Check

**Purpose:** Verify all containers started successfully

**Frequency:** After every deployment

**Duration:** 5 minutes

```bash
# Check all containers running
ssh homelab@rpi-home "docker ps --format 'table {{.Names}}\t{{.Status}}'"

# Count running vs expected
ssh homelab@rpi-home "docker ps -q | wc -l"
# Base (7) + Apps (10) = 17 expected

# Check for unhealthy containers
ssh homelab@rpi-home "docker ps --filter 'health=unhealthy'"
# Should return empty

# Check for restarting containers
ssh homelab@rpi-home "docker ps --filter 'status=restarting'"
# Should return empty
```

**Success Criteria:**

- All expected containers running
- No unhealthy containers
- No containers in restart loop
- Status shows "Up X minutes"

**Troubleshooting:**

```bash
# If container not running
ssh homelab@rpi-home "docker logs <container-name>"

# If container unhealthy
ssh homelab@rpi-home "docker inspect <container-name> | grep -A 20 Health"

# Restart failed container
ssh homelab@rpi-home "docker restart <container-name>"
```

---

### Test 6: Service Accessibility

**Purpose:** Verify services are accessible via Tailscale

**Frequency:** After deployment, after network changes

**Duration:** 5 minutes

```bash
# Get Tailscale IP
TAILSCALE_IP=$(ssh homelab@rpi-home tailscale ip -4)

# Test each service
services=(
  "8081:FreshRSS"
  "9925:Mealie"
  "8282:Wallos"
  "8082:SterlingPDF"
  "8083:SearXNG"
  "8443:VSCode"
  "8084:OpenWebUI"
  "13378:Audiobookshelf"
  "3000:AdGuard"
  "5432:PostgreSQL"
)

for service in "${services[@]}"; do
  port="${service%%:*}"
  name="${service##*:}"

  if curl -s -o /dev/null -w "%{http_code}" "http://${TAILSCALE_IP}:${port}" | grep -q "200\|302\|401"; then
    echo " $name ($port): OK"
  else
    echo " $name ($port): FAILED"
  fi
done
```

**Success Criteria:**

- All services return HTTP 200, 302, or 401 (auth required)
- No connection refused errors
- Services respond within 5 seconds

---

### Test 7: Database Connectivity

**Purpose:** Verify databases are accessible and working

**Frequency:** After base deployment, after database updates

**Duration:** 3 minutes

```bash
# Test PostgreSQL
ssh homelab@rpi-home "docker exec postgres psql -U postgres -c 'SELECT 1;'"
# Expected: "1"

# List databases
ssh homelab@rpi-home "docker exec postgres psql -U postgres -c '\l'"
# Expected: postgres, freshrss, mealie databases

# Test Redis
ssh homelab@rpi-home "docker exec redis redis-cli PING"
# Expected: "PONG"

# Check Redis memory
ssh homelab@rpi-home "docker exec redis redis-cli INFO memory | grep used_memory_human"

# Test database connection from app
ssh homelab@rpi-home "docker exec freshrss nc -zv localhost 5432"
# Expected: Connection successful
```

**Success Criteria:**

- PostgreSQL responds to queries
- All expected databases exist
- Redis responds to PING
- Apps can connect to databases

---

### Test 8: Log Review

**Purpose:** Check logs for errors after deployment

**Frequency:** After deployment

**Duration:** 5 minutes

```bash
# Check for errors in all containers
ssh homelab@rpi-home "docker ps --format '{{.Names}}' | xargs -I {} sh -c 'echo \"=== {} ===\"  && docker logs --tail 50 {} 2>&1 | grep -i error'"

# Check Docker daemon logs
ssh homelab@rpi-home "journalctl -u docker --since '10 minutes ago' | grep -i error"

# Check system logs
ssh homelab@rpi-home "journalctl --since '10 minutes ago' -p err"
```

**Success Criteria:**

- No critical errors in logs
- No connection failures
- No permission denied errors
- Warnings are acceptable if service works

---

## Backup & Restore Testing

### Test 9: Initial Backup

**Purpose:** Verify backup system works after deployment

**Frequency:** After backup automation deployment

**Duration:** 10 minutes

```bash
# Run manual backup
make backup-now HOST=rpi-home

# Monitor backup progress
ssh homelab@rpi-home "tail -f /var/log/backup.log"

# Wait for completion (Ctrl+C to stop following)

# Verify backup succeeded
ssh homelab@rpi-home "tail -n 50 /var/log/backup.log | grep -i 'snapshot.*saved'"

# List snapshots
ssh homelab@rpi-home "restic -r b2:your-bucket snapshots"

# Check backup size
ssh homelab@rpi-home "restic -r b2:your-bucket stats latest"
```

**Success Criteria:**

- Backup completes without errors
- Snapshot created in B2
- Backup size reasonable (1-50GB typically)
- Backup time < 30 minutes

**Expected Duration:**

- First backup: 10-30 minutes (full data)
- Subsequent backups: 2-10 minutes (incremental)

---

### Test 10: Non-Destructive Restore Test

**Purpose:** Verify restore works without affecting production

**Frequency:** Monthly (critical!)

**Duration:** 15 minutes

```bash
# Run restore test on standby node
make restore-test HOST=rpi-friend

# Verify restore directory created
ssh homelab@rpi-friend "ls -lh /tmp/restic_restore_test/"

# Check restored Docker volumes
ssh homelab@rpi-friend "ls -lh /tmp/restic_restore_test/docker_volumes/"
ssh homelab@rpi-friend "du -sh /tmp/restic_restore_test/docker_volumes/*"

# Check database dumps
ssh homelab@rpi-friend "ls -lh /tmp/restic_restore_test/databases/"
ssh homelab@rpi-friend "file /tmp/restic_restore_test/databases/*.sql"

# Verify database dump content (spot check)
ssh homelab@rpi-friend "head -n 20 /tmp/restic_restore_test/databases/freshrss.sql"

# Check configuration files
ssh homelab@rpi-friend "ls -lh /tmp/restic_restore_test/config/"

# Calculate total restored size
ssh homelab@rpi-friend "du -sh /tmp/restic_restore_test/"

# Clean up
ssh homelab@rpi-friend "rm -rf /tmp/restic_restore_test/"
```

**Success Criteria:**

- Restore completes without errors
- All directories present
- Database dumps are valid SQL
- File sizes reasonable
- Total size matches backup size

**Red Flags:**

-  Database dumps empty or corrupted
-  Missing Docker volumes
-  Restore size significantly different from backup
-  Restore fails with errors

---

### Test 11: Database Restore Verification

**Purpose:** Verify database dumps are valid and restorable

**Frequency:** Monthly with restore test

**Duration:** 10 minutes

```bash
# After running restore test, verify database dumps

# Check SQL dump syntax (shouldn't return errors)
ssh homelab@rpi-friend "cat /tmp/restic_restore_test/databases/freshrss.sql | head -n 100"

# Try to restore to test database (non-destructive)
ssh homelab@rpi-home "docker exec postgres psql -U postgres -c 'CREATE DATABASE test_restore;'"

ssh homelab@rpi-friend "cat /tmp/restic_restore_test/databases/freshrss.sql" | \
  ssh homelab@rpi-home "docker exec -i postgres psql -U postgres -d test_restore"

# Check restored data
ssh homelab@rpi-home "docker exec postgres psql -U postgres -d test_restore -c '\dt'"

# Count records (should match production)
ssh homelab@rpi-home "docker exec postgres psql -U postgres -d test_restore -c 'SELECT COUNT(*) FROM <some_table>;'"

# Clean up test database
ssh homelab@rpi-home "docker exec postgres psql -U postgres -c 'DROP DATABASE test_restore;'"
```

**Success Criteria:**

- SQL dump parses without errors
- Database restores successfully
- Tables and data present
- Record counts reasonable

---

### Test 12: Backup Automation

**Purpose:** Verify automated backups run on schedule

**Frequency:** After backup deployment, 24 hours later

**Duration:** 5 minutes (+ 24 hour wait)

```bash
# Check cron job exists
ssh homelab@rpi-home "sudo crontab -l | grep backup"

# Expected output similar to:
# 0 3 * * * /opt/backups/backup_now.sh >> /var/log/backup.log 2>&1

# Wait 24 hours, then check if backup ran
ssh homelab@rpi-home "tail -n 100 /var/log/backup.log | grep $(date +%Y-%m-%d)"

# List snapshots - should see daily backups
ssh homelab@rpi-home "restic -r b2:your-bucket snapshots --group-by host"

# Check last backup time
ssh homelab@rpi-home "restic -r b2:your-bucket snapshots latest"
```

**Success Criteria:**

- Cron job configured
- Backup ran automatically
- New snapshot created daily
- No errors in logs

---

## High Availability Testing

### Test 13: Standby Node Promotion

**Purpose:** Verify standby can take over from primary

**Frequency:** Quarterly

**Duration:** 20 minutes

```bash
# Document current state
echo "Test started: $(date)" > ha_test_log.txt
ssh homelab@rpi-home "docker ps" >> ha_test_log.txt

# Stop apps on primary (simulate failure)
ssh homelab@rpi-home "cd /opt/stacks/apps && docker compose down"

# Record start time
START_TIME=$(date +%s)

# Promote standby
make failover

# Wait for services to start
sleep 60

# Record end time
END_TIME=$(date +%s)
DOWNTIME=$((END_TIME - START_TIME))
echo "Failover time: ${DOWNTIME} seconds" | tee -a ha_test_log.txt

# Get rpi-friend Tailscale IP
FRIEND_IP=$(ssh homelab@rpi-friend tailscale ip -4)

# Test services on rpi-friend
services=(8081 9925 8282 8082 8083 8443 8084 13378)
for port in "${services[@]}"; do
  if curl -s -o /dev/null -w "%{http_code}" "http://${FRIEND_IP}:${port}" | grep -q "200\|302\|401"; then
    echo " Port $port: OK" | tee -a ha_test_log.txt
  else
    echo " Port $port: FAILED" | tee -a ha_test_log.txt
  fi
done

# Check logs for errors
ssh homelab@rpi-friend "cd /opt/stacks/apps && docker compose logs" >> ha_test_log.txt

# Restore primary
ssh homelab@rpi-home "cd /opt/stacks/apps && docker compose up -d"

# Stop apps on standby
ssh homelab@rpi-friend "cd /opt/stacks/apps && docker compose down"

# Final report
echo "Test completed: $(date)" | tee -a ha_test_log.txt
echo "Target RTO: <15 minutes" | tee -a ha_test_log.txt
echo "Actual failover: ${DOWNTIME} seconds" | tee -a ha_test_log.txt
```

**Success Criteria:**

- Failover completed in < 15 minutes
- All services accessible on standby
- No data loss (for data backed up)
- Fallback to primary successful

**Target Metrics:**

- Failover time: < 5 minutes
- Service availability: 100% on standby
- Data loss: Limited to time since last backup

---

### Test 14: Split-Brain Prevention

**Purpose:** Verify both nodes don't run apps simultaneously

**Frequency:** During HA tests

**Duration:** 5 minutes

```bash
# Start apps on both nodes (intentional misconfiguration)
ssh homelab@rpi-home "cd /opt/stacks/apps && docker compose up -d"
ssh homelab@rpi-friend "cd /opt/stacks/apps && docker compose up -d"

# Check port conflicts
ssh homelab@rpi-home "docker ps | grep -E '8081|9925'"
ssh homelab@rpi-friend "docker ps | grep -E '8081|9925'"

# Check database connections
ssh homelab@rpi-home "docker logs freshrss | tail -n 20"
ssh homelab@rpi-friend "docker logs freshrss | tail -n 20"

# Stop apps on one node
ssh homelab@rpi-friend "cd /opt/stacks/apps && docker compose down"
```

**Expected Behavior:**

- Services may conflict if both try to connect to same DB
- No data corruption should occur
- Containers may restart if ports conflict

**Prevention:**

- Only one node should run apps at a time
- Use `APPS_ENABLED` flag to control
- Monitor for split-brain condition

---

## Disaster Recovery Testing

### Test 15: Full Node Rebuild

**Purpose:** Verify complete rebuild process

**Frequency:** Annually

**Duration:** 2-4 hours

**Prerequisites:**

- Spare SD card or test hardware
- Valid backups in B2
- This repository cloned

```bash
# See detailed procedure in DISASTER-RECOVERY.md
# Follow "Procedure 4: Full Node Restore"

# Key metrics to track:
# - Time to flash OS: ~10 min
# - Time to bootstrap: ~20 min
# - Time to deploy base: ~10 min
# - Time to restore backup: ~30 min
# - Time to deploy apps: ~10 min
# - Total time: 1-2 hours
```

**Success Criteria:**

- Node rebuilt from scratch
- All data restored
- All services working
- Total time < 4 hours

---

### Test 16: Backup Corruption Scenario

**Purpose:** Test recovery when backup is corrupted

**Frequency:** Annually

**Duration:** 1 hour

```bash
# Verify current backup
ssh homelab@rpi-home "restic -r b2:your-bucket check"

# Simulate using older backup (skip latest)
ssh homelab@rpi-home "restic -r b2:your-bucket snapshots"
# Note the second-to-last snapshot ID

# Restore from older snapshot
ssh homelab@rpi-home
restic -r b2:your-bucket restore <older-snapshot-id> \
  --target /tmp/old_restore \
  --include /docker_volumes

# Verify older data
ls -lh /tmp/old_restore/docker_volumes/

# Clean up
rm -rf /tmp/old_restore/
```

**Success Criteria:**

- Can restore from older backups
- Older backups are valid
- Data loss limited to time between backups

---

## Security Testing

### Test 17: SSH Hardening Verification

**Purpose:** Verify SSH is properly secured

**Frequency:** After bootstrap, quarterly

**Duration:** 5 minutes

```bash
# Test that root login is disabled
ssh root@<tailscale-ip>
# Expected: Permission denied

# Test that password auth is disabled
ssh -o PreferredAuthentications=password homelab@<tailscale-ip>
# Expected: Permission denied

# Verify SSH config
ssh homelab@rpi-home "sudo grep -E '(PermitRootLogin|PasswordAuthentication)' /etc/ssh/sshd_config"

# Expected output:
# PermitRootLogin no
# PasswordAuthentication no

# Test that key auth works
ssh homelab@rpi-home "echo 'Key auth OK'"
```

**Success Criteria:**

- Root login disabled
- Password authentication disabled
- Key-based auth works
- SSH config hardened

---

### Test 18: Firewall Configuration

**Purpose:** Verify firewall rules are correct

**Frequency:** After bootstrap, quarterly

**Duration:** 5 minutes

```bash
# Check UFW status
ssh homelab@rpi-home "sudo ufw status verbose"

# Expected rules:
# - 22/tcp ALLOW (SSH)
# - 51820/udp ALLOW (Tailscale)
# - 41641/udp ALLOW (Tailscale)

# Test that only allowed ports are open
ssh homelab@rpi-home "sudo netstat -tlnp"

# Verify Docker containers NOT exposed to 0.0.0.0
ssh homelab@rpi-home "sudo netstat -tlnp | grep docker-proxy"
# Should show 127.0.0.1:* not 0.0.0.0:*
```

**Success Criteria:**

- UFW enabled and active
- Only required ports open
- Docker containers bind to localhost
- No unexpected listeners

---

### Test 19: Secret Management

**Purpose:** Verify secrets are not exposed

**Frequency:** Before each deployment

**Duration:** 3 minutes

```bash
# Check that secrets.env is not in git
git ls-files | grep secrets.env
# Expected: empty (only secrets.example.env should be tracked)

# Check for placeholder values
grep -r "your-" env/secrets.env
# Expected: empty

# Check for secrets in logs
ssh homelab@rpi-home "docker logs freshrss | grep -i password"
# Expected: No plaintext passwords

# Verify secrets.env permissions
ssh homelab@rpi-home "ls -l /opt/stacks/env/secrets.env"
# Expected: -rw------- (600) or -rw-r----- (640)
```

**Success Criteria:**

- secrets.env not in version control
- No placeholder values
- No secrets in logs
- Proper file permissions

---

## Performance Testing

### Test 20: Resource Usage

**Purpose:** Monitor system resource usage under load

**Frequency:** After deployment, quarterly

**Duration:** 10 minutes

```bash
# Check CPU usage
ssh homelab@rpi-home "top -bn2 | grep 'Cpu(s)'"

# Check memory usage
ssh homelab@rpi-home "free -h"

# Check disk usage
ssh homelab@rpi-home "df -h /"

# Check Docker resource usage
ssh homelab@rpi-home "docker stats --no-stream"

# Check temperature (Raspberry Pi)
ssh homelab@rpi-home "vcgencmd measure_temp"

# Check system load
ssh homelab@rpi-home "uptime"
```

**Success Criteria:**

- CPU usage < 70% average
- Memory usage < 80%
- Disk usage < 80%
- Temperature < 70°C
- Load average < number of cores

**Performance Baselines:**

- Idle CPU: 5-15%
- Idle Memory: 2-3GB used (out of 8GB)
- App CPU: 20-40%
- App Memory: 4-6GB used

---

### Test 21: Backup Performance

**Purpose:** Measure backup speed and optimize

**Frequency:** Quarterly

**Duration:** Time of one backup

```bash
# Run timed backup
time make backup-now HOST=rpi-home

# Check backup log for timing
ssh homelab@rpi-home "grep 'processed.*in' /var/log/backup.log | tail -n 1"

# Check Restic stats
ssh homelab@rpi-home "restic -r b2:your-bucket stats latest"

# Measure upload speed
ssh homelab@rpi-home "curl -s https://speed.cloudflare.com/__down?bytes=25000000 > /dev/null"
```

**Target Metrics:**

- Incremental backup: < 10 minutes
- Full backup: < 30 minutes
- Upload speed: > 10 Mbps

---

## Automated Testing

### Test 22: Continuous Validation

Create automated test script:

```bash
#!/bin/bash
# Save as scripts/continuous_test.sh

set -e

echo "=== Homelab Continuous Tests ==="
echo "Started: $(date)"

# Test 1: Ansible connectivity
echo "Test 1: Ansible connectivity..."
ansible all -i inventory/hosts.ini -m ping || exit 1

# Test 2: Service health
echo "Test 2: Service health..."
ssh homelab@rpi-home "docker ps --format '{{.Names}}\t{{.Status}}' | grep -v 'Up' && exit 1 || exit 0"

# Test 3: Database connectivity
echo "Test 3: Database..."
ssh homelab@rpi-home "docker exec postgres psql -U postgres -c 'SELECT 1;'" || exit 1

# Test 4: Backup status
echo "Test 4: Backup status..."
ssh homelab@rpi-home "restic -r b2:your-bucket snapshots latest" || exit 1

# Test 5: Disk space
echo "Test 5: Disk space..."
DISK_USAGE=$(ssh homelab@rpi-home "df / | tail -1 | awk '{print \$5}' | sed 's/%//'")
if [ "$DISK_USAGE" -gt 80 ]; then
  echo "WARNING: Disk usage high: ${DISK_USAGE}%"
fi

echo "All tests passed!"
echo "Completed: $(date)"
```

Run weekly via cron:

```bash
# On management machine
crontab -e

# Add:
0 8 * * 1 cd /path/to/homelab && ./scripts/continuous_test.sh >> test_log.txt 2>&1
```

---

## Test Result Template

Document test results:

```markdown
## Test Results: [Test Name]

**Date:** [YYYY-MM-DD]
**Tester:** [Your name]
**Environment:** [Production/Staging/Test]

### Pre-Test State

- Services running: [X/Y]
- Last backup: [Date/Time]
- Disk usage: [X%]

### Test Execution

- Start time: [HH:MM]
- End time: [HH:MM]
- Duration: [X minutes]

### Results

- [ ] Test passed
- [ ] Test failed
- [ ] Partial success

### Observations

- [Observation 1]
- [Observation 2]

### Issues Found

1. [Issue description]
   - Severity: [Critical/High/Medium/Low]
   - Resolution: [How it was fixed]

### Metrics

- Downtime: [X minutes]
- Recovery time: [X minutes]
- Data loss: [None/X minutes worth]

### Follow-Up Actions

- [ ] Update documentation
- [ ] Fix identified issues
- [ ] Retest after fixes
```

---

## Testing Schedule

### Daily

- Automated health checks (if implemented)

### Weekly

- Review backup logs
- Check service availability

### Monthly

- **Restore test (critical!)**
- Security audit
- Performance review

### Quarterly

- HA failover test
- Full DR drill
- Security penetration test
- Performance benchmarking

### Annually

- Complete rebuild test
- Hardware inspection
- Documentation review
- Full DR scenario

---

## Additional Resources

- [DISASTER-RECOVERY.md](DISASTER-RECOVERY.md) - DR procedures
- [OPERATIONS.md](OPERATIONS.md) - Daily operations
- Main [README.md](../README.md) - Setup guide
