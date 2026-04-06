# Traefik HTTPS Setup Guide

Complete guide to deploying Traefik reverse proxy with automatic HTTPS using Cloudflare DNS challenge.

## Overview

This setup provides:
-  **Public HTTPS access** to your homelab services via custom domain
-  **Automatic SSL certificates** from Let's Encrypt (via Cloudflare DNS challenge)
-  **SSO authentication** via Authentik for all services
-  **Monitoring** with Uptime Kuma
-  **Secure routing** from cloud VM → Tailscale VPN → RPi services

**Architecture:**
```
Internet → yourdomain.com (Cloudflare DNS)
    ↓
Cloud VM Public IP (Traefik + Let's Encrypt HTTPS)
    ↓
Tailscale VPN mesh
    ↓
RPi-Home (Services: Mealie, Wallos, etc.)
```

**Monthly Cost:** ~$5-10 for cloud VM

---

## Prerequisites

Before starting, ensure you have:

-  Domain name registered (any registrar: Namecheap, Google Domains, etc.)
-  Domain DNS managed by Cloudflare (free account)
-  Cloud VM running (Linode, DigitalOcean, Vultr, etc.)
-  Cloud VM bootstrapped and joined to Tailscale
-  RPi-Home services running and accessible via Tailscale
-  Ansible working (can ping cloud-node)

**Check prerequisites:**
```bash
# Test Ansible connectivity
ansible cloud-node -i inventory/hosts.ini -m ping --ask-vault-pass

# Verify RPi services are running
ssh homelab@rpi-home "docker ps"

# Verify cloud VM can reach RPi via Tailscale
ssh homelab@cloud-node "ping -c 3 ub-house-green"
```

---

## Step 1: Transfer Domain to Cloudflare

If your domain is not already on Cloudflare:

1. **Sign up for Cloudflare** (free): https://dash.cloudflare.com/sign-up
2. **Add your domain** to Cloudflare:
   - Dashboard → Add a Site → Enter your domain
   - Select Free plan
3. **Update nameservers** at your domain registrar:
   - Cloudflare will provide 2 nameservers (e.g., `adam.ns.cloudflare.com`)
   - Go to your domain registrar (Namecheap, GoDaddy, etc.)
   - Update nameservers to Cloudflare's nameservers
   - Wait 5-60 minutes for propagation
4. **Verify domain is active** on Cloudflare:
   - Dashboard should show "Active" status
   - Test: `dig yourdomain.com` should show Cloudflare nameservers

---

## Step 2: Configure Cloudflare DNS

Add DNS records pointing to your cloud VM:

1. **Get cloud VM public IP:**
```bash
# SSH to cloud VM and get public IP
ssh homelab@cloud-node "curl -s ifconfig.me"
# Example output: 45.79.123.45
```

2. **Add DNS records in Cloudflare:**
   - Go to: Dashboard → Your Domain → DNS → Records
   - Add these A records:

| Type | Name | Content (IPv4)      | Proxy | TTL  |
|------|------|---------------------|-------|------|
| A    | @    | 45.79.123.45        |  Proxied | Auto |
| A    | *    | 45.79.123.45        |  Proxied | Auto |

**Proxy Status:**
- ** Proxied (Orange Cloud)**: Cloudflare hides your real IP, provides DDoS protection, CDN
- ** DNS Only (Gray Cloud)**: Direct connection to your VM

**Recommendation:** Use Proxied for better security and DDoS protection.

3. **Verify DNS propagation:**
```bash
# Test root domain
dig yourdomain.com +short
# Should show Cloudflare proxy IPs (not your VM IP if proxied)

# Test wildcard subdomain
dig mealie.yourdomain.com +short
# Should resolve to same IP

# Wait 2-5 minutes if not resolving yet
```

---

## Step 3: Create Cloudflare API Token

Traefik needs an API token to complete the DNS challenge for SSL certificates.

1. **Go to Cloudflare API Tokens:**
   - Visit: https://dash.cloudflare.com/profile/api-tokens
   - Click **Create Token**

