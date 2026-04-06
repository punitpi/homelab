# Tailscale-Only HTTPS Setup

This setup provides **secure HTTPS access to your services via Tailscale** without exposing anything to the public internet.

## Architecture

```
Your Devices (connected to Tailscale)
  ↓ HTTPS (https://mealie.igh.one)
Traefik on RPi (100.88.245.35)
  ├── Let's Encrypt TLS cert (Cloudflare DNS challenge)
  └── Routes to apps (Mealie, Wallos, etc.)
```

**Benefits:**
-  Secure HTTPS with valid certificates
-  No public internet exposure
-  Works from any device with Tailscale
-  Simple, no cloud VM needed
-  No monthly costs

## Prerequisites

1. **Domain name**: You need `igh.one` (already configured)
2. **Cloudflare DNS**: Domain must use Cloudflare nameservers
3. **Cloudflare API token**: Already in `env/secrets.env` (CF_DNS_API_TOKEN)
4. **Tailscale**: All devices connected to same Tailscale network

## DNS Configuration

**Option 1: Tailscale MagicDNS (Recommended)**

Add a DNS override in Tailscale admin console:
1. Go to https://login.tailscale.com/admin/dns
2. Add nameserver: `100.88.245.35` (your RPi Tailscale IP)
3. Add search domain: `igh.one`

OR

**Option 2: Split DNS on Client Devices**

On each device using Tailscale, configure DNS to resolve `*.igh.one` to the RPi's Tailscale IP:

**macOS/Linux** - Add to `/etc/hosts`:
```
100.88.245.35 mealie.igh.one
100.88.245.35 wallos.igh.one
100.88.245.35 pdf.igh.one
100.88.245.35 search.igh.one
100.88.245.35 code.igh.one
100.88.245.35 chat.igh.one
100.88.245.35 books.igh.one
100.88.245.35 n8n.igh.one
100.88.245.35 traefik.igh.one
```

**Windows** - Add to `C:\Windows\System32\drivers\etc\hosts` (same format)

**Android/iOS** - Use a DNS override app or configure per-network DNS

**Option 3: Public DNS (Works but certificate validation only)**

You can also set public DNS A records pointing to the Tailscale IP. The DNS will be public, but the IP is only routable on your Tailscale network:

```
A    *.igh.one -> 100.88.245.35
```

 This exposes that you have these subdomains, but they're not accessible without Tailscale.

## How It Works

1. **DNS Resolution**: `mealie.igh.one` resolves to `100.88.245.35` (RPi Tailscale IP)
2. **Traefik receives request**: Port 443 on RPi
3. **TLS termination**: Traefik presents Let's Encrypt certificate
4. **Cloudflare DNS challenge**: Let's Encrypt validates domain ownership via Cloudflare DNS API (no need for port 80/443 to be publicly accessible)
5. **Proxy to app**: Traefik routes to the correct container (e.g., Mealie on port 9000)

## Deployment

1. **Deploy base stack** (includes Traefik with TLS):
```bash
make deploy-base
```

2. **Deploy apps stack**:
```bash
make deploy-apps target=rpi-home
```

3. **Check Traefik logs**:
```bash
ansible rpi-home -i inventory/hosts.ini -m shell -a "docker logs traefik" --ask-vault-pass
```

Look for:
```
time="..." level=info msg="Configuration loaded from flags."
time="..." level=info msg="Traefik version 3.0..."
```

## Testing Access

1. **Connect to Tailscale** on your device
2. **Configure DNS** (using one of the options above)
3. **Visit** `https://mealie.igh.one`

You should see:
-  Valid HTTPS certificate (Let's Encrypt)
-  No browser warnings
-  Mealie login page

## Troubleshooting

### Certificate not issued

Check Traefik logs for ACME errors:
```bash
ansible rpi-home -i inventory/hosts.ini -m shell -a "docker logs traefik | grep acme" --ask-vault-pass
```

Common issues:
- Cloudflare API token invalid or expired
- Rate limit (Let's Encrypt: 5 certs/week per domain)
- DNS propagation delay (wait 5-10 minutes)

### DNS not resolving

Test DNS resolution:
```bash
nslookup mealie.igh.one
# Should return: 100.88.245.35
```

If it doesn't:
- Check your DNS configuration method
- Ensure Tailscale is connected: `tailscale status`
- Try using `/etc/hosts` override

### Connection refused

Check if Traefik is running:
```bash
ansible rpi-home -i inventory/hosts.ini -m shell -a "docker ps | grep traefik" --ask-vault-pass
```

Check if port 443 is listening:
```bash
ansible rpi-home -i inventory/hosts.ini -m shell -a "netstat -tlnp | grep 443" --ask-vault-pass
```

### App not accessible via Traefik

1. Check if app is on the `traefik` network:
```bash
ansible rpi-home -i inventory/hosts.ini -m shell -a "docker network inspect traefik" --ask-vault-pass
```

2. Check Traefik dashboard for routers:
Visit `https://traefik.igh.one` to see all configured routes

## Services Available

Once deployed, these services are available via HTTPS:

- `https://traefik.igh.one` - Traefik dashboard
- `https://mealie.igh.one` - Recipe manager
- `https://wallos.igh.one` - Subscription tracker
- `https://pdf.igh.one` - PDF tools
- `https://search.igh.one` - Private search
- `https://code.igh.one` - VS Code web
- `https://chat.igh.one` - AI chat interface
- `https://books.igh.one` - Audiobooks
- `https://n8n.igh.one` - Workflow automation

## Future: Cloud Proxy (Optional)

If you later want **public internet access** without Tailscale:
1. See `docs/CLOUD-PROXY-SETUP.md` for cloud VM setup
2. Deploy the cloud stack: `make deploy-cloud`
3. Point public DNS to cloud VM IP

This is **optional** and adds complexity. The current Tailscale-only setup is:
- More secure
- Simpler
- Cheaper (no cloud costs)
- Fully functional for personal use
