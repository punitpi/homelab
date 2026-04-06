# Contributing to Homelab Infrastructure

Thank you for your interest in contributing to this homelab project! This guide will help you get started.

##  Quick Start for Contributors

### Prerequisites

- Docker and Docker Compose
- Ansible (for automation testing)
- Git
- Basic understanding of infrastructure as code

### Development Setup

1. **Fork and Clone**

   ```bash
   git clone https://github.com/YOUR-USERNAME/homelab.git
   cd homelab
   ```

2. **Validate Setup**

   ```bash
   make validate
   ```

3. **Create Development Secrets**
   ```bash
   cp env/secrets.example.env env/secrets.env
   # Fill with test/dummy values for local testing
   ```

##  Types of Contributions

### 🐛 Bug Fixes

- Fix issues with Docker Compose configurations
- Resolve Ansible playbook problems
- Correct documentation errors
- Address security vulnerabilities

### ✨ New Features

- Add new applications/services
- Enhance automation scripts
- Improve monitoring/observability
- Add new deployment targets

### 📚 Documentation

- Improve setup instructions
- Add troubleshooting guides
- Create architecture diagrams
- Write operational runbooks

### 🔧 Infrastructure Improvements

- Optimize Docker configurations
- Enhance Ansible automation
- Improve backup/recovery processes
- Add validation scripts

## 🛠 Development Workflow

### 1. Create a Branch

```bash
git checkout -b feature/your-feature-name
# or
git checkout -b fix/your-bug-fix
```

### 2. Make Changes

- Follow existing code patterns and conventions
- Update documentation for any user-facing changes
- Add/update comments for complex configurations

### 3. Test Your Changes

#### Local Validation

```bash
# Validate all configurations
make validate

# Test Docker Compose syntax
cd stacks/base && docker compose config
cd ../apps && docker compose config

# Test Ansible syntax
cd ansible && ansible-playbook --syntax-check site.yml
```

#### Integration Testing (if possible)

```bash
# Test on a development environment
make deploy-base target=dev-node
make deploy-apps target=dev-node
```

### 4. Update Documentation

- Update `README.md` for new features
- Update `QUICKSTART.md` for setup changes
- Add/update inline comments
- Update architecture docs if needed

### 5. Commit Changes

```bash
git add .
git commit -m "feat: add new service XYZ with monitoring

- Added Docker Compose configuration for XYZ service
- Integrated with existing PostgreSQL database
- Added Ansible deployment automation
- Updated documentation with setup instructions

Closes #123"
```

#### Commit Message Format

We use [Conventional Commits](https://www.conventionalcommits.org/):

- `feat:` - New features
- `fix:` - Bug fixes
- `docs:` - Documentation changes
- `refactor:` - Code refactoring
- `test:` - Adding/updating tests
- `chore:` - Maintenance tasks

### 6. Submit Pull Request

- Push your branch to your fork
- Create a pull request against the `main` branch
- Fill out the pull request template completely
- Link any related issues

##  Code Standards

### Docker Compose

```yaml
# Use consistent service naming
services:
  service-name: # kebab-case
    container_name: service_name # snake_case
    image: image:tag # Always pin versions
    restart: unless-stopped
    environment:
      - VAR_NAME=${ENV_VAR} # Use env vars for configuration
    volumes:
      - ./data:/app/data:rw # Explicit permissions
    networks:
      - homelab
```

### Ansible

```yaml
# Use descriptive task names
- name: Install and configure Docker
  ansible.builtin.package:
    name: docker.io
    state: present
  become: true
  tags: ['docker', 'setup']
```

### Environment Variables

- Use descriptive names: `SERVICE_DATABASE_URL` not `DB_URL`
- Group related variables in sections
- Add comments explaining non-obvious variables
- Never commit actual secrets

### Documentation

- Use clear, concise language
- Include code examples for complex procedures
- Add troubleshooting sections for common issues
- Keep the quick start guide under 5 minutes

## 🧪 Testing Guidelines

### What to Test

- [ ] Docker Compose files validate (`docker compose config`)
- [ ] Ansible playbooks pass syntax check
- [ ] All required environment variables are documented
- [ ] Services start successfully
- [ ] Backup/restore procedures work
- [ ] Documentation is accurate

### Test Environment

If you have access to test hardware:

1. Deploy on a separate environment
2. Test the complete deployment flow
3. Verify service functionality
4. Test backup and restore procedures
5. Test failover scenarios (if applicable)

##  Security Considerations

### Secrets Management

- Never commit actual secrets or credentials
- Use environment variables for all sensitive data
- Test with dummy/example values
- Ensure secrets templates are complete

### Network Security

- Maintain Tailscale-only communication
- Don't expose unnecessary ports
- Follow principle of least privilege
- Document any security implications

### Container Security

- Use official images when possible
- Pin image versions (avoid `latest`)
- Run containers as non-root when possible
- Keep images updated

##  Performance Guidelines

### Resource Efficiency

- Optimize for Raspberry Pi constraints
- Set appropriate resource limits
- Use multi-stage builds for custom images
- Minimize image sizes

### Monitoring

- Add health checks to services
- Include resource monitoring
- Document performance expectations
- Provide tuning guidance

## ❓ Getting Help

### Before Asking

1. Check existing documentation
2. Search existing issues
3. Run `make validate` to check for obvious problems

### Where to Ask

- **GitHub Issues**: Bug reports and feature requests
- **GitHub Discussions**: General questions and ideas
- **Pull Request Comments**: Code review questions

### When Reporting Issues

- Include full error messages
- Provide system information (OS, Docker version, etc.)
- Share relevant configuration (with secrets redacted)
- Describe what you expected vs. what happened

## 🏆 Recognition

Contributors will be:

- Listed in the project README
- Credited in release notes
- Given appropriate GitHub repository permissions (for regular contributors)

## 📜 License

By contributing, you agree that your contributions will be licensed under the same license as the project (see LICENSE file).

---

Thank you for contributing to this homelab project! Your efforts help make self-hosted infrastructure more accessible to everyone. 🙏