2. **Use "Edit zone DNS" template:**
   - Click **Use template** next to "Edit zone DNS"

3. **Configure permissions:**
   ```
   Permissions:
   - Zone / DNS / Edit

   Zone Resources:
   - Include / Specific zone / yourdomain.com

   Client IP Address Filtering: (leave empty)
   TTL: (leave default or set expiration)
   ```

4. **Create token and copy it:**
   - Click **Continue to summary** → **Create Token**
   - ** IMPORTANT:** Copy the token NOW - you won't see it again!
   - Example: `Qx7sM9dK3nP8hJ2fA5bC1vR6wT4yE0oL`

5. **Test the token:**
```bash
# Get your Zone ID from Cloudflare dashboard (Overview page)
# Replace YOUR_ZONE_ID and YOUR_TOKEN with your values

curl -X GET "https://api.cloudflare.com/client/v4/zones/YOUR_ZONE_ID/dns_records" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json"

# Should return JSON with your DNS records (not an error)
```

---

## Step 4: Configure Environment Secrets

Update your `env/secrets.env` file with the required values.

1. **Get RPi-Home Tailscale IP:**
```bash
ssh homelab@rpi-home "tailscale ip -4"
# Example output: 100.88.245.35
```

2. **Edit secrets.env:**
```bash
# On your local machine
nano env/secrets.env
```

3. **Add/update these variables:**
```bash
# Domain & DNS Configuration
DOMAIN=yourdomain.com                          # Replace with your actual domain
ACME_EMAIL=you@example.com                     # Your email for Let's Encrypt
CF_DNS_API_TOKEN=Qx7sM9dK3nP8hJ2fA5bC1vR6wT4yE0oL  # Cloudflare API token from Step 3
RPI_HOME_IP=100.88.245.35                      # RPi-Home Tailscale IP from above

# Authentik Configuration (generate strong passwords)
AUTHENTIK_SECRET_KEY=$(openssl rand -base64 32)
AUTHENTIK_DB_PASSWORD=$(openssl rand -base64 32)
```

4. **Generate Authentik secrets:**
```bash
# Generate random secure keys
openssl rand -base64 32
# Example output: 8x3mK9jL2pN7vR4wQ5tY6uH1sD0fG3zA

# Copy the output and paste into secrets.env for AUTHENTIK_SECRET_KEY
# Run again for AUTHENTIK_DB_PASSWORD
```

5. **Verify no placeholders remain:**
```bash
grep "your-" env/secrets.env
# Should return nothing (no matches)

grep "yourdomain.com" env/secrets.env
# Should only show your actual domain
```

---

## Step 5: Deploy Cloud Stack

Now deploy Traefik, Authentik, and Uptime Kuma to your cloud VM.

1. **Validate configuration:**
```bash
make validate
# Should pass all checks
```

2. **Deploy cloud stack:**
```bash
make deploy-cloud
```

This will:
- Copy environment files to cloud-node
- Deploy Traefik reverse proxy
- Deploy Authentik SSO (with PostgreSQL + Redis)
- Deploy Uptime Kuma monitoring
- Start all services

3. **Monitor deployment:**
```bash
# Watch container startup
ssh homelab@cloud-node "watch docker ps"

# Check logs if any issues
ssh homelab@cloud-node "docker logs traefik"
ssh homelab@cloud-node "docker logs authentik"
```

4. **Wait for services to be ready:**
```bash
# All containers should show "Up" status
ssh homelab@cloud-node "docker ps --format 'table {{.Names}}\t{{.Status}}'"

# Expected output:
# NAMES               STATUS
# traefik             Up X minutes
# authentik           Up X minutes
# authentik-worker    Up X minutes
# authentik-db        Up X minutes
# authentik-redis     Up X minutes
# uptime-kuma         Up X minutes
```

---

## Step 6: Verify HTTPS Certificates

Traefik should automatically request SSL certificates from Let's Encrypt.

1. **Check Traefik logs for certificate acquisition:**
```bash
ssh homelab@cloud-node "docker logs traefik | grep -i acme"
# Look for: "Certificate obtained for domain"
```

