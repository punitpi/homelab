# Rclone Cloud Mounts

**Purpose:** Stream media from cloud storage (Backblaze B2) without downloading entire libraries.

**Architecture:**
- Rclone mounts cloud storage paths as local filesystem via FUSE
- Systemd service manages auto-mount on boot
- VFS caching enables smooth streaming with local cache
- Deployed only to active node (where apps run)

**Configuration Files:**
- `env/rclone-mounts.env` - Mount configuration (remote paths, mount points)
- `scripts/rclone-audiobooks.service` - Systemd service definition
- `ansible/roles/rclone-mount/` - Ansible role for deployment

**Current Mounts:**
- **Audiobooks**: `b2-crypt:data/media/audiobooks` → `/mnt/audiobooks` (used by audiobookshelf)

**Cache Configuration:**
- **Mode**: `vfs-cache-mode full` - Caches entire files for best streaming performance
- **Max Size**: 50GB - Prevents cache from consuming too much disk space
- **Max Age**: 240 hours (10 days) - Keeps frequently accessed files cached
- **Chunk Size**: 128MB - Optimal for audiobook streaming
- **Buffer**: 256MB - Smooth playback without stuttering

**Systemd Service:**
- **Type**: `notify` - Rclone notifies systemd when mount is ready
- **User**: `homelab` - Runs as non-root user for security
- **Allow-Other**: Enabled - Allows Docker containers to access mount
- **Auto-Start**: Enabled - Mounts on boot before Docker services

**FUSE Configuration:**
- `/etc/fuse.conf` - Must have `user_allow_other` enabled
- Allows non-root users to use `--allow-other` flag
- Required for Docker containers to access mounts

**Adding New Mounts:**
1. Add mount configuration to `env/rclone-mounts.env`:
   ```bash
   PODCASTS_REMOTE=b2-crypt:data/media/podcasts
   PODCASTS_MOUNT=/mnt/podcasts
   ```
2. Create systemd service file (copy `rclone-audiobooks.service` as template)
3. Add Ansible tasks to `ansible/roles/rclone-mount/tasks/main.yml`
4. Update app compose file to mount the directory
5. Deploy with `make deploy-rclone-mount`

**Deployment Target:**
- Uses `.active-node` file or explicit `target=` parameter
- Only deploys to active node (not standby)
- Mount must be ready before apps start (deployment order enforced)

**Troubleshooting:**
```bash
# Check service status
systemctl status rclone-audiobooks.service

# View logs
journalctl -u rclone-audiobooks.service -f

# Check mount is accessible
ls -lah /mnt/audiobooks/

# Verify FUSE configuration
grep user_allow_other /etc/fuse.conf

# Check cache size
du -sh /home/homelab/.cache/rclone

# Manual unmount if needed
fusermount -uz /mnt/audiobooks
```
