## Security Policy

### Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| main    | :white_check_mark: |
| develop | :white_check_mark: |

#  Security Overview

Comprehensive security documentation for your homelab infrastructure.

---

## Table of Contents

1. [Security Model](#security-model)
2. [Network Security](#network-security)
3. [Access Control](#access-control)
4. [Data Protection](#data-protection)
5. [Hardening Checklist](#hardening-checklist)
6. [Threat Model](#threat-model)
7. [Security Monitoring](#security-monitoring)
8. [Incident Response](#incident-response)
9. [Reporting Security Issues](#reporting-security-issues)

---

## Security Model

### Defense in Depth

Our security strategy uses multiple layers:

```
Layer 1: Network (Tailscale VPN, Firewall)
    ↓
Layer 2: Access Control (SSH keys, No root login)
    ↓
Layer 3: Application (Container isolation, Localhost binding)
    ↓
Layer 4: Data (Encrypted backups, Database passwords)
    ↓
Layer 5: Monitoring (Logs, Alerts, Intrusion detection)
```

### Security Principles

1. **Zero Trust**: Never trust, always verify
2. **Least Privilege**: Minimum necessary access
3. **Fail Secure**: Secure defaults, explicit allow
4. **Defense in Depth**: Multiple security layers
5. **Security by Design**: Built-in, not bolted-on

---

## Network Security

### Tailscale VPN Mesh

**Security Features:**

-  WireGuard encryption (ChaCha20-Poly1305)
-  End-to-end encrypted tunnels
-  No public port exposure
-  Zero-config secure networking

**Best Practices:**

- Use ephemeral keys for temporary devices
- Enable key expiry for testing
- Disable key expiry for servers
- Use ACLs to restrict inter-node traffic

### Firewall (UFW)

**Default Policy:**

```bash
# Default: Deny all incoming, allow all outgoing
sudo ufw default deny incoming
sudo ufw default allow outgoing
```

**Allowed Ports:**

- 22/tcp (SSH)
- 51820/udp (Tailscale WireGuard)
- 41641/udp (Tailscale pathfinding)

### Service Binding

**Localhost-Only Binding:**

```yaml
# All services bind to 127.0.0.1, not 0.0.0.0
services:
  freshrss:
    ports:
      - '127.0.0.1:8081:80' #  Secure (localhost only)
```

---

## Access Control

### SSH Security

**Key-Based Authentication Only:**

```bash
# SSH config (enforced by bootstrap script)
PermitRootLogin no              # Root cannot login
PasswordAuthentication no       # No passwords allowed
PubkeyAuthentication yes        # Only SSH keys
```

**SSH Key Requirements:**

- Ed25519 keys (modern, secure)
- Passphrase protected (recommended)
- Stored securely on management machine

### Secrets Management

**Storage:**

- `env/secrets.env` - local management machine only
- Never committed to git (`.gitignore`)
- Copied to nodes via Ansible (encrypted in transit)
- Restricted permissions on nodes (600)

---

## Data Protection

### Backup Encryption

**Restic Encryption:**

- AES-256 encryption
- Password-based key derivation (scrypt)
- Encrypted before upload to B2

**Key Management:**

- Store `RESTIC_PASSWORD` in password manager
- Never share or commit to git
- Use strong password (20+ characters)

### Database Security

**PostgreSQL:**

- Strong unique passwords per database
- Network isolated (127.0.0.1 only)
- Regular encrypted backups

---

## Hardening Checklist

### System Level

- [ ] SSH key-based authentication only
- [ ] Root login disabled
- [ ] Firewall (UFW) enabled
- [ ] Fail2ban installed
- [ ] Automatic security updates enabled
- [ ] Audit logging enabled

### Docker Level

- [ ] Services bind to localhost
- [ ] Official images used where possible
- [ ] Image versions pinned (not :latest)
- [ ] Regular image updates
- [ ] Limited container privileges

### Application Level

- [ ] Strong passwords (16+ characters)
- [ ] Unique passwords per service
- [ ] Secrets in environment files (not hardcoded)
- [ ] HTTPS where possible (via Traefik)

---

## Threat Model

### Attack Vectors & Mitigations

| Threat               | Likelihood | Impact   | Mitigation                          |
| -------------------- | ---------- | -------- | ----------------------------------- |
| SSH Brute Force      | Low        | High     | Key-only auth, fail2ban             |
| Container Escape     | Very Low   | High     | Updated Docker, minimal privileges  |
| Physical Access      | Low        | Critical | Encrypted backups, strong passwords |
| Backup Compromise    | Low        | Critical | Strong encryption password          |
| Tailscale Compromise | Low        | High     | MFA, device authorization           |

---

## Security Monitoring

### Log Monitoring

**Regular Checks:**

```bash
# SSH login attempts
sudo grep "sshd" /var/log/auth.log | tail -n 50

# Firewall blocks
sudo grep "UFW" /var/log/syslog | tail -n 50

# Failed logins
sudo grep "Failed password" /var/log/auth.log | tail -n 20
```

### Automated Monitoring

**Daily Security Audit:**

- Failed SSH attempts
- Firewall status
- Available updates
- Container status
- Disk encryption status

---

## Incident Response

### Response Plan

1. **Detection**: Anomaly detected
2. **Containment**: Isolate affected systems
3. **Eradication**: Remove threat, patch vulnerabilities
4. **Recovery**: Restore from backup
5. **Post-Incident**: Document and prevent recurrence

### Emergency Procedures

**Suspected Compromise:**

```bash
# 1. Disconnect from network
sudo tailscale down

# 2. Stop services
cd /opt/stacks && docker compose down

# 3. Review logs
sudo grep "Accepted publickey" /var/log/auth.log

# 4. Restore from backup
make restore-latest HOST=rpi-home

# 5. Update all credentials
nano env/secrets.env
make deploy-base
make deploy-apps target=rpi-home
```

---

## Security Checklist

### Weekly Tasks

- [ ] Review SSH login attempts
- [ ] Check firewall logs
- [ ] Verify backup success
- [ ] Update system packages

### Monthly Tasks

- [ ] Full security audit
- [ ] Test backup restoration
- [ ] Review user accounts
- [ ] Update Docker images

### Quarterly Tasks

- [ ] Password rotation
- [ ] Full security assessment
- [ ] Disaster recovery drill
- [ ] Update security documentation

---

## Reporting Security Issues

If you discover a security vulnerability:

1. **Do NOT** open a public GitHub issue
2. Email: [your-security-email]
3. Include:
   - Description of issue
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)

**Response Timeline:**

- Acknowledgment: 24 hours
- Assessment: 48 hours
- Fix: 7 days (depending on severity)

---

## Additional Resources

- [Docker Security Best Practices](https://docs.docker.com/engine/security/)
- [Tailscale Security](https://tailscale.com/security/)
- [SSH Hardening Guide](https://www.ssh.com/academy/ssh/hardening)
- [OWASP Top 10](https://owasp.org/www-project-top-ten/)

---

**Last Updated:** $(date)  
**Next Review:** [Date + 3 months]

#### Security Best Practices

When using this homelab:

**Secrets Management:**

- Never commit actual secrets to Git
- Use strong, unique passwords for all services
- Regularly rotate Tailscale auth keys
- Keep backup encryption passwords secure

**Network Security:**

- Keep Tailscale network private (don't expose publicly)
- Regularly update Tailscale client
- Monitor network access logs
- Use firewall rules on individual nodes

**Container Security:**

- Keep Docker images updated
- Monitor security advisories for used images
- Run containers with minimal privileges
- Regularly audit running containers

**System Security:**

- Keep host OS updated
- Use SSH keys instead of passwords
- Regularly audit system access
- Monitor system logs for anomalies

**Backup Security:**

- Use strong encryption for backups
- Secure backup storage credentials
- Test backup integrity regularly
- Limit backup access to necessary systems

#### Security Resources

- [Docker Security Best Practices](https://docs.docker.com/engine/security/)
- [Ansible Security Guide](https://docs.ansible.com/ansible/latest/user_guide/playbooks_vault.html)
- [Tailscale Security Model](https://tailscale.com/security/)

#### Hall of Fame

Contributors who responsibly disclose security issues:

- (None yet - be the first!)

---

**Remember:** This is a self-hosted homelab setup. You are responsible for the security of your own infrastructure. This project provides configurations and best practices, but cannot guarantee security in all environments.