2. **Verify ACME storage:**
```bash
ssh homelab@cloud-node "docker exec traefik cat /acme/acme.json | jq '.cloudflare.Certificates | length'"
# Should show number > 0 (certificates exist)
```

3. **Test HTTPS access:**
```bash
# Test Traefik dashboard
curl -I https://traefik.yourdomain.com
# Should return: HTTP/2 200 or HTTP/2 302

# Test Authentik
curl -I https://auth.yourdomain.com
# Should return: HTTP/2 200 or HTTP/2 302

# Test a proxied service
curl -I https://mealie.yourdomain.com
# Should return: HTTP/2 302 (redirect to Authentik login)
```

4. **Check certificate in browser:**
   - Visit: https://traefik.yourdomain.com
   - Click padlock icon → Certificate details
   - Should show: Issued by "R3" or "E1" (Let's Encrypt)
   - Valid for 90 days (auto-renews at 60 days)

---

## Step 7: Configure Authentik SSO

Set up Authentik to provide authentication for all services.

1. **Access Authentik setup wizard:**
   - Visit: https://auth.yourdomain.com/if/flow/initial-setup/
   - Should see "Welcome to authentik" setup page

2. **Create admin account:**
   - Email: your-email@example.com
   - Username: admin
   - Password: (set a strong password)
   - Click **Create**

3. **Configure Traefik Forward Auth (for proxy integration):**

   a. **Create Proxy Provider:**
   - Flows & Stages → Providers → Create → Proxy Provider
   - Name: `Traefik Forward Auth`
   - Authorization flow: `default-provider-authorization-implicit-consent`
   - Type: **Forward auth (single application)**
   - External host: `https://traefik.yourdomain.com`
   - Click **Create**

   b. **Create Application:**
   - Applications → Create
   - Name: `Traefik`
   - Slug: `traefik`
   - Provider: `Traefik Forward Auth`
   - Click **Create**

   c. **Create Outpost:**
   - Outposts → Create
   - Name: `Traefik Outpost`
   - Type: `Proxy`
   - Applications: Select `Traefik` application
   - Click **Create**

4. **Configure applications for each service:**

Repeat for each service (Mealie, Wallos, etc.):

   a. Create Proxy Provider:
   - Name: `Mealie`
   - Authorization flow: `default-provider-authorization-implicit-consent`
   - Type: **Forward auth (single application)**
   - External host: `https://mealie.yourdomain.com`

   b. Create Application:
   - Name: `Mealie`
   - Slug: `mealie`
   - Provider: Select the provider you just created
   - Launch URL: `https://mealie.yourdomain.com`

   c. Add to Outpost:
   - Outposts → Traefik Outpost → Edit
   - Add new application to the list

5. **Verify authentication works:**
   - Visit: https://mealie.yourdomain.com
   - Should redirect to Authentik login
   - Login with admin credentials
   - Should redirect back to Mealie

**Detailed Authentik setup:** https://goauthentik.io/integrations/services/traefik/

---

## Step 8: Set Up Monitoring

Configure Uptime Kuma to monitor all your services.

1. **Access Uptime Kuma:**
   - Visit: https://status.yourdomain.com
   - First visit will prompt to create admin account
   - Set username and password

2. **Add monitors for each service:**
   - Click **Add New Monitor**
   - For each service:
     ```
     Monitor Type: HTTP(s)
     Friendly Name: Mealie
     URL: https://mealie.yourdomain.com
     Heartbeat Interval: 60 seconds
     Retries: 3
     ```

3. **Create status page (optional):**
   - Status Pages → Add Status Page
   - Name: Homelab Services
   - Select which monitors to display
   - Can be public or password-protected

---

## Step 9: Test Access

Verify everything works from outside your network (without Tailscale).

1. **Disconnect from Tailscale:**
```bash
sudo tailscale down
```

2. **Test each service via browser:**
   - https://traefik.yourdomain.com → Traefik dashboard
   - https://auth.yourdomain.com → Authentik login
   - https://mealie.yourdomain.com → Should redirect to Authentik → Mealie
   - https://wallos.yourdomain.com → Should redirect to Authentik → Wallos
   - https://pdf.yourdomain.com → Should redirect to Authentik → Sterling PDF
   - https://search.yourdomain.com → Should redirect to Authentik → SearXNG
   - https://code.yourdomain.com → Should redirect to Authentik → VS Code Server
   - https://chat.yourdomain.com → Should redirect to Authentik → Open WebUI
   - https://books.yourdomain.com → Should redirect to Authentik → Audiobookshelf
   - https://n8n.yourdomain.com → Should redirect to Authentik → n8n
   - https://status.yourdomain.com → Uptime Kuma (protected by Authentik)

3. **Reconnect to Tailscale:**
```bash
sudo tailscale up
```

4. **Check SSL certificates:**
   - All services should have valid SSL certificates
   - Browser should show padlock icon
   - No certificate warnings

---

## Troubleshooting

### DNS Not Resolving

**Problem:** `dig mealie.yourdomain.com` returns NXDOMAIN

**Solution:**
```bash
# Check Cloudflare DNS records are created
# Visit: https://dash.cloudflare.com → Your Domain → DNS

# Verify nameservers
dig yourdomain.com NS
# Should show Cloudflare nameservers

# Wait 5-10 minutes for propagation
# Test again with: dig mealie.yourdomain.com +short
```

### Certificate Errors

**Problem:** Traefik logs show "cloudflare: failed to obtain certificate"

**Solutions:**

1. **Check API token permissions:**
```bash
# Test token
curl -X GET "https://api.cloudflare.com/client/v4/zones/YOUR_ZONE_ID/dns_records" \
  -H "Authorization: Bearer YOUR_CF_DNS_API_TOKEN"

# Should return JSON, not error
```

2. **Verify token in environment:**
```bash
ssh homelab@cloud-node "cat /opt/stacks/cloud/.env | grep CF_DNS_API_TOKEN"
# Should show actual token, not placeholder
```

3. **Check rate limits:**
```bash
# Let's Encrypt limits: 5 certs/week per domain
# Check certificate transparency logs: https://crt.sh/?q=yourdomain.com
# If hit limit, wait or use staging server for testing
```

4. **Use staging server for testing:**
```bash
# Edit stacks/cloud/traefik/traefik.yml
# Add caServer line:
certificatesResolvers:
  cloudflare:
    acme:
      email: 'your-email'
      caServer: https://acme-staging-v02.api.letsencrypt.org/directory  # Add this
      storage: /acme/acme.json
      dnsChallenge:
        provider: cloudflare

# Redeploy
make deploy-cloud
```

### 503 Service Unavailable

**Problem:** Visiting https://mealie.yourdomain.com returns 503 error

**Solutions:**

1. **Check RPi service is running:**
```bash
ssh homelab@rpi-home "docker ps | grep mealie"
# Should show container running
```

2. **Verify Tailscale connectivity:**
```bash
# From cloud VM to RPi
ssh homelab@cloud-node "curl -I http://100.88.245.35:9925"
# Should return HTTP 200 or 302
```

3. **Check Traefik backend health:**
```bash
# View Traefik logs
ssh homelab@cloud-node "docker logs traefik | grep mealie"

# Check backend configuration
ssh homelab@cloud-node "docker exec traefik cat /config/dynamic.yml | grep -A 5 mealie-svc"
```

4. **Verify RPI_HOME_IP is correct:**
```bash
ssh homelab@cloud-node "cat /opt/stacks/cloud/.env | grep RPI_HOME_IP"
# Should match: ssh homelab@rpi-home "tailscale ip -4"
```

### Authentik Login Loop

**Problem:** After logging into Authentik, redirects back to login

**Solutions:**

1. **Check Authentik configuration:**
```bash
# View Authentik logs
ssh homelab@cloud-node "docker logs authentik"

# Common issue: Forward Auth not configured correctly
# Revisit Step 7 and ensure Outpost is created and running
```

2. **Verify Authentik outpost:**
```bash
# Check Authentik admin panel
# Visit: https://auth.yourdomain.com/if/admin/#/outpost/outposts
# Traefik Outpost should show "Healthy" status
```

3. **Check service configuration:**
```bash
# Verify dynamic.yml has authentik middleware
ssh homelab@cloud-node "cat /opt/stacks/cloud/traefik/config/dynamic.yml | grep -A 5 'authentik:'"
```

### Firewall Blocking Ports

**Problem:** Cannot access cloud VM at all

**Solutions:**

1. **Check UFW on cloud VM:**
```bash
ssh homelab@cloud-node "sudo ufw status"
# Should show:
# 80/tcp     ALLOW       Anywhere
# 443/tcp    ALLOW       Anywhere
```

2. **Add firewall rules if missing:**
```bash
ssh homelab@cloud-node "sudo ufw allow 80/tcp"
ssh homelab@cloud-node "sudo ufw allow 443/tcp"
ssh homelab@cloud-node "sudo ufw reload"
```

3. **Check cloud provider firewall:**
   - Linode: Cloud Firewalls
   - DigitalOcean: Networking → Firewalls
   - Vultr: Firewall settings
   - Ensure ports 80 and 443 are allowed

---

## Maintenance

### Update Services

```bash
# Update all cloud services
make update-images

# Or manually
ssh homelab@cloud-node "cd /opt/stacks/cloud && docker compose pull && docker compose up -d"
```

### View Logs

```bash
# Traefik logs
ssh homelab@cloud-node "docker logs -f traefik"

# Authentik logs
ssh homelab@cloud-node "docker logs -f authentik"

# All services
ssh homelab@cloud-node "cd /opt/stacks/cloud && docker compose logs -f"
```

### Backup Certificates

```bash
# ACME certificates are stored in Docker volume: traefik_acme
# They auto-renew, but good to backup:

ssh homelab@cloud-node "docker exec traefik cat /acme/acme.json > /tmp/acme-backup.json"
scp homelab@cloud-node:/tmp/acme-backup.json ./backups/
```

### Renew Certificates (Manual)

```bash
# Certificates auto-renew at 60 days (90-day validity)
# To force renewal (if needed):

ssh homelab@cloud-node "docker exec traefik rm /acme/acme.json"
ssh homelab@cloud-node "cd /opt/stacks/cloud && docker compose restart traefik"

# Watch logs for new certificate request
ssh homelab@cloud-node "docker logs -f traefik | grep -i acme"
```

---

## Security Best Practices

1. **Enable 2FA in Authentik:**
   - Settings → Stages → Create → Authenticator Validation
   - Add to authentication flow

2. **Use strong passwords:**
   - Authentik admin account
   - Uptime Kuma admin account
   - Code Server password

3. **Regular updates:**
```bash
# Update Docker images monthly
make update-images

# Update system packages
ssh homelab@cloud-node "sudo apt update && sudo apt upgrade -y"
```

4. **Monitor logs:**
```bash
# Check for suspicious activity
ssh homelab@cloud-node "docker logs traefik | grep -i 'error\|fail'"
```

5. **Rate limiting:**
   - Already configured in `stacks/cloud/traefik/config/dynamic.yml`
   - Limits: 100 requests/minute average, 50 burst

6. **Backup regularly:**
   - ACME certificates
   - Authentik database
   - Uptime Kuma configuration

---

## Next Steps

- **Add more services** to dynamic.yml as you deploy them
- **Configure Authentik groups** for granular access control
- **Set up email notifications** in Uptime Kuma
- **Enable Cloudflare WAF rules** for additional security
- **Configure backup automation** for cloud-node

---

## Additional Resources

- Traefik Documentation: https://doc.traefik.io/traefik/
- Authentik Documentation: https://goauthentik.io/docs/
- Cloudflare API Docs: https://developers.cloudflare.com/api/
- Let's Encrypt: https://letsencrypt.org/docs/
- Uptime Kuma: https://github.com/louislam/uptime-kuma

---

**Last Updated:** 2025-10-25
