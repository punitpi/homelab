# Docker Image Pull Strategy

## Overview

This homelab uses a smart Docker image caching strategy to avoid Docker Hub rate limits while ensuring efficient deployments.

## Rate Limit Problem

Docker Hub enforces rate limits:
- **Anonymous users**: 100 pulls per 6 hours per IP
- **Free accounts**: 200 pulls per 6 hours
- **Pro accounts**: Unlimited pulls

With multiple nodes and services, repeated deployments can quickly hit these limits.

## Our Solution

### 1. Pull Policy: `missing` (Default)

The Ansible playbook uses `pull: missing` in `ansible/roles/compose-deploy/tasks/main.yml`:

```yaml
- name: Deploy {{ stack_name }} stack from compose file
  community.docker.docker_compose_v2:
    project_src: '{{ STACKS_PATH }}/{{ stack_name }}'
    state: present
    pull: missing  # ← Only pulls if image not cached
```

**What this does:**
- Docker Compose only pulls images that don't exist locally
- If image is cached, it uses the cached version
- No unnecessary pulls = no rate limit issues
- Deployments are fast and reliable

### 2. Pre-Pull Command: `make pull-images`

Before initial deployment or when setting up new nodes, run:

```bash
make pull-images
```

**What this does:**
- Pulls all required images to all nodes in one go
- Base images (PostgreSQL, Redis) → All nodes
- App images (Mealie, Wallos, etc.) → RPi nodes
- Cloud images (Traefik, Authentik, etc.) → Cloud VM
- Takes ~5-10 minutes depending on internet speed
- Ensures all future deployments use cached images

**When to use:**
-  Before first deployment (highly recommended)
-  After adding new nodes
-  After adding new services
-  Not needed for regular deployments

### 3. Update Command: `make update-images`

When you want to update all services to latest versions:

```bash
make update-images
```

**What this does:**
- Pulls fresh images from registries (forces update)
- Restarts all services with new images
- Works across all stacks (base, apps, cloud)
- Prompts for confirmation before proceeding

**When to use:**
-  Monthly updates for security patches
-  When new features are released
-  When explicitly wanting latest versions
-  Not for regular deployments (use cached images)

## Image Sources

Our images come from different registries with different rate limits:

| Registry | Images | Rate Limits |
|----------|--------|-------------|
| Docker Hub | postgres, redis, wallos, frooodle/s-pdf, searxng, traefik | 100-200 pulls/6h |
| GitHub Container Registry (ghcr.io) | open-webui, authentik | More generous limits |
| LinuxServer.io (lscr.io) | mealie, code-server, audiobookshelf | Separate rate limits |

## Deployment Workflow

### Initial Setup (One Time)

```bash
# 1. Pre-pull all images (optional but recommended)
make pull-images

# 2. Deploy infrastructure (uses cached images)
make deploy-base
make deploy-apps target=rpi-home
make deploy-backup-automation
```

### Regular Deployments (Iterative)

```bash
# Deploy changes (uses cached images, no pulls)
make deploy-apps target=rpi-home

# Ansible uses pull: missing, so no rate limit issues
```

### Monthly Updates

```bash
# Update all services to latest versions
make update-images

# Or update specific stack manually
ssh rpi-home "cd /opt/stacks/apps && docker compose pull && docker compose up -d"
```

## Avoiding Rate Limits: Best Practices

1. **Pre-pull before deployments**
   ```bash
   make pull-images  # Run this first
   ```

2. **Use cached images for iterations**
   ```bash
   # These use cached images (no pulls)
   make deploy-base
   make deploy-apps target=rpi-home
   ```

3. **Only force-pull when needed**
   ```bash
   # Only do this when you want updates
   make update-images
   ```

4. **Login to Docker Hub (optional)**
   ```bash
   # On each node, increases limit to 200/6h
   ssh homelab@rpi-home "docker login"
   ssh homelab@rpi-friend "docker login"
   ssh homelab@cloud-vm "docker login"
   ```

5. **Monitor rate limits**
   ```bash
   # Check remaining pulls (requires auth token)
   curl -s "https://auth.docker.io/token?service=registry.docker.io&scope=repository:ratelimitpreview/test:pull" | jq -r .token | xargs -I {} curl -s -H "Authorization: Bearer {}" https://registry-1.docker.io/v2/ratelimitpreview/test/manifests/latest -I | grep -i ratelimit
   ```

## Troubleshooting Rate Limits

### Error: "toomanyrequests: You have reached your pull rate limit"

**Solution 1: Wait it out**
```bash
# Rate limit resets after 6 hours
# Check back later
```

**Solution 2: Use cached images**
```bash
# Your cached images still work fine
docker images  # View cached images
docker compose up -d  # Use cached images
```

**Solution 3: Login to Docker Hub**
```bash
# Increases limit to 200 pulls per 6 hours
docker login
# Enter your Docker Hub username/password
```

**Solution 4: Use Docker Hub Pro account**
- Upgrade to Pro ($7/month) for unlimited pulls
- Login on all nodes with Pro credentials

### Verify Images are Cached

```bash
# On any node
ssh homelab@rpi-home

# List all cached images
docker images

# Check specific image
docker images | grep mealie
docker images | grep postgres
```

### Check Image Pull Policy

```bash
# Verify Ansible uses 'missing' policy
grep -r "pull:" ansible/roles/compose-deploy/tasks/main.yml

# Should show: pull: missing
```

## Advanced: Docker Hub Authentication

For production setups, consider authenticating all nodes:

### One-time setup on each node

```bash
# Create Docker Hub access token at:
# https://hub.docker.com/settings/security

# On each node
ssh homelab@rpi-home
docker login -u YOUR_USERNAME
# Enter token as password

# Verify login
cat ~/.docker/config.json
```

### Automate with Ansible (Optional)

Add to `env/secrets.env`:
```bash
DOCKERHUB_USERNAME=your-username
DOCKERHUB_TOKEN=your-token
```

Create `ansible/roles/docker-login/tasks/main.yml`:
```yaml
---
- name: Login to Docker Hub
  community.docker.docker_login:
    username: "{{ DOCKERHUB_USERNAME }}"
    password: "{{ DOCKERHUB_TOKEN }}"
  when: DOCKERHUB_USERNAME is defined
```

## Summary

**Default behavior (no rate limit issues):**
```bash
# Ansible uses 'pull: missing' - only pulls if not cached
make deploy-base
make deploy-apps target=rpi-home
```

**Pre-pull for first time (recommended):**
```bash
make pull-images  # One-time per node setup
```

**Force updates (when you want latest):**
```bash
make update-images  # Monthly or as needed
```

This strategy ensures:
-  Fast deployments (uses cache)
-  No rate limit issues (minimal pulls)
-  Easy updates (when you want them)
-  Reliable operations (cached images always work)
