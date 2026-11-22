# Ansible Sudo Password Configuration

Ansible needs the `homelab` user's sudo password on each node. The passwords live in one vault-encrypted file, and every `make` command that deploys prompts for the vault password (not the sudo passwords).

## Layout

```
inventory/group_vars/
├── all.yml          # Whole file encrypted with ansible-vault. Holds the secrets:
│                    #   vault_rpi_sudo_pass, vault_cloud_sudo_pass, vault_wifi_password
├── rpi_nodes.yml    # Plain text: ansible_sudo_pass: '{{ vault_rpi_sudo_pass }}'
└── cloud_nodes.yml  # Plain text: ansible_sudo_pass: '{{ vault_cloud_sudo_pass }}'
```

The group files only reference the vault variables, so they stay readable and diffable; the secrets themselves are only in `all.yml`.

## Setup

```bash
# First time: create the encrypted file (you choose the vault password here)
ansible-vault create inventory/group_vars/all.yml

# Later: edit it in place
ansible-vault edit inventory/group_vars/all.yml
```

Contents (plain YAML inside the encrypted file):

```yaml
vault_rpi_sudo_pass: 'sudo password of the homelab user on the RPis'
vault_cloud_sudo_pass: 'sudo password of the homelab user on the cloud VM'
vault_wifi_password: 'WiFi password, used by the network-priority tasks'
```

When rebuilding a node, set the `homelab` user's password to the value in `vault_rpi_sudo_pass`, or deployments fail with an incorrect sudo password.

## App secrets (passwords, API keys, ACME email)

The stacks' secrets can live in the same vault as a `vault_stack_secrets` dictionary. When it is set, the `common` role writes each node's `/opt/stacks/env/secrets.env` from it (mode 0600, never logged). When it is not set, the role copies your git-ignored `env/secrets.env` as before.

```yaml
# inside inventory/group_vars/all.yml (encrypted)
vault_stack_secrets:
  ACME_EMAIL: !unsafe 'you@yourdomain'
  PG_PASSWORD: !unsafe '...'
  PAPERLESS_DB_PASSWORD: !unsafe '...'
  # one entry per KEY=value line of the old secrets.env
```

`!unsafe` stops Ansible from treating `{{` or `{%` inside a random password as a template expression.

One-time migration from `env/secrets.env`:

```bash
# In your own terminal (the output is every secret in plain text; don't paste it anywhere else)
scripts/secrets-to-vault.sh
ansible-vault edit inventory/group_vars/all.yml   # paste the block, save
make deploy-base                                  # nodes now get secrets.env from the vault
```

Keep `env/secrets.env` for now: `make validate` still reads it to check that every variable is defined.

Rotating a secret is then: `ansible-vault edit`, change the value, redeploy.

## Usage

```bash
make deploy-base                    # prompts for the vault password
make deploy-apps target=rpi-home    # prompts for the vault password
```

## Troubleshooting

```bash
# Check the vault decrypts and the variable is there
ansible-vault view inventory/group_vars/all.yml

# Check sudo works through Ansible
ansible rpi_nodes -i inventory/hosts.ini -m shell -a "sudo whoami" --ask-vault-pass

# Check the password by hand on the node
ssh homelab@rpi-home
sudo whoami
```

- **"Missing sudo password" or "Incorrect sudo password":** the node's `homelab` password does not match `vault_rpi_sudo_pass`. Change one to match the other.
- **Changing the vault password:** `ansible-vault rekey inventory/group_vars/all.yml` (needs the current vault password).
- **Forgotten vault password:** it cannot be recovered. Recreate `all.yml` with `ansible-vault create` and enter the sudo and WiFi passwords again.

## Security notes

- Keep the vault password in a password manager, never in the repository.
- The vault password protects every secret in `all.yml`; the sudo passwords are the real passwords of the `homelab` user on each node.
