# 🗓 20-Day Migration Plan: India → Austria

Complete timeline for migrating homelab from India to Austria with zero data loss and minimal downtime.

---

## Table of Contents

1. [Overview](#overview)
2. [Migration Strategy](#migration-strategy)
3. [Pre-Migration Preparation](#pre-migration-preparation)
4. [Weekly Timeline](#weekly-timeline)
5. [Risk Management](#risk-management)
6. [Rollback Plan](#rollback-plan)

---

## Overview

### Migration Goals

-  Move `rpi-home` from India to Austria
-  Zero data loss
-  Minimize service downtime (< 30 minutes)
-  Validate all systems work in new location
-  Update all documentation

### Migration Approach

**Strategy: Active-Standby Failover**

1. **Promote** `rpi-friend` to primary (in India)
2. **Ship** `rpi-home` to Austria
3. **Setup** `rpi-home` in Austria
4. **Failover** back to `rpi-home` (now in Austria)
5. **Keep** `rpi-friend` as standby (still in India)

### Timeline Overview

| Phase                        | Duration | Days       | Status             |
| ---------------------------- | -------- | ---------- | ------------------ |
| **Phase 1: Preparation**     | Week 1   | Days 1-7   | Planning & Testing |
| **Phase 2: Pre-Migration**   | Week 2   | Days 8-14  | Backups & Failover |
| **Phase 3: Transit & Setup** | Week 3   | Days 15-17 | Shipping & Setup   |
| **Phase 4: Verification**    | Week 3-4 | Days 18-20 | Testing & Docs     |

---

## Migration Strategy

### Why This Approach?

1. **No Service Interruption**: Services stay online during shipping
2. **Data Safety**: Multiple backups before physical transport
3. **Tested Process**: Uses existing HA failover procedure
4. **Reversible**: Can rollback at any step
5. **Documented**: Every step documented and tested

### Key Milestones

- 🎯 **Day 7**: All tests passed, ready to proceed
- 🎯 **Day 14**: Failover complete, rpi-home ready to ship
- 🎯 **Day 17**: rpi-home operational in Austria
- 🎯 **Day 20**: Final verification, documentation updated

---

## Pre-Migration Preparation

### Before Day 1

**Management Machine Setup:**

```bash
# Ensure you have:
- [ ] Ansible installed
- [ ] SSH keys configured
- [ ] This repository cloned
- [ ] Secrets file backed up
- [ ] Access to Tailscale admin
- [ ] Access to Backblaze B2
```

**Backup Critical Information:**

```bash
# Save to password manager or secure location:
- [ ] Tailscale auth key
- [ ] B2 credentials
- [ ] All passwords from secrets.env
- [ ] Raspberry Pi serial numbers
- [ ] Network configuration details
```

**Physical Preparation:**

```bash
# For shipping rpi-home:
- [ ] Anti-static bag
- [ ] Bubble wrap
- [ ] Sturdy box
- [ ] Shipping label materials
- [ ] Tracked shipping service selected
```

---

## Weekly Timeline

## Week 1: Preparation & Testing (Days 1-7)

### Day 1: Environment Setup & Validation

**Time Required:** 2 hours  
**Risk Level:** Low

**Tasks:**

```bash
# 1. Clone fresh copy of repository
git clone <repo-url> homelab-migration
cd homelab-migration

# 2. Verify all configuration files
make validate

# 3. Test Ansible connectivity
ansible all -i inventory/hosts.ini -m ping

# 4. Document current state
cat > migration_journal.md << EOF
# Migration Journal

## Current State (Day 1)
- Date: $(date)
- Primary: rpi-home (India)
- Standby: rpi-friend (India)
- Services: All operational

## Baseline Metrics
EOF

# 5. Collect baseline metrics
ssh homelab@rpi-home "docker ps --format 'table {{.Names}}\t{{.Status}}'" >> migration_journal.md
ssh homelab@rpi-home "df -h" >> migration_journal.md
ssh homelab@rpi-home "free -h" >> migration_journal.md

# 6. Verify backup system
ssh homelab@rpi-home "restic -r b2:your-bucket snapshots --last 7"
```

**Success Criteria:**

- [ ] All validation checks pass
- [ ] Ansible connects to all nodes
- [ ] Last backup < 24 hours old
- [ ] All services running
- [ ] Baseline metrics documented

**Deliverables:**

- `migration_journal.md` with current state
- Validation report
- Baseline metrics

---

### Day 2: Backup System Verification

**Time Required:** 3 hours  
**Risk Level:** Low

**Tasks:**

```bash
# 1. Run full backup on all nodes
for host in rpi-home rpi-friend india-box; do
  echo "Backing up $host..."
  make backup-now HOST=$host
done

# 2. Verify backups succeeded
ssh homelab@rpi-home "tail -n 100 /var/log/backup.log | grep -i 'snapshot.*saved'"

# 3. List all snapshots
ssh homelab@rpi-home "restic -r b2:your-bucket snapshots"

# 4. Check backup sizes
ssh homelab@rpi-home "restic -r b2:your-bucket stats latest"

# 5. Run non-destructive restore test
make restore-test HOST=rpi-friend

# 6. Verify restored data
ssh homelab@rpi-friend "ls -lh /tmp/restic_restore_test/docker_volumes/"
ssh homelab@rpi-friend "ls -lh /tmp/restic_restore_test/databases/"
ssh homelab@rpi-friend "du -sh /tmp/restic_restore_test/"

# 7. Test database dump validity
ssh homelab@rpi-friend "file /tmp/restic_restore_test/databases/*.sql"

# 8. Document results
echo "Backup test passed: $(date)" >> migration_journal.md

# 9. Clean up test restore
ssh homelab@rpi-friend "rm -rf /tmp/restic_restore_test/"
```

**Success Criteria:**

- [ ] Fresh backups on all nodes
- [ ] Restore test successful
- [ ] Database dumps valid
- [ ] Backup sizes reasonable
- [ ] No errors in backup logs

---

### Day 3: Failover Testing (Dry Run)

**Time Required:** 4 hours  
**Risk Level:** Medium

**Tasks:**

```bash
# 1. Document pre-test state
echo "=== Failover Test (Day 3) ===" >> migration_journal.md
echo "Start time: $(date)" >> migration_journal.md

# 2. Stop apps on primary (simulate failure)
ssh homelab@rpi-home "cd /opt/stacks/apps && docker compose down"

# 3. Record downtime start
START_TIME=$(date +%s)

# 4. Promote standby
make failover

# 5. Wait for services to start
sleep 120

# 6. Get rpi-friend Tailscale IP
FRIEND_IP=$(ssh homelab@rpi-friend tailscale ip -4)
echo "rpi-friend IP: $FRIEND_IP" >> migration_journal.md

# 7. Test all services
services=(8081 9925 8282 8082 8083 8443 8084 13378)
for port in "${services[@]}"; do
  curl -I "http://${FRIEND_IP}:${port}" && echo "Port $port: OK" >> migration_journal.md
done

# 8. Record downtime end
END_TIME=$(date +%s)
DOWNTIME=$((END_TIME - START_TIME))
echo "Downtime: ${DOWNTIME} seconds" >> migration_journal.md

# 9. Verify data consistency
ssh homelab@rpi-friend "cd /opt/stacks/apps && docker compose logs" | grep -i error

# 10. Test services for 1 hour while monitoring

# 11. Failback to primary
ssh homelab@rpi-home "cd /opt/stacks/apps && docker compose up -d"
ssh homelab@rpi-friend "cd /opt/stacks/apps && docker compose down"

# 12. Document results
echo "Failover test completed: $(date)" >> migration_journal.md
echo "Target RTO: <15 min, Actual: ${DOWNTIME}s" >> migration_journal.md
```

**Success Criteria:**

- [ ] Failover completed in < 15 minutes
- [ ] All services accessible on standby
- [ ] No errors in logs
- [ ] Failback successful
- [ ] No data loss

**Go/No-Go Decision Point:**

- If failover test fails, **STOP** and fix issues before proceeding

---

### Day 4: Network Planning

**Time Required:** 2 hours  
**Risk Level:** Low

**Tasks:**

```bash
# 1. Document Austria network details
cat >> migration_journal.md << EOF

## Austria Network Setup
- ISP: [Your ISP]
- Router: [Router model]
- Expected speeds: [Down/Up Mbps]
- Static IP available: [Yes/No]
- Port forwarding needed: No (using Tailscale)
EOF

# 2. Verify Tailscale auth keys
# Generate new auth key with:
# - Reusable: Yes
# - Ephemeral: No
# - Tags: homelab, austria

# Save auth key securely
echo "New Tailscale auth key generated: $(date)" >> migration_journal.md

# 3. Plan IP addressing
cat >> migration_journal.md << EOF

## IP Addressing Plan
- rpi-home (Austria): [Will get new Tailscale IP]
- rpi-friend (India): [Current: 100.x.x.x]
- india-box (India): [Current: 100.x.x.x]

## DNS Updates Needed
- Update bookmarks with new IPs
- Update Traefik backend (if using)
- Update any hardcoded IPs in configs
EOF

# 4. Test Tailscale from management machine
tailscale status
tailscale netcheck
```

**Deliverables:**

- Network plan documented
- Tailscale auth key ready
- IP addressing plan
- DNS update checklist

---

### Day 5: Documentation & Runbooks

**Time Required:** 3 hours  
**Risk Level:** Low

**Tasks:**

```bash
# 1. Create Austria setup runbook
cat > docs/AUSTRIA_SETUP.md << EOF
# Austria Setup Runbook

## Network Setup
1. Connect rpi-home to router
2. Get local IP: \`ip addr show\`
3. Test internet: \`ping 8.8.8.8\`

## Tailscale Setup
1. Join network: \`sudo tailscale up --authkey=KEY\`
2. Verify: \`tailscale status\`
3. Get IP: \`tailscale ip -4\`

## Service Verification
1. Check Docker: \`docker ps\`
2. Test services: [List of URLs]
3. Check logs: [Commands]

## Troubleshooting
- No internet: [Steps]
- Tailscale issues: [Steps]
- Services not starting: [Steps]
EOF

# 2. Create shipping checklist
cat > docs/SHIPPING_CHECKLIST.md << EOF
# Shipping Checklist

## Before Shutdown
- [ ] Run final backup
- [ ] Verify backup succeeded
- [ ] Document any pending tasks
- [ ] Export any temporary data

## Shutdown Procedure
- [ ] Stop all services: \`cd /opt/stacks/apps && docker compose down\`
- [ ] Stop base services: \`cd /opt/stacks/base && docker compose down\`
- [ ] Leave Tailscale down
- [ ] Safely shutdown: \`sudo shutdown -h now\`
- [ ] Wait for all LEDs to stop
- [ ] Disconnect power
- [ ] Disconnect all cables

## Packaging
- [ ] Place in anti-static bag
- [ ] Wrap in bubble wrap (at least 2 layers)
- [ ] Place in sturdy box
- [ ] Fill empty space with packing material
- [ ] Label as "FRAGILE - ELECTRONIC DEVICE"
- [ ] Add "THIS SIDE UP" labels

## Shipping
- [ ] Use tracked shipping service
- [ ] Insure for replacement value
- [ ] Save tracking number
- [ ] Note expected delivery date
EOF

# 3. Update main README with migration notes
echo "Migration documentation created: $(date)" >> migration_journal.md
```

**Deliverables:**

- Austria setup runbook
- Shipping checklist
- Migration notes in README

---

### Day 6: Secondary Backup & Verification

**Time Required:** 2 hours  
**Risk Level:** Low

**Tasks:**

```bash
# 1. Create secondary backup location (optional but recommended)
# If you have another cloud storage or local NAS

# 2. Run fresh backup on all nodes
for host in rpi-home rpi-friend india-box; do
  make backup-now HOST=$host
done

# 3. Verify all backups
ssh homelab@rpi-home "restic -r b2:your-bucket snapshots --last 3"

# 4. Download critical configs locally (offline backup)
mkdir -p backup_configs
scp -r homelab@rpi-home:/opt/stacks backup_configs/
scp homelab@rpi-home:/opt/stacks/env/* backup_configs/env/

# 5. Export Docker images (optional - for faster recovery)
ssh homelab@rpi-home "docker images --format '{{.Repository}}:{{.Tag}}' | grep -v '<none>' | head -n 10"

# 6. Document backup locations
cat >> migration_journal.md << EOF

## Backup Locations
- Primary: Backblaze B2 (bucket: your-bucket)
- Secondary: [If applicable]
- Local config backup: $(pwd)/backup_configs
- Last backup: $(date)
EOF
```

**Success Criteria:**

- [ ] Fresh backups completed
- [ ] Local config backup saved
- [ ] All backup locations documented
- [ ] Multiple recovery options available

---

### Day 7: Final Preparation & Go/No-Go Decision

**Time Required:** 2 hours  
**Risk Level:** Low

**Tasks:**

```bash
# 1. Run full validation suite
./scripts/validate_setup.sh

# 2. Run health checks
ansible all -i inventory/hosts.ini -m shell -a "docker ps --format 'table {{.Names}}\t{{.Status}}'"

# 3. Review migration journal
cat migration_journal.md

# 4. Create final checklist
cat > MIGRATION_CHECKLIST.md << EOF
# Migration Go/No-Go Checklist

## Preparation (Week 1)
- [ ] All tests passed
- [ ] Failover tested successfully
- [ ] Backups verified
- [ ] Documentation complete
- [ ] Shipping materials ready
- [ ] Austria network planned
- [ ] Tailscale auth key ready

## Risk Assessment
- Impact: Medium (temporary failover to standby)
- Probability of issues: Low (tested procedure)
- Data loss risk: None (multiple backups)
- Rollback available: Yes

## Go/No-Go Decision
- Date: $(date)
- Decision: [ ] GO  [ ] NO-GO
- Signed: ________________
EOF

# 5. Make Go/No-Go decision
echo "=== Week 1 Complete ===" >> migration_journal.md
echo "Go/No-Go decision: [TO BE FILLED]" >> migration_journal.md
```

**Go Criteria (all must be YES):**

- [ ] All validation tests pass
- [ ] Failover test successful (< 15 min)
- [ ] Backup/restore test successful
- [ ] All documentation complete
- [ ] Shipping materials ready
- [ ] Austria location prepared
- [ ] Team comfortable with plan

**No-Go Criteria (any triggers stop):**

- [ ] Any critical test failed
- [ ] Data integrity concerns
- [ ] Backup system issues
- [ ] Austria location not ready
- [ ] Unexpected technical issues

---

## Week 2: Pre-Migration & Failover (Days 8-14)

### Day 8: Final System Health Check

**Time Required:** 2 hours  
**Risk Level:** Low

```bash
# 1. Run comprehensive health check
ssh homelab@rpi-home "docker stats --no-stream"
ssh homelab@rpi-home "df -h"
ssh homelab@rpi-home "free -h"
ssh homelab@rpi-home "vcgencmd measure_temp"

# 2. Check for pending updates
ssh homelab@rpi-home "apt list --upgradable"

# 3. Apply any critical updates
ssh homelab@rpi-home "sudo apt update && sudo apt upgrade -y"

# 4. Reboot if needed
# ssh homelab@rpi-home "sudo reboot"

# 5. Document system state
echo "=== System Health (Day 8) ===" >> migration_journal.md
ssh homelab@rpi-home "docker ps" >> migration_journal.md
```

**Success Criteria:**

- [ ] All services healthy
- [ ] System updated
- [ ] No pending issues
- [ ] Ready for failover

---

### Day 9-10: Pre-Migration Backup Window

**Time Required:** 4 hours spread over 2 days  
**Risk Level:** Low

```bash
# DAY 9: Multiple backups

# 1. Stop any write-heavy operations if possible

# 2. Run backup on all nodes
for host in rpi-home rpi-friend india-box; do
  echo "Backing up $host..."
  make backup-now HOST=$host
  echo "Backup completed: $(date)" >> migration_journal.md
done

# 3. Wait 12 hours

# DAY 10: Final verification backup

# 4. Run another round of backups
for host in rpi-home rpi-friend; do
  make backup-now HOST=$host
done

# 5. Verify both backup sets exist
ssh homelab@rpi-home "restic -r b2:your-bucket snapshots --last 5"

# 6. Test restoration from latest
make restore-test HOST=rpi-friend

# 7. Document backup window
echo "Pre-migration backups complete: $(date)" >> migration_journal.md
echo "Total snapshots available: $(ssh homelab@rpi-home 'restic -r b2:your-bucket snapshots | wc -l')" >> migration_journal.md
```

**Success Criteria:**

- [ ] Multiple backup sets created
- [ ] All backups verified
- [ ] Restore test successful
- [ ] Backup integrity confirmed

---

### Day 11: Promote rpi-friend (THE FAILOVER)

**Time Required:** 1 hour  
**Risk Level:** HIGH  
**Point of No Return:** After step 3

**Pre-Failover Checklist:**

```bash
# Verify before proceeding:
- [ ] rpi-friend healthy: `ansible rpi-friend -m ping`
- [ ] Latest backup < 24h old
- [ ] Restore test passed (Day 10)
- [ ] All documentation ready
- [ ] Austria setup prepared
```

**Failover Procedure:**

```bash
# 1. Announce maintenance window (if applicable)
echo "=== FAILOVER STARTING ===" >> migration_journal.md
echo "Start time: $(date)" >> migration_journal.md

# 2. Run final backup on primary
make backup-now HOST=rpi-home
ssh homelab@rpi-home "tail -n 50 /var/log/backup.log | grep -i 'snapshot.*saved'"

# 3. STOP APPS ON PRIMARY (Point of No Return)
ssh homelab@rpi-home "cd /opt/stacks/apps && docker compose down"

# Record downtime start
START_TIME=$(date +%s)

# 4. PROMOTE STANDBY
make failover

# 5. Wait for services to start (2-3 minutes)
sleep 180

# 6. Verify services on rpi-friend
FRIEND_IP=$(ssh homelab@rpi-friend tailscale ip -4)
echo "Services moved to: $FRIEND_IP" >> migration_journal.md

# 7. Test all services
services=(8081 9925 8282 8082 8083 8443 8084 13378)
for port in "${services[@]}"; do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://${FRIEND_IP}:${port}")
  echo "Port $port: $STATUS" >> migration_journal.md
done

# 8. Check logs for errors
ssh homelab@rpi-friend "cd /opt/stacks/apps && docker compose logs --tail=50" > failover_logs.txt

# 9. Monitor for 30 minutes
# Verify services are stable

# 10. Record completion
END_TIME=$(date +%s)
DOWNTIME=$((END_TIME - START_TIME))
echo "=== FAILOVER COMPLETE ===" >> migration_journal.md
echo "Downtime: ${DOWNTIME} seconds" >> migration_journal.md
echo "Services now on: rpi-friend (India)" >> migration_journal.md

# 11. Update DNS/bookmarks if needed
echo "Update service URLs to: $FRIEND_IP" >> migration_journal.md
```

**Success Criteria:**

- [ ] All services running on rpi-friend
- [ ] Downtime < 15 minutes
- [ ] No errors in logs
- [ ] Services stable for 30+ minutes

**Rollback Procedure (if needed):**

```bash
# If failover fails, rollback:
ssh homelab@rpi-friend "cd /opt/stacks/apps && docker compose down"
ssh homelab@rpi-home "cd /opt/stacks/apps && docker compose up -d"
echo "ROLLBACK EXECUTED: $(date)" >> migration_journal.md
```

---

### Day 12-13: Stability Monitoring

**Time Required:** Passive monitoring  
**Risk Level:** Low

```bash
# Monitor rpi-friend for 48 hours

# DAY 12: 24-hour check
ssh homelab@rpi-friend "docker ps"
ssh homelab@rpi-friend "cd /opt/stacks/apps && docker compose logs --since 24h" | grep -i error

# Verify services
curl -I http://<rpi-friend-ip>:8081
curl -I http://<rpi-friend-ip>:9925

# Check resource usage
ssh homelab@rpi-friend "docker stats --no-stream"

# DAY 13: 48-hour check
echo "48-hour stability check: $(date)" >> migration_journal.md
ssh homelab@rpi-friend "uptime" >> migration_journal.md
ssh homelab@rpi-friend "docker ps" >> migration_journal.md
```

**Success Criteria:**

- [ ] No service crashes
- [ ] No error increase
- [ ] Resource usage normal
- [ ] Users report no issues

---

### Day 14: Prepare rpi-home for Shipping

**Time Required:** 2 hours  
**Risk Level:** Low

```bash
# 1. Run final backup on rpi-home (current data)
make backup-now HOST=rpi-home

# 2. Verify backup
ssh homelab@rpi-home "restic -r b2:your-bucket snapshots latest"

# 3. Stop all services
ssh homelab@rpi-home "cd /opt/stacks/apps && docker compose down"
ssh homelab@rpi-home "cd /opt/stacks/base && docker compose down"

# 4. Leave Tailscale down
ssh homelab@rpi-home "sudo tailscale down"

# 5. Shutdown system
ssh homelab@rpi-home "sudo shutdown -h now"

# 6. Physical preparation (follow SHIPPING_CHECKLIST.md)
# - Disconnect power (wait for all LEDs off)
# - Disconnect SSD
# - Place in anti-static bag
# - Wrap in bubble wrap
# - Pack in box with padding
# - Label as FRAGILE

# 7. Ship to Austria
# - Use tracked service (DHL/FedEx)
# - Insurance for ~€200
# - Save tracking number

# 8. Document shipping
cat >> migration_journal.md << EOF

=== rpi-home Shipped (Day 14) ===
- Tracking: [NUMBER]
- Carrier: [CARRIER]
- Expected delivery: [DATE]
- Shipped from: India
- Shipped to: Austria
- Insured: Yes/No
EOF
```

**Checklist:**

- [ ] Final backup completed
- [ ] Services stopped cleanly
- [ ] System shut down properly
- [ ] Hardware packed securely
- [ ] Shipped with tracking
- [ ] Tracking number saved

---

## Week 3: Transit & Austria Setup (Days 15-17)

### Day 15-16: Transit Period

**Time Required:** Passive monitoring  
**Risk Level:** Low

```bash
# Monitor shipping status
# Check tracking daily
# Services continue on rpi-friend

# Document transit
echo "Transit day $(date): Status = [TRACKING_UPDATE]" >> migration_journal.md

# Verify rpi-friend still stable
ssh homelab@rpi-friend "docker ps"
ssh homelab@rpi-friend "uptime"
```

---

### Day 17: Austria Setup

**Time Required:** 3 hours  
**Risk Level:** Medium

**Unboxing & Inspection:**

```bash
# 1. Inspect hardware for shipping damage
- [ ] No physical damage
- [ ] All connections intact
- [ ] SSD securely attached

# 2. Document receipt
echo "=== rpi-home arrived in Austria (Day 17) ===" >> migration_journal.md
echo "Condition: [GOOD/DAMAGED]" >> migration_journal.md
```

**Network Setup:**

```bash
# 3. Connect to Austria network
# - Connect Ethernet cable
# - Connect power
# - Boot system

# 4. Find local IP (check router or use monitor)
# Example: 192.168.178.10

# 5. SSH using local IP
ssh homelab@192.168.178.10

# 6. Verify system booted correctly
uptime
docker ps  # Should be empty or only base services

# 7. Join Tailscale network
sudo tailscale up --ssh --accept-routes --accept-dns --authkey=tskey-auth-XXXXX

# 8. Get new Tailscale IP
tailscale ip -4
# Example: 100.101.102.150

# 9. Update inventory
# On management machine:
nano inventory/hosts.ini
# Update rpi-home ansible_host to new Tailscale IP

# 10. Test Ansible connectivity
ansible rpi-home -i inventory/hosts.ini -m ping
```

**Deploy Services:**

```bash
# 11. Deploy base services
make deploy-base --limit rpi-home

# 12. Wait for base services
ssh homelab@rpi-home "docker ps"
# Should see: postgres, redis, tailscale, adguard

# 13. Stop base services for restore
ssh homelab@rpi-home "cd /opt/stacks/base && docker compose down"

# 14. Restore from backup
make restore-latest HOST=rpi-home

# 15. Restart base services
ssh homelab@rpi-home "cd /opt/stacks/base && docker compose up -d"

# 16. Deploy apps
make deploy-apps target=rpi-home

# 17. Verify all services running
ssh homelab@rpi-home "docker ps --format 'table {{.Names}}\t{{.Status}}'"

# 18. Get new Tailscale IP for access
NEW_IP=$(ssh homelab@rpi-home tailscale ip -4)
echo "rpi-home new IP: $NEW_IP" >> migration_journal.md
```

**Success Criteria:**

- [ ] System booted successfully
- [ ] Network connected
- [ ] Tailscale working
- [ ] All services deployed
- [ ] Data restored
- [ ] Services accessible

---

## Week 4: Verification & Documentation (Days 18-20)

### Day 18: Comprehensive Testing

**Time Required:** 4 hours  
**Risk Level:** Low

```bash
# Follow testing procedures from TESTING.md

# 1. Service health check
ssh homelab@rpi-home "docker ps"

# 2. Test all service URLs
NEW_IP=$(ssh homelab@rpi-home tailscale ip -4)
for port in 8081 9925 8282 8082 8083 8443 8084 13378; do
  echo "Testing port $port..."
  curl -I "http://${NEW_IP}:${port}"
done

# 3. Database connectivity
ssh homelab@rpi-home "docker exec postgres psql -U postgres -c 'SELECT 1;'"
ssh homelab@rpi-home "docker exec redis redis-cli PING"

# 4. Check logs for errors
ssh homelab@rpi-home "cd /opt/stacks/apps && docker compose logs --since 1h" | grep -i error

# 5. Run backup test
make backup-now HOST=rpi-home

# 6. Verify backup to B2
ssh homelab@rpi-home "restic -r b2:your-bucket snapshots latest"

# 7. Test restoration
make restore-test HOST=rpi-friend

# 8. Performance check
ssh homelab@rpi-home "docker stats --no-stream"
ssh homelab@rpi-home "vcgencmd measure_temp"

# Document results
echo "=== Austria Testing Complete (Day 18) ===" >> migration_journal.md
```

**Success Criteria:**

- [ ] All services operational
- [ ] Databases working
- [ ] Backups working
- [ ] Performance normal
- [ ] No critical errors

---

### Day 19: Failback to Austria Primary

**Time Required:** 1 hour  
**Risk Level:** Medium

**Failback Procedure:**

```bash
# 1. Verify rpi-home (Austria) is stable
ssh homelab@rpi-home "docker ps"

# 2. Update service URLs/bookmarks to Austria IP
NEW_IP=$(ssh homelab@rpi-home tailscale ip -4)
echo "Update bookmarks to: $NEW_IP" >> migration_journal.md

# 3. Run final backup on rpi-friend
make backup-now HOST=rpi-friend

# 4. Stop apps on rpi-friend (India)
START_TIME=$(date +%s)
ssh homelab@rpi-friend "cd /opt/stacks/apps && docker compose down"

# 5. Services now primary on rpi-home (Austria)
# Already running from Day 17

# 6. Monitor for issues
sleep 60

# 7. Verify services
for port in 8081 9925 8282 8082 8083 8443 8084 13378; do
  curl -I "http://${NEW_IP}:${port}"
done

# 8. Record completion
END_TIME=$(date +%s)
DOWNTIME=$((END_TIME - START_TIME))
echo "=== Failback Complete (Day 19) ===" >> migration_journal.md
echo "Downtime: ${DOWNTIME} seconds" >> migration_journal.md
echo "Primary: rpi-home (Austria)" >> migration_journal.md
echo "Standby: rpi-friend (India)" >> migration_journal.md
```

**Success Criteria:**

- [ ] Services running in Austria
- [ ] rpi-friend stopped cleanly
- [ ] Downtime < 5 minutes
- [ ] No errors

---

### Day 20: Final Documentation & Cleanup

**Time Required:** 3 hours  
**Risk Level:** Low

```bash
# 1. Update all documentation
cat >> README.md << EOF

## Migration History
- Migrated: $(date)
- Primary location: Austria
- Standby location: India
- Migration duration: 20 days
- Total downtime: ~15 minutes (failover) + ~1 minute (failback)
EOF

# 2. Update inventory with final IPs
nano inventory/hosts.ini

# 3. Update host_vars with new details
cat > inventory/host_vars/rpi-home.yml << EOF
---
location: austria
timezone: Europe/Vienna
apps_enabled: true
EOF

# 4. Document network configuration
cat > docs/NETWORK_CONFIG.md << EOF
# Network Configuration

## Austria (Primary)
- Location: Vienna, Austria
- Node: rpi-home
- Tailscale IP: $NEW_IP
- Local network: [Details]
- ISP: [ISP name]

## India (Standby)
- Location: [City], India
- Node: rpi-friend
- Tailscale IP: [IP]
- Local network: [Details]
EOF

# 5. Create migration report
cat > MIGRATION_REPORT.md << EOF
# Migration Report: India → Austria

## Summary
- **Start Date**: [Day 1 date]
- **Completion Date**: $(date)
- **Duration**: 20 days
- **Total Downtime**: ~16 minutes
- **Data Loss**: None
- **Issues**: [None or list]

## Metrics
- Failover time: [X seconds]
- Shipping time: [X days]
- Austria setup time: [X hours]
- Failback time: [X seconds]

## Lessons Learned
1. [Lesson 1]
2. [Lesson 2]
3. [Lesson 3]

## Recommendations
1. [Recommendation 1]
2. [Recommendation 2]

## Final State
- Primary: rpi-home (Austria, $NEW_IP)
- Standby: rpi-friend (India, [IP])
- Status: Operational
- Last backup: $(date)
EOF

# 6. Cleanup temporary files
rm -f backup_configs.tar.gz
rm -f failover_logs.txt

# 7. Run final validation
make validate

# 8. Test DR procedures with new setup
make restore-test HOST=rpi-friend

# 9. Update backup schedule if timezone changed
# Edit cron jobs if needed

# 10. Celebrate! 🎉
echo "🎉 Migration complete!" >> migration_journal.md
```

**Final Checklist:**

- [ ] All documentation updated
- [ ] Inventory updated
- [ ] Network config documented
- [ ] Migration report created
- [ ] Validation passed
- [ ] Backups working
- [ ] DR tested
- [ ] Team trained on new setup

---

## Risk Management

### Identified Risks

| Risk                    | Probability | Impact   | Mitigation                                  |
| ----------------------- | ----------- | -------- | ------------------------------------------- |
| Shipping damage         | Low         | High     | Insurance, good packaging, tracked shipping |
| Data loss               | Very Low    | Critical | Multiple backups, tested restores           |
| Extended downtime       | Low         | Medium   | Tested failover, standby ready              |
| Network issues Austria  | Medium      | Medium   | Pre-plan, Tailscale backup                  |
| Service incompatibility | Low         | Medium   | Test in Austria before failback             |
| Backup restore fails    | Very Low    | Critical | Test monthly, multiple backup sets          |

### Mitigation Strategies

**Before Shipping:**

- Multiple backup copies
- Tested restore procedures
- Standby node proven
- All procedures documented

**During Transit:**

- Quality packaging
- Insurance
- Tracked shipping
- Services remain on standby

**After Arrival:**

- Careful unboxing
- System inspection
- Gradual service restoration
- Extensive testing

---

## Rollback Plan

### Rollback Scenarios

**Scenario 1: Austria Setup Fails**

```bash
# If rpi-home won't start in Austria
# Solution: Keep using rpi-friend in India
# No action needed - services already stable
```

**Scenario 2: Data Corruption**

```bash
# If restored data is corrupted
# Solution: Restore from older backup
make restore-latest HOST=rpi-home
# Try previous snapshots until valid data found
```

**Scenario 3: Complete Failure**

```bash
# If rpi-home is damaged/lost
# Solution: Promote rpi-friend permanently
make failover
# Purchase new hardware
# Follow rebuild procedure
```

---

## Communication Plan

### Stakeholders

- Primary user (you)
- Family members using services
- Friends with access (if any)

### Communication Schedule

**Day 0 (Week before):**

- "Planning homelab migration to Austria"
- "Services will remain online throughout"

**Day 11 (Failover):**

- "Brief downtime (< 15 min) for maintenance"
- "Services temporarily on different IP"

**Day 17 (Austria Setup):**

- "Hardware arrived in Austria"
- "Setting up services in new location"

**Day 19 (Failback):**

- "Brief downtime (< 5 min) for final switch"
- "Services now running from Austria"

**Day 20 (Complete):**

- "Migration successful!"
- "New service IPs: [list]"

---

## Success Metrics

### Target KPIs

-  **Total Downtime**: < 30 minutes
-  **Data Loss**: 0 bytes
-  **Migration Duration**: 20 days
-  **Test Success Rate**: 100%
-  **Service Availability**: > 99.9%
-  **Backup Integrity**: 100%

### Actual Results (Fill After Migration)

```markdown
## Actual Results

- Total Downtime: [X minutes]
- Data Loss: [X bytes]
- Migration Duration: [X days]
- Issues Encountered: [Number]
- Service Availability: [X%]
- Final Status: [Success/Partial/Failed]
```

---

## Post-Migration Tasks

**Week After Migration:**

- [ ] Monitor services daily
- [ ] Verify backup automation
- [ ] Update monitoring alerts
- [ ] Test Austria internet speeds
- [ ] Optimize for new network

**Month After Migration:**

- [ ] Monthly backup test
- [ ] Performance review
- [ ] Cost analysis (power, internet)
- [ ] Document long-term observations
- [ ] Update procedures based on learnings

---

## Additional Resources

- [DISASTER-RECOVERY.md](DISASTER-RECOVERY.md) - Recovery procedures
- [OPERATIONS.md](OPERATIONS.md) - Daily operations
- [TESTING.md](TESTING.md) - Testing procedures
- Main [README.md](../README.md) - Setup guide
