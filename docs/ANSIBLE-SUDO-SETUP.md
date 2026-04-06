# Ansible Sudo Password Configuration Guide

This document explains how sudo password authentication is configured in this homelab setup.

## Overview

Instead of manually entering sudo passwords every time you run Ansible commands, this setup uses **encrypted sudo passwords** stored in Ansible Vault files. This provides:

-  **Security**: Passwords are encrypted using Ansible Vault
-  **Convenience**: No manual password entry for each command
-  **Flexibility**: Different passwords for different node groups
-  **Automation**: Supports scripted deployments

## Configuration Structure

```
inventory/
├── hosts.ini                    # Main inventory (no passwords here)
└── group_vars/
    ├── rpi_nodes.yml           # Contains encrypted sudo password for RPis
    └── cloud_nodes.yml         # Contains encrypted sudo password for cloud VMs
```

## How It Works

1. **Group-specific passwords**: Each node group (`rpi_nodes`, `cloud_nodes`) can have different sudo passwords
2. **Ansible Vault encryption**: All passwords are encrypted using `ansible-vault encrypt_string`
3. **Single vault password**: One vault password decrypts all encrypted secrets
4. **Automatic usage**: Makefile commands include `--ask-vault-pass` to prompt for the vault password

## Setup Process

### 1. Encrypt Sudo Password for RPi Nodes

```bash
echo 'ansible_sudo_pass: YOUR_RPI_SUDO_PASSWORD' | ansible-vault encrypt_string --stdin-name 'ansible_sudo_pass'
```

### 2. Add to rpi_nodes.yml

Add the encrypted output to `inventory/group_vars/rpi_nodes.yml`:

```yaml
# Ansible Authentication
ansible_sudo_pass: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  [ENCRYPTED_PASSWORD_OUTPUT]
```

### 3. Repeat for Cloud Nodes

```bash
echo 'ansible_sudo_pass: YOUR_CLOUD_SUDO_PASSWORD' | ansible-vault encrypt_string --stdin-name 'ansible_sudo_pass'
```

Add to `inventory/group_vars/cloud_nodes.yml` in the same format.

## Usage

All `make` commands that require sudo access will prompt for your **vault password** (not the actual sudo passwords):

```bash
make deploy-base                    # Prompts for vault password
make deploy-apps target=rpi-home   # Prompts for vault password
make update-packages               # Prompts for vault password
```

## Security Notes

- **Vault password**: This is the master password that decrypts all your encrypted secrets
- **Sudo passwords**: These are the actual passwords for the `homelab` user on each node
- **Storage**: Store your vault password in a password manager, not in the repository
- **Rotation**: To change passwords, re-encrypt using `ansible-vault encrypt_string`

## Troubleshooting

### "Missing sudo password" Error

This usually means the encrypted password isn't properly configured:

```bash
# Test vault decryption
ansible-vault view inventory/group_vars/rpi_nodes.yml

# Test sudo access manually
ssh homelab@rpi-home
sudo whoami  # Should work with the same password you encrypted
```

### "Incorrect vault password" Error

Your vault password is wrong. If you forgot it:

```bash
# Re-encrypt all vault files with new vault password
ansible-vault rekey inventory/group_vars/rpi_nodes.yml
ansible-vault rekey inventory/group_vars/cloud_nodes.yml
```

### Testing Configuration

```bash
# Test RPi nodes sudo access
ansible rpi_nodes -i inventory/hosts.ini -m shell -a "sudo whoami" --ask-vault-pass

# Test cloud nodes sudo access
ansible cloud_nodes -i inventory/hosts.ini -m shell -a "sudo whoami" --ask-vault-pass
```

## Alternative Approaches

If you prefer not to use encrypted passwords, you can:

1. **Manual password entry**: Remove the `ansible_sudo_pass` variables and add `--ask-become-pass` to commands
2. **Passwordless sudo**: Configure the `homelab` user for passwordless sudo (less secure)
3. **SSH key-based sudo**: Use SSH keys for sudo authentication (advanced setup)

This encrypted approach provides the best balance of security and convenience for most users.
