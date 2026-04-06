# Container Registry Authentication & Rate Limits

## The Problem

Container registries enforce rate limits and access restrictions:

1. **Docker Hub (docker.io)**
   - Anonymous: 100 pulls per 6 hours per IP
   - Free account: 200 pulls per 6 hours
   - Pro account: Unlimited pulls

2. **GitHub Container Registry (ghcr.io)**
   - Some public images require authentication
   - LinuxServer.io images at `lscr.io/linuxserver/*` redirect to ghcr.io
   - Often shows "denied" errors even for public images

3. **LinuxServer.io (lscr.io)**
   - Registry redirects to ghcr.io
   - May require GitHub authentication

## Our Solution

### 1. Use Docker Hub Mirrors

We switched from registry-specific images to Docker Hub mirrors where available:

**Before:**
```yaml
mealie:
  image: lscr.io/linuxserver/mealie:latest  #  Requires GHCR auth

code-server:
  image: lscr.io/linuxserver/code-server:latest  #  Requires GHCR auth
```

**After:**
```yaml
mealie:
  image: ghcr.io/mealie-recipes/mealie:latest  #  Official Mealie image

code-server:
  image: linuxserver/code-server:latest  #  Docker Hub mirror

audiobookshelf:
  image: linuxserver/audiobookshelf:latest  #  Docker Hub mirror
```

### 2. Image Source Matrix

| Service | Old Image (GHCR) | New Image (Docker Hub) | Registry |
|---------|------------------|------------------------|----------|
| Mealie | lscr.io/linuxserver/mealie | ghcr.io/mealie-recipes/mealie | GitHub (official) |
| Code Server | lscr.io/linuxserver/code-server | linuxserver/code-server | Docker Hub |
| Audiobookshelf | lscr.io/linuxserver/audiobookshelf | linuxserver/audiobookshelf | Docker Hub |
| Wallos | bellamy/wallos | bellamy/wallos | Docker Hub |
| Sterling PDF | frooodle/s-pdf | frooodle/s-pdf | Docker Hub |
| SearXNG | searxng/searxng | searxng/searxng | Docker Hub |
| Open WebUI | ghcr.io/open-webui/open-webui | ghcr.io/open-webui/open-webui | GitHub |

### 3. Benefits

 **No authentication needed** - All images publicly accessible  
 **No rate limit issues** - Using Docker Hub and official repos  
 **Faster pulls** - Docker Hub has better CDN  
 **Official images** - Mealie now uses official image  

## If You Still Hit Rate Limits

### Option 1: Docker Hub Free Account

```bash
# On each node
ssh homelab@rpi-home
docker login
# Enter your Docker Hub username and password
# Increases limit to 200 pulls per 6 hours
```

### Option 2: GitHub Container Registry Authentication

If you need to pull from ghcr.io:

```bash
# Create GitHub Personal Access Token:
# https://github.com/settings/tokens
# Scopes needed: read:packages

# Login to GHCR on each node
ssh homelab@rpi-home
echo YOUR_GITHUB_TOKEN | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin
```

### Option 3: Pre-pull Images

```bash
# Pre-pull all images before deployment
make pull-images

# Then deploy (uses cached images)
make deploy-apps target=rpi-home
```

## Environment Variable Warning Fix

**Issue:** Warning about B2_BUCKET not set during Docker Compose deployment

**Cause:** `common.env` is loaded before `secrets.env`, so B2_BUCKET isn't available yet

**Solution:** The warning is harmless (B2_BUCKET gets defined when secrets.env loads). We removed the unused RESTIC_REPOSITORY variable reference from common.env.

**Before (common.env):**
```bash
RESTIC_REPOSITORY=rclone:${RCLONE_REMOTE_NAME}:${B2_BUCKET}/restic  #  B2_BUCKET undefined
```

**After (common.env):**
```bash
# Note: B2_BUCKET is defined in secrets.env
# Scripts will load both env files and build the path dynamically
```

The backup scripts load both env files explicitly, so they have access to all variables.

## Deployment Workflow

### First Time Setup

```bash
# 1. Pre-pull images (optional but recommended)
make pull-images

# 2. Deploy apps (uses cached images or Docker Hub mirrors)
make deploy-apps target=rpi-home

# No authentication needed!
```

### Regular Deployments

```bash
# Deploy changes (uses cached images)
make deploy-apps target=rpi-home

# With pull: missing, only pulls if image not cached
```

### Monthly Updates

```bash
# Update all images to latest
make update-images

# Or update specific service
ssh rpi-home "cd /opt/stacks/apps && docker compose pull mealie && docker compose up -d mealie"
```

## Troubleshooting

### Error: "denied" from ghcr.io

**Solution:** We fixed this by switching to Docker Hub mirrors

```bash
# Old (fails with "denied")
image: lscr.io/linuxserver/code-server:latest

# New (works without auth)
image: linuxserver/code-server:latest
```

### Error: "toomanyrequests" from Docker Hub

**Solution 1:** Pre-pull images
```bash
make pull-images
```

**Solution 2:** Login to Docker Hub
```bash
ssh homelab@rpi-home
docker login
```

**Solution 3:** Use cached images
```bash
# Your deployments already use cached images with pull: missing
# Just wait 6 hours for rate limit reset
```

### Verify Current Images

```bash
# Check what images are configured
grep "image:" stacks/apps/compose.yml

# Check what's cached on node
ssh homelab@rpi-home
docker images | grep -E "mealie|code-server|audiobookshelf"
```

## Advanced: Automated Registry Authentication

If you want to automate registry authentication across all nodes:

### 1. Create Docker Hub Token

Visit: https://hub.docker.com/settings/security

### 2. Add to secrets.env

```bash
DOCKERHUB_USERNAME=your-username
DOCKERHUB_TOKEN=your-token
```

### 3. Create Ansible Role

```yaml
# ansible/roles/docker-login/tasks/main.yml
---
- name: Login to Docker Hub
  community.docker.docker_login:
    registry_url: https://index.docker.io/v1/
    username: "{{ lookup('env', 'DOCKERHUB_USERNAME') }}"
    password: "{{ lookup('env', 'DOCKERHUB_TOKEN') }}"
  when: lookup('env', 'DOCKERHUB_USERNAME') != ''

- name: Login to GitHub Container Registry
  community.docker.docker_login:
    registry_url: ghcr.io
    username: "{{ lookup('env', 'GITHUB_USERNAME') }}"
    password: "{{ lookup('env', 'GITHUB_TOKEN') }}"
  when: lookup('env', 'GITHUB_TOKEN') != ''
```

### 4. Add to site.yml

```yaml
- hosts: all
  roles:
    - docker-login
    - common
    - compose-deploy
```

## Summary

**Current Setup:**
-  All images use Docker Hub or official repos
-  No authentication required
-  No rate limit issues (with pull: missing)
-  Fast, reliable deployments

**If you need:**
- More pulls: Login to Docker Hub (200 pulls/6h)
- GHCR access: Create GitHub token and login
- Zero limits: Upgrade to Docker Hub Pro ($7/month)
