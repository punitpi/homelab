#  SSH Setup Guide

Complete guide for setting up SSH key authentication for your homelab.

---

## Why SSH Keys?

SSH keys provide:

-  **Security**: More secure than passwords
-  **Convenience**: No password typing once set up
-  **Automation**: Required for Ansible
-  **Auditability**: Know which keys have access

---

## Quick Setup (5 minutes)

```bash
# 1. Generate SSH key
ssh-keygen -t ed25519 -C "homelab-key"
# Press Enter to accept default location
# Set a passphrase (recommended) or press Enter for none

# 2. Start SSH agent
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519

# 3. Copy key to all nodes
ssh-copy-id pi@192.168.1.100        # RPi-Home
ssh-copy-id pi@192.168.1.101        # RPi-Friend
ssh-copy-id root@139.162.155.202    # Cloud VPS

# 4. Test connection
ssh pi@192.168.1.100 "echo 'SSH working!'"
```

**Done!** You can now SSH without passwords.

---

## Detailed Setup

### Step 1: Generate SSH Key Pair

**On your management machine (laptop/desktop):**

```bash
# Generate Ed25519 key (recommended - modern and secure)
ssh-keygen -t ed25519 -C "homelab-key"

# You'll see:
Generating public/private ed25519 key pair.
Enter file in which to save the key (/Users/you/.ssh/id_ed25519):
```

**Press Enter** to accept default location (`~/.ssh/id_ed25519`)

```bash
Enter passphrase (empty for no passphrase):
```

**Options:**

- **With passphrase** (recommended): More secure, but you'll need to type it
- **Without passphrase**: More convenient, less secure

**Result:**

- Private key: `~/.ssh/id_ed25519` (keep secret!)
- Public key: `~/.ssh/id_ed25519.pub` (can be shared)

**Alternative: RSA key (if Ed25519 not supported)**

```bash
ssh-keygen -t rsa -b 4096 -C "homelab-key"
```

---

### Step 2: Start SSH Agent

The SSH agent holds your keys in memory so you don't have to type the passphrase repeatedly.

```bash
# Start agent
eval "$(ssh-agent -s)"

# Add your key
ssh-add ~/.ssh/id_ed25519

# Verify key is loaded
ssh-add -l
```

**Expected output:**

```
256 SHA256:xxx...xxx homelab-key (ED25519)
```

---

### Step 3: Copy Keys to Target Nodes

You need to copy your public key to each node you want to access.

#### For Raspberry Pis

**Default user is usually `pi` or `ubuntu`:**

```bash
# Find your RPi's IP (check your router or use nmap)
nmap -sn 192.168.1.0/24 | grep -B 2 "Raspberry Pi"

# Copy key to RPi
ssh-copy-id pi@192.168.1.100

# You'll see:
The authenticity of host '192.168.1.100' can't be established.
ED25519 key fingerprint is SHA256:xxx...xxx
Are you sure you want to continue connecting (yes/no/[fingerprint])?
```

**Type `yes`** and press Enter

```bash
pi@192.168.1.100's password:
```

**Enter the default password** (usually `raspberry` or the one you set during installation)

```bash
Number of key(s) added: 1

Now try logging into the machine, with:   "ssh 'pi@192.168.1.100'"
and check to make sure that only the key(s) you wanted were added.
```

#### For Cloud VPS

**Default user is usually `root`:**

```bash
ssh-copy-id root@139.162.155.202
```

Same process - you may need to enter the VPS password once.

#### For Custom Linux Box

**Use the current username:**

```bash
ssh-copy-id youruser@192.168.1.105
```

---

### Step 4: Test SSH Connection

**Test each node:**

```bash
# Test RPi-Home
ssh pi@192.168.1.100 "echo 'SSH working!'"

# Test RPi-Friend
ssh pi@192.168.1.101 "echo 'SSH working!'"

# Test Cloud VPS
ssh root@139.162.155.202 "echo 'SSH working!'"
```

**Expected:** Command executes without asking for password.

**If it asks for password:** Key wasn't copied correctly, repeat Step 3.

---

## Bootstrap Script & SSH Keys

After running the bootstrap script, SSH access changes:

