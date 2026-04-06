# Troubleshooting Guide

This document contains solutions to common issues encountered when running the homelab infrastructure.

## Table of Contents

- [DNS and Networking](#dns-and-networking)
- [Tailscale Issues](#tailscale-issues)
- [Docker and Container Issues](#docker-and-container-issues)
- [Ansible Deployment Issues](#ansible-deployment-issues)
- [SSL/TLS Certificate Issues](#ssltls-certificate-issues)
- [Service Access Issues](#service-access-issues)

---

## DNS and Networking

### Tailscale DNS Conflicts with systemd-resolved

**Symptom:**
- Tailscale health check shows DNS errors
- `/etc/resolv.conf` shows Tailscale DNS (100.100.100.100) but it's commented out
- DNS resolution is slow or fails intermittently
- `tailscale status` shows DNS warnings

**Root Cause:**
Tailscale tries to manage `/etc/resolv.conf` directly, but systemd-resolved on Ubuntu/Debian also wants to manage it. This creates a conflict where:
1. Tailscale overwrites `/etc/resolv.conf`
2. systemd-resolved's stub resolver (127.0.0.53) is bypassed
3. Tailscale DNS fails and falls back to public DNS
4. MagicDNS doesn't work properly

**Solution:**

The fix is to let systemd-resolved be the primary DNS manager and configure it to use Tailscale DNS as an upstream resolver.

```bash
# Stop tailscaled
sudo systemctl stop tailscaled

# Backup current resolv.conf
sudo cp /etc/resolv.conf /etc/resolv.conf.backup

# Remove Tailscale-managed resolv.conf
sudo rm /etc/resolv.conf

# Create symlink to systemd-resolved stub
sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

# Restart systemd-resolved
sudo systemctl restart systemd-resolved

# Start tailscaled and disable direct resolv.conf management
sudo systemctl start tailscaled
sudo tailscale set --accept-dns=false

# Verify the setup
cat /etc/resolv.conf        # Should show 127.0.0.53
resolvectl status           # Should show Tailscale DNS in the list
tailscale status            # Should not show DNS errors
```

**Verification:**

```bash
# Check resolv.conf points to systemd-resolved stub
cat /etc/resolv.conf
# Should show: nameserver 127.0.0.53

# Test DNS resolution
nslookup google.com
nslookup homelab-vpc.tailb99699.ts.net  # Replace with your Tailscale network name

# Check systemd-resolved status
resolvectl status
```

**Expected Result:**
- `/etc/resolv.conf` points to `127.0.0.53` (systemd-resolved stub)
- systemd-resolved uses Tailscale DNS (100.100.100.100) as primary
- Fallback to Quad9 (9.9.9.9) or Cloudflare (1.1.1.1) if Tailscale DNS fails
- No health check errors from Tailscale
- MagicDNS works properly for `.ts.net` domains

**Prevention:**
This fix is automatically applied by the bootstrap script on new nodes (version 2025-10-25 and later).

---

## Tailscale Issues

### Cannot Join Tailscale Network

**Symptom:**
```bash
sudo tailscale up --authkey=tskey-xxx
# Error: failed to connect to Tailscale
```

**Solutions:**

1. **Check firewall allows Tailscale ports:**
```bash
sudo ufw status
# Should show:
# 51820/udp    ALLOW       Anywhere
# 41641/udp    ALLOW       Anywhere

# If missing, add them:
sudo ufw allow 51820/udp
sudo ufw allow 41641/udp
```

2. **Check Tailscale service is running:**
```bash
sudo systemctl status tailscaled
# If not running:
sudo systemctl start tailscaled
sudo systemctl enable tailscaled
```

3. **Verify auth key is valid:**
- Auth keys expire (check Tailscale admin console)
- Reusable keys can be used multiple times
- Ephemeral keys are for temporary devices
- Generate new key if expired

4. **Check network connectivity:**
```bash
# Test internet connectivity
ping -c 3 8.8.8.8
ping -c 3 google.com

# Test Tailscale coordination server
curl https://controlplane.tailscale.com
```

### Tailscale Nodes Cannot Communicate

**Symptom:**
```bash
ping 100.x.x.x  # Tailscale IP of another node
# Request timeout or no route to host
```

**Solutions:**

1. **Check both nodes are online:**
```bash
tailscale status
# Should show both nodes with recent "last seen"
```

2. **Check subnet routing is enabled:**
```bash
# On both nodes
tailscale up --accept-routes
```

3. **Check Tailscale ACLs:**
- Visit Tailscale admin console → Access Controls
- Ensure nodes can communicate (default should allow all)

4. **Force reconnection:**
```bash
sudo tailscale down
sudo tailscale up --accept-routes --accept-dns
```

---

## Docker and Container Issues

### Container Fails to Start

**Symptom:**
```bash
docker ps -a
# Shows container with "Exited (1)" status
```

**Diagnosis:**

1. **Check container logs:**
```bash
docker logs <container-name>
# or
docker compose -f /opt/stacks/apps/compose.yml logs <service-name>
```

2. **Check environment variables:**
```bash
# Verify .env file exists and has correct values
cat /opt/stacks/apps/.env
# Look for "your-" placeholders (not replaced from secrets.env)
grep "your-" /opt/stacks/apps/.env
# Should return nothing
```

3. **Check volume permissions:**
```bash
# Check ownership of data directories
ls -la /opt/appdata/
# Should be owned by homelab user or correct PUID/PGID
```

4. **Check port conflicts:**
```bash
# See what's using the port
sudo netstat -tlnp | grep <port-number>
# or
sudo ss -tlnp | grep <port-number>
```

**Common Fixes:**

1. **Recreate container:**
```bash
cd /opt/stacks/apps
docker compose down <service-name>
docker compose up -d <service-name>
```

2. **Fix permissions:**
```bash
sudo chown -R 1000:1000 /opt/appdata/<service-name>
```

3. **Clear and recreate:**
```bash
docker compose down <service-name>
docker compose rm -f <service-name>
docker volume rm <volume-name>  # WARNING: Deletes data!
docker compose up -d <service-name>
```

### Docker Out of Disk Space

**Symptom:**
```bash
docker: no space left on device
```

**Solutions:**

1. **Check disk usage:**
```bash
df -h
docker system df
```

2. **Clean up Docker resources:**
```bash
# Remove stopped containers
docker container prune -f

# Remove unused images
docker image prune -a -f

# Remove unused volumes (WARNING: May delete data!)
docker volume prune -f

# Remove everything unused (aggressive cleanup)
docker system prune -a --volumes -f
```

3. **Check log file sizes:**
```bash
# Docker logs can grow large
du -sh /var/lib/docker/containers/*/*-json.log

# Configure log rotation in /etc/docker/daemon.json:
cat << EOF | sudo tee /etc/docker/daemon.json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF

sudo systemctl restart docker
```

---

## Ansible Deployment Issues

### "Failed to connect to the host via ssh"

**Symptom:**
```bash
make deploy-apps target=rpi-home
# Error: Failed to connect to the host via ssh
```

**Solutions:**

1. **Test SSH connectivity:**
```bash
ssh homelab@ub-house-green  # Using Tailscale MagicDNS
# or
ssh homelab@100.x.x.x  # Using Tailscale IP
```

2. **Check SSH key is loaded:**
```bash
ssh-add -l
# Should show your ed25519 key

# If not loaded:
ssh-add ~/.ssh/id_ed25519
```

3. **Test Ansible ping:**
```bash
ansible rpi-home -i inventory/hosts.ini -m ping --ask-vault-pass
```

4. **Check inventory file:**
```bash
cat inventory/hosts.ini
# Verify ansible_host is correct (Tailscale IP or MagicDNS hostname)
```

5. **Increase SSH timeout:**
```bash
# Add to ansible.cfg or set environment variable:
export ANSIBLE_SSH_TIMEOUT=30
```

### "Incorrect sudo password"

**Symptom:**
```bash
ansible-playbook ansible/site.yml --ask-vault-pass
# Error: Incorrect sudo password
```

**Solutions:**

1. **Verify Vault password:**
```bash
# Test decryption
ansible-vault view inventory/group_vars/rpi_nodes.yml
# Should show decrypted ansible_sudo_pass
```

2. **Check sudo password is correct:**
```bash
# SSH to node and test sudo
ssh homelab@rpi-home
sudo -k  # Clear cached sudo password
sudo whoami  # Should prompt for password
# Use the password from ansible_sudo_pass
```

3. **Re-encrypt sudo password:**
```bash
# Generate new encrypted password
echo 'ansible_sudo_pass: YOUR_ACTUAL_PASSWORD' | ansible-vault encrypt_string --stdin-name 'ansible_sudo_pass'

# Update inventory/group_vars/rpi_nodes.yml with new encrypted value
```

---

## SSL/TLS Certificate Issues

### Let's Encrypt Rate Limit Exceeded

**Symptom:**
```bash
docker logs traefik
# Error: too many certificates already issued for exact set of domains
```

**Explanation:**
Let's Encrypt limits certificates to:
- 5 certificates per week for the same domain
- 50 certificates per week per account

**Solutions:**

1. **Wait for rate limit to reset:**
   - Rate limits reset after 7 days
   - Check status: https://crt.sh/?q=yourdomain.com

2. **Use staging server for testing:**
```yaml
# In stacks/cloud/traefik/traefik.yml
certificatesResolvers:
  cloudflare:
    acme:
      email: 'your-email@example.com'
      storage: /acme/acme.json
      caServer: https://acme-staging-v02.api.letsencrypt.org/directory  # Add this line
      dnsChallenge:
        provider: cloudflare
```

3. **Use wildcard certificate:**
   - Already configured in your setup (*.yourdomain.com)
   - Reduces certificate count to 1 per domain

### Cloudflare DNS Challenge Fails

**Symptom:**
```bash
docker logs traefik
# Error: cloudflare: failed to obtain certificate
```

**Solutions:**

1. **Verify API token permissions:**
   - Go to Cloudflare Dashboard → My Profile → API Tokens
   - Token needs: Zone / DNS / Edit permission
   - Must be scoped to your specific domain

2. **Test API token:**
```bash
# SSH to cloud node
ssh homelab@cloud-node

# Test token (replace with your token and zone ID)
curl -X GET "https://api.cloudflare.com/client/v4/zones/YOUR_ZONE_ID/dns_records" \
  -H "Authorization: Bearer YOUR_CF_DNS_API_TOKEN" \
  -H "Content-Type: application/json"
```

3. **Check token is set correctly:**
```bash
ssh homelab@cloud-node
cat /opt/stacks/cloud/.env | grep CF_DNS_API_TOKEN
# Should show your actual token, not "your-cloudflare-api-token"
```

4. **Regenerate token:**
   - Create new API token in Cloudflare
   - Update env/secrets.env
   - Redeploy cloud stack

---

## Service Access Issues

### "503 Service Unavailable" from Traefik

**Symptom:**
Visiting https://mealie.yourdomain.com returns 503 error

**Solutions:**

1. **Check backend service is running:**
```bash
# On RPi-Home
ssh homelab@rpi-home
docker ps | grep mealie
# Should show container running
```

2. **Check Traefik can reach backend:**
```bash
# On cloud node
ssh homelab@cloud-node

# Test connectivity to RPi over Tailscale
curl -I http://RPI_TAILSCALE_IP:9925
# Should return HTTP 200 or 302
```

3. **Check Traefik configuration:**
```bash
ssh homelab@cloud-node
docker logs traefik | grep -i error
docker logs traefik | grep mealie
```

4. **Verify RPI_HOME_IP in .env:**
```bash
ssh homelab@cloud-node
cat /opt/stacks/cloud/.env | grep RPI_HOME_IP
# Should match RPi's Tailscale IP
```

5. **Check Traefik dashboard:**
   - Visit: https://traefik.yourdomain.com
   - Look at HTTP → Routers → mealie
   - Check service status and backend health

### Cannot Access Service via Tailscale

**Symptom:**
```bash
curl http://100.x.x.x:9925  # RPi Tailscale IP
# Connection refused or timeout
```

**Solutions:**

1. **Check service is listening:**
```bash
ssh homelab@rpi-home
docker ps | grep mealie
netstat -tlnp | grep 9925
# Should show 0.0.0.0:9925 or specific IP
```

2. **Check firewall (UFW):**
```bash
ssh homelab@rpi-home
sudo ufw status
# Should allow Tailscale subnet (100.64.0.0/10)
```

3. **Check if binding to localhost only:**
```bash
# Check compose file
cat /opt/stacks/apps/compose.yml | grep -A 2 "9925"
# If shows 127.0.0.1:9925 - only accessible locally
# Change to 0.0.0.0:9925 for Tailscale access
```

---

## Getting Help

If these solutions don't resolve your issue:

1. **Check service-specific logs:**
```bash
docker logs <container-name> --tail=100
```

2. **Check system logs:**
```bash
journalctl -u docker -n 100
journalctl -u tailscaled -n 100
```

3. **Gather diagnostic info:**
```bash
# System info
df -h
free -h
docker system df
tailscale status

# Service status
docker ps -a
systemctl status docker tailscaled
```

4. **Create an issue:**
   - Include error messages
   - Include relevant logs
   - Include steps to reproduce
   - Include system information (OS, Docker version, etc.)

---

**Last Updated:** 2025-10-25
