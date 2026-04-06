#  Optional: Adding Cloud Edge Proxy

This guide explains how to add a cloud-based edge proxy (Traefik + Authentik) for public internet access to your services.

---

## Overview

**Current Setup:** Tailscale-only access (recommended for security)

-  More secure (no public exposure)
-  Simpler setup
-  No cloud VM costs
-  Requires Tailscale client to access

**With Cloud Proxy:** Public internet access via domain

-  Access from anywhere (no Tailscale needed)
-  Share with users who don't have Tailscale
-  Professional URLs (freshrss.yourdomain.com)
-  More complex setup
-  Monthly cloud VM cost (~$5-10)
-  Additional security considerations

---

## When to Add Cloud Proxy

**Good reasons:**

- You want to access services from devices without Tailscale (work laptop, friends' devices)
- You want custom domain URLs
- You want to share specific services publicly (with authentication)
- You're comfortable with additional security complexity

**Keep Tailscale-only if:**

- You only access from your own devices
- Security is your top priority
- You want to minimize costs
- You prefer simplicity

---

## Architecture with Cloud Proxy

```
                    Internet
                       │
                       │ (Public HTTPS)
                       ↓
              ┌────────────────┐
              │   Cloud VM     │
              │  (Linode/DO)   │
              │                │
              │  - Traefik     │ ← Reverse proxy (routes traffic)
              │  - Authentik   │ ← SSO/authentication
              │  - Uptime Kuma │ ← Monitoring
              └────────┬───────┘
                       │
                       │ (Tailscale VPN)
                       ↓
         ┌─────────────┴──────────────┐
         │                            │
    ┌────┴─────┐                 ┌───┴──────┐
    │ RPi-Home │                 │RPi-Friend│
    │          │                 │          │
    │ Services │                 │ Services │
    └──────────┘                 └──────────┘
```

**How it works:**

1. User visits `freshrss.yourdomain.com`
2. DNS points to cloud VM public IP
3. Traefik (on cloud VM) receives request
4. Authentik authenticates user
5. Traefik forwards request via Tailscale to RPi-Home
6. Response flows back through same path

---

## Prerequisites

Before adding cloud proxy:

-  Current homelab working (RPi-Home + RPi-Friend)
-  Domain name registered (e.g., yourdomain.com)
-  Cloud provider account (Linode, DigitalOcean, Vultr, etc.)
-  Comfortable with Docker Compose
-  Basic understanding of reverse proxies

**Estimated Setup Time:** 2-3 hours

**Monthly Cost:** $5-10 (1GB RAM VPS is sufficient)

---

## Setup Steps

### Step 1: Create Cloud VM

**Recommended Specs:**

- **RAM:** 1-2GB
- **CPU:** 1 core
- **Disk:** 25GB
- **OS:** Ubuntu 22.04 LTS
- **Location:** Close to you for lower latency

**Providers:**

- Linode: $5/month (Nanode 1GB)
- DigitalOcean: $6/month (Basic Droplet)
- Vultr: $5/month (Cloud Compute)
- Hetzner: €4.5/month (CX11)

### Step 2: Bootstrap Cloud VM

```bash
# SSH to cloud VM (use initial IP from provider)
ssh root@<cloud-vm-ip>

# Copy bootstrap script
scp scripts/bootstrap.sh root@<cloud-vm-ip>:/tmp/

# Run bootstrap
ssh root@<cloud-vm-ip>
sudo bash /tmp/bootstrap.sh Europe/Vienna root
```

### Step 3: Join Tailscale Network

```bash
# On cloud VM
ssh homelab@<cloud-vm-ip>
sudo tailscale up --ssh --accept-routes --authkey=tskey-auth-XXXXX

# Get Tailscale IP
tailscale ip -4
# Note this IP (e.g., 100.101.102.200)
```

### Step 4: Update Inventory

```bash
# On management machine
nano inventory/hosts.ini
```

Add:

```ini
[cloud_nodes]
cloud-vm ansible_host=100.101.102.200 # Tailscale IP
```

Test:

```bash
ansible cloud-vm -i inventory/hosts.ini -m ping
```

### Step 5: Configure Domain DNS

**In your domain registrar:**

Create A records pointing to cloud VM public IP:

```
A    @                   -> <cloud-vm-public-ip>
A    *.                  -> <cloud-vm-public-ip>
```

This allows:

- `yourdomain.com` → cloud VM
- `freshrss.yourdomain.com` → cloud VM
- `mealie.yourdomain.com` → cloud VM
- etc.

**Verify DNS:**

```bash
dig freshrss.yourdomain.com
# Should show cloud VM public IP
```

### Step 6: Create Cloud Stack

Create `stacks/cloud/compose.yml`:

```yaml
version: '3.8'

services:
  traefik:
    image: traefik:v3.0
    container_name: traefik
    restart: unless-stopped
    ports:
      - '80:80'
      - '443:443'
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./traefik.yml:/etc/traefik/traefik.yml:ro
      - ./dynamic:/etc/traefik/dynamic:ro
      - traefik_acme:/acme
    environment:
      - DOMAIN=${DOMAIN}
    networks:
      - proxy

  authentik-server:
    image: ghcr.io/goauthentik/server:latest
    container_name: authentik
    restart: unless-stopped
    command: server
    environment:
      AUTHENTIK_SECRET_KEY: ${AUTHENTIK_SECRET_KEY}
      AUTHENTIK_ERROR_REPORTING__ENABLED: 'false'
      AUTHENTIK_POSTGRESQL__HOST: authentik-db
      AUTHENTIK_POSTGRESQL__NAME: authentik
      AUTHENTIK_POSTGRESQL__USER: authentik
      AUTHENTIK_POSTGRESQL__PASSWORD: ${AUTHENTIK_DB_PASSWORD}
    volumes:
      - authentik_media:/media
      - authentik_templates:/templates
    depends_on:
      - authentik-db
    networks:
      - proxy
    labels:
      - 'traefik.enable=true'
      - 'traefik.http.routers.authentik.rule=Host(`auth.${DOMAIN}`)'
      - 'traefik.http.routers.authentik.entrypoints=websecure'
      - 'traefik.http.routers.authentik.tls.certresolver=letsencrypt'
      - 'traefik.http.services.authentik.loadbalancer.server.port=9000'

  authentik-worker:
    image: ghcr.io/goauthentik/server:latest
    container_name: authentik-worker
    restart: unless-stopped
    command: worker
    environment:
      AUTHENTIK_SECRET_KEY: ${AUTHENTIK_SECRET_KEY}
      AUTHENTIK_ERROR_REPORTING__ENABLED: 'false'
      AUTHENTIK_POSTGRESQL__HOST: authentik-db
      AUTHENTIK_POSTGRESQL__NAME: authentik
      AUTHENTIK_POSTGRESQL__USER: authentik
      AUTHENTIK_POSTGRESQL__PASSWORD: ${AUTHENTIK_DB_PASSWORD}
    volumes:
      - authentik_media:/media
      - authentik_templates:/templates
    depends_on:
      - authentik-db
    networks:
      - proxy

  authentik-db:
    image: postgres:15-alpine
    container_name: authentik-db
    restart: unless-stopped
    environment:
      POSTGRES_DB: authentik
      POSTGRES_USER: authentik
      POSTGRES_PASSWORD: ${AUTHENTIK_DB_PASSWORD}
    volumes:
      - authentik_db:/var/lib/postgresql/data
    networks:
      - proxy

  uptime-kuma:
    image: louislam/uptime-kuma:latest
    container_name: uptime-kuma
    restart: unless-stopped
    volumes:
      - uptime_kuma:/app/data
    networks:
      - proxy
    labels:
      - 'traefik.enable=true'
      - 'traefik.http.routers.kuma.rule=Host(`status.${DOMAIN}`)'
      - 'traefik.http.routers.kuma.entrypoints=websecure'
      - 'traefik.http.routers.kuma.tls.certresolver=letsencrypt'
      - 'traefik.http.services.kuma.loadbalancer.server.port=3001'

volumes:
  traefik_acme:
  authentik_db:
  authentik_media:
  authentik_templates:
  uptime_kuma:

networks:
  proxy:
    name: proxy
```

### Step 7: Configure Traefik

Create `stacks/cloud/traefik.yml`:

```yaml
global:
  checkNewVersion: false
  sendAnonymousUsage: false

api:
  dashboard: true
  insecure: false

entryPoints:
  web:
    address: ':80'
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https

  websecure:
    address: ':443'
    http:
      tls:
        certResolver: letsencrypt

certificatesResolvers:
  letsencrypt:
    acme:
      email: your-email@example.com
      storage: /acme/acme.json
      httpChallenge:
        entryPoint: web

providers:
  docker:
    endpoint: 'unix:///var/run/docker.sock'
    exposedByDefault: false
  file:
    directory: /etc/traefik/dynamic
    watch: true

log:
  level: INFO
```

### Step 8: Create Dynamic Configuration

Create `stacks/cloud/dynamic/rpi-services.yml`:

```yaml
http:
  routers:
    freshrss:
      rule: 'Host(`freshrss.yourdomain.com`)'
      entryPoints:
        - websecure
      service: freshrss-svc
      middlewares:
        - authentik
      tls:
        certResolver: letsencrypt

    mealie:
      rule: 'Host(`mealie.yourdomain.com`)'
      entryPoints:
        - websecure
      service: mealie-svc
      middlewares:
        - authentik
      tls:
        certResolver: letsencrypt

  services:
    freshrss-svc:
      loadBalancer:
        servers:
          - url: 'http://100.88.245.35:8081' # RPi-Home Tailscale IP

    mealie-svc:
      loadBalancer:
        servers:
          - url: 'http://100.88.245.35:9925' # RPi-Home Tailscale IP

  middlewares:
    authentik:
      forwardAuth:
        address: 'http://authentik:9000/outpost.goauthentik.io/auth/traefik'
        trustForwardHeader: true
        authResponseHeaders:
          - 'X-authentik-username'
          - 'X-authentik-groups'
          - 'X-authentik-email'
```

### Step 9: Deploy Cloud Stack

```bash
# Create secrets
cat >> env/secrets.env << EOF
DOMAIN=yourdomain.com
AUTHENTIK_SECRET_KEY=$(openssl rand -base64 32)
AUTHENTIK_DB_PASSWORD=$(openssl rand -base64 32)
EOF

# Deploy to cloud VM
ssh homelab@cloud-vm "mkdir -p /opt/stacks/cloud"
scp -r stacks/cloud/* homelab@cloud-vm:/opt/stacks/cloud/
scp env/secrets.env homelab@cloud-vm:/opt/stacks/cloud/.env

# Start services
ssh homelab@cloud-vm "cd /opt/stacks/cloud && docker compose up -d"
```

### Step 10: Configure Authentik

1. Visit `https://auth.yourdomain.com`
2. Complete initial setup wizard
3. Create admin account
4. Create application for each service
5. Create outpost for Traefik
6. Configure users and groups

**Detailed Authentik setup:** https://goauthentik.io/docs/

### Step 11: Test Access

```bash
# Test without Tailscale
# (Disconnect from Tailscale VPN)

# Should prompt for authentication
curl -I https://freshrss.yourdomain.com

# After logging in via browser, service should be accessible
```

---

## Security Considerations

### Firewall Rules

```bash
# On cloud VM
sudo ufw allow 80/tcp    # HTTP
sudo ufw allow 443/tcp   # HTTPS
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 51820/udp # Tailscale
```

### SSL/TLS

- Traefik automatically gets Let's Encrypt certificates
- All traffic encrypted (HTTPS only)
- Certificates auto-renew

### Authentication

- All services require Authentik login
- Implement 2FA in Authentik
- Use strong passwords
- Regular security audits

### Rate Limiting

Add to Traefik config:

```yaml
http:
  middlewares:
    rate-limit:
      rateLimit:
        average: 100
        burst: 50
```

---

## Maintenance

### Update Cloud Services

```bash
ssh homelab@cloud-vm
cd /opt/stacks/cloud
docker compose pull
docker compose up -d
```

### Monitor Logs

```bash
# Traefik logs
ssh homelab@cloud-vm "docker logs -f traefik"

# Authentik logs
ssh homelab@cloud-vm "docker logs -f authentik"
```

### Check SSL Certificates

```bash
# View certificate info
openssl s_client -connect freshrss.yourdomain.com:443 -servername freshrss.yourdomain.com | openssl x509 -noout -dates
```

---

## Costs

**Monthly Breakdown:**

- Cloud VM: $5-10
- Domain: $10-15/year (~$1/month)
- SSL Certificates: Free (Let's Encrypt)

**Total:** ~$6-11/month

---

## Rollback

If you want to remove cloud proxy:

```bash
# Stop services
ssh homelab@cloud-vm "cd /opt/stacks/cloud && docker compose down"

# Remove from inventory
nano inventory/hosts.ini
# Comment out [cloud_nodes] section

# Continue using Tailscale-only access
```

---

## Troubleshooting

### Can't access services publicly

1. Check DNS: `dig freshrss.yourdomain.com`
2. Check firewall: `sudo ufw status`
3. Check Traefik logs: `docker logs traefik`
4. Verify Tailscale connection between cloud VM and RPi-Home

### SSL certificate issues

```bash
# Check Traefik logs
docker logs traefik | grep -i acme

# Verify domain resolves to correct IP
dig yourdomain.com

# Check Let's Encrypt rate limits
# (5 certificates per domain per week)
```

### Authentik not working

```bash
# Check Authentik logs
docker logs authentik
docker logs authentik-worker

# Verify database connection
docker exec authentik-db psql -U authentik -d authentik -c "SELECT 1;"
```

---

## Alternative: Cloudflare Tunnel

If you don't want to manage a cloud VM, consider Cloudflare Tunnel:

**Pros:**

- Free (no cloud VM costs)
- Cloudflare handles SSL
- DDoS protection included
- Simpler setup

**Cons:**

- Cloudflare can see your traffic
- Dependent on Cloudflare service
- Less control

**Guide:** https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/

---

## Conclusion

Adding a cloud edge proxy is optional and adds complexity. The current Tailscale-only setup is:

-  More secure
-  Simpler
-  Cheaper
-  Fully functional

Only add cloud proxy if you have specific public access requirements.

---

**Questions?** Refer to:

- [Traefik Docs](https://doc.traefik.io/traefik/)
- [Authentik Docs](https://goauthentik.io/docs/)
- Main [README.md](../README.md)