### Before Bootstrap

```bash
# Can SSH as default user
ssh pi@192.168.1.100          #  Works
ssh root@139.162.155.202      #  Works
```

### After Bootstrap

```bash
# Must SSH as homelab user
ssh homelab@192.168.1.100     #  Works
ssh pi@192.168.1.100          #  Won't work (disabled)
ssh root@139.162.155.202      #  Won't work (disabled)
```

**Why?** Bootstrap script:

1. Creates `homelab` user
2. Copies SSH keys from source user to `homelab`
3. Disables root login
4. Disables password authentication

---

## Troubleshooting

### Problem: "Permission denied (publickey)"

**After ssh-copy-id, but still can't connect:**

```bash
# Check if key is loaded
ssh-add -l

# If empty, add key again
ssh-add ~/.ssh/id_ed25519

# Try connecting with verbose output
ssh -v pi@192.168.1.100
```

**Look for:**

```
debug1: Offering public key: /Users/you/.ssh/id_ed25519 ED25519 SHA256:xxx
debug1: Server accepts key: /Users/you/.ssh/id_ed25519 ED25519 SHA256:xxx
debug1: Authentication succeeded (publickey).
```

**If you see "no mutual signature algorithm":**

```bash
# Add this to ~/.ssh/config
Host *
  PubkeyAcceptedKeyTypes +ssh-rsa
  HostKeyAlgorithms +ssh-rsa
```

### Problem: "Connection refused"

```bash
# Check if SSH service is running on target
# (requires physical access or console)
sudo systemctl status sshd

# If stopped, start it
sudo systemctl start sshd
sudo systemctl enable sshd
```

### Problem: ssh-copy-id not found (Windows)

**Option 1: Use Git Bash**

```bash
# Git Bash includes ssh-copy-id
```

**Option 2: Manual copy**

```bash
# Get your public key
cat ~/.ssh/id_ed25519.pub

# Copy the output, then SSH to target and run:
mkdir -p ~/.ssh
chmod 700 ~/.ssh
echo "paste-your-public-key-here" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

**Option 3: Use PowerShell**

```powershell
# PowerShell command
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh pi@192.168.1.100 "cat >> ~/.ssh/authorized_keys"
```

### Problem: "Too many authentication failures"

**If you have many SSH keys:**

```bash
# Specify which key to use
ssh -i ~/.ssh/id_ed25519 pi@192.168.1.100

# Or add to ~/.ssh/config
Host rpi-home
  HostName 192.168.1.100
  User pi
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
```

### Problem: After bootstrap, can't connect as homelab

**Keys weren't copied properly during bootstrap:**

```bash
# Connect as default user one more time (if possible)
ssh pi@192.168.1.100

# Manually copy keys to homelab user
sudo mkdir -p /home/homelab/.ssh
sudo cp ~/.ssh/authorized_keys /home/homelab/.ssh/
sudo chown -R homelab:homelab /home/homelab/.ssh
sudo chmod 700 /home/homelab/.ssh
sudo chmod 600 /home/homelab/.ssh/authorized_keys

# Test
exit
ssh homelab@192.168.1.100
```

---

## SSH Config File (Optional)

Create `~/.ssh/config` for easier access:

```bash
# Edit config file
nano ~/.ssh/config
```

**Add:**

```
# RPi-Home
Host rpi-home
  HostName 192.168.1.100
  User homelab
  IdentityFile ~/.ssh/id_ed25519

# RPi-Friend
Host rpi-friend
  HostName 192.168.1.101
  User homelab
  IdentityFile ~/.ssh/id_ed25519

# Cloud VPS
Host cloud-vm
  HostName 139.162.155.202
  User homelab
  IdentityFile ~/.ssh/id_ed25519

# General settings
Host *
  AddKeysToAgent yes
  UseKeychain yes  # macOS only
  ServerAliveInterval 60
  ServerAliveCountMax 10
```

**Now you can use:**

```bash
ssh rpi-home      # Instead of ssh homelab@192.168.1.100
ssh rpi-friend
ssh cloud-vm
```

---

## Tailscale IPs (After Setup)

Once Tailscale is configured, update SSH config with Tailscale IPs:

```bash
# Get Tailscale IPs
ssh homelab@192.168.1.100 tailscale ip -4

# Update ~/.ssh/config
Host rpi-home
  HostName 100.101.102.103  # Use Tailscale IP
  User homelab
  IdentityFile ~/.ssh/id_ed25519
```

**Benefits:**

- Access from anywhere (not just local network)
- Encrypted connection via Tailscale
- Same IP even if local IP changes

---

## Security Best Practices

### 1. Use Passphrase

**Protect your private key:**

```bash
# Add/change passphrase on existing key
ssh-keygen -p -f ~/.ssh/id_ed25519
```

### 2. Set Proper Permissions

```bash
# Private key (only you can read)
chmod 600 ~/.ssh/id_ed25519

# Public key (others can read)
chmod 644 ~/.ssh/id_ed25519.pub

# .ssh directory
chmod 700 ~/.ssh
```

### 3. Backup Keys Securely

```bash
# Backup private key to secure location
# DO NOT store in cloud unencrypted!

# Option 1: Encrypted USB drive
# Option 2: Password manager with file storage
# Option 3: Encrypted backup service
```

### 4. Rotate Keys Periodically

```bash
# Generate new key pair
ssh-keygen -t ed25519 -C "homelab-key-2024"

# Copy new key to all nodes
ssh-copy-id -i ~/.ssh/id_ed25519_new pi@192.168.1.100

# Test new key works
ssh -i ~/.ssh/id_ed25519_new pi@192.168.1.100

# Remove old key from nodes
ssh pi@192.168.1.100
nano ~/.ssh/authorized_keys
# Delete old key line

# Update ssh-agent
ssh-add -D  # Remove all
ssh-add ~/.ssh/id_ed25519_new  # Add new
```

### 5. Limit Key Access

**On target node, restrict what key can do:**

```bash
# Edit authorized_keys
nano ~/.ssh/authorized_keys

# Add restrictions before key:
from="192.168.1.0/24",command="/usr/bin/backup" ssh-ed25519 AAAA...
```

---

## Multi-Machine Setup

If managing from multiple computers:

**Option 1: Use same key on all (easier)**

```bash
# Copy private key to second machine
scp ~/.ssh/id_ed25519 user@laptop:~/.ssh/
scp ~/.ssh/id_ed25519.pub user@laptop:~/.ssh/
```

**Option 2: Generate separate keys (more secure)**

```bash
# On second machine, generate new key
ssh-keygen -t ed25519 -C "homelab-key-laptop"

# Copy to all nodes
ssh-copy-id -i ~/.ssh/id_ed25519_laptop pi@192.168.1.100

# Now both keys work
```

---

## Testing Checklist

Before proceeding with homelab setup:

```bash
# Test all nodes
- [ ] SSH to rpi-home works without password
- [ ] SSH to rpi-friend works without password
- [ ] SSH to cloud-vm works without password
- [ ] SSH keys loaded in ssh-agent
- [ ] Can run commands remotely: ssh node "ls -la"
- [ ] Ansible ping works: ansible all -i inventory/hosts.ini -m ping
```

**Once all checked, you're ready for bootstrap!**

---

## Quick Reference

```bash
# Generate key
ssh-keygen -t ed25519 -C "homelab"

# Start agent
eval "$(ssh-agent -s)"

# Add key
ssh-add ~/.ssh/id_ed25519

# Copy key
ssh-copy-id user@host

# Test connection
ssh user@host "echo OK"

# List loaded keys
ssh-add -l

# Remove all keys
ssh-add -D

# Connect with specific key
ssh -i ~/.ssh/key user@host
```

---

## Additional Resources

- [SSH.com Academy](https://www.ssh.com/academy/ssh)
- [GitHub SSH Guide](https://docs.github.com/en/authentication/connecting-to-github-with-ssh)
- [DigitalOcean SSH Tutorial](https://www.digitalocean.com/community/tutorials/ssh-essentials-working-with-ssh-servers-clients-and-keys)

---

**Next Steps:** Once SSH is working, proceed to [bootstrap script](../scripts/bootstrap.sh) to prepare your nodes.
