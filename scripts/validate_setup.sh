#!/bin/bash
# validate_setup.sh - Comprehensive validation script for homelab setup

set -e

# Check if running in CI mode
CI_MODE=${VALIDATION_MODE:-"local"}

echo "🔍 Homelab Setup Validation"
echo "=========================="
if [[ "$CI_MODE" == "ci" ]]; then
    echo "Running in CI mode - skipping actual secrets validation"
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Validation functions
check_file() {
    if [[ -f "$1" ]]; then
        echo -e "  ✅ $1 ${GREEN}exists${NC}"
        return 0
    else
        echo -e "  ❌ $1 ${RED}missing${NC}"
        return 1
    fi
}

check_env_var() {
    if grep -q "^$1=." "$2" 2>/dev/null; then
        echo -e "  ✅ $1 ${GREEN}defined${NC}"
        return 0
    else
        echo -e "  ❌ $1 ${RED}missing or empty in $2${NC}"
        return 1
    fi
}

validate_secrets() {
    local env_file="$1"
    local required_vars=(
        "TAILSCALE_AUTH_KEY"
        "B2_KEY_ID"
        "B2_APP_KEY"
        "B2_BUCKET"
        "CF_DNS_API_TOKEN"
        "PG_PASSWORD"
        "PAPERLESS_DB_PASSWORD"
        "PAPERLESS_SECRET_KEY"
        "HOMARR_SECRET_KEY"
        "CODE_PASSWORD"
        "CODE_SUDO_PASSWORD"
    )
    
    echo -e "\n📋 Checking required secrets in $env_file:"
    local missing=0
    
    for var in "${required_vars[@]}"; do
        if ! check_env_var "$var" "$env_file"; then
            missing=$((missing + 1))
        fi
    done
    
    return $missing
}

# Every ${VAR} interpolated by the base and apps stacks must be defined in an env file
# (a missing one reaches the container as an empty string and fails late, at runtime).
validate_compose_vars() {
    local missing=0 var
    echo -e "\n🔑 Checking variables used by the stacks are defined:"
    for var in $(grep -ohE '\$\{[A-Z][A-Z0-9_]*\}' stacks/base/compose.yml stacks/apps/compose.yml | tr -d '${}' | sort -u); do
        if ! grep -qE "^${var}=" env/common.env env/secrets.env env/local.env 2>/dev/null; then
            echo -e "  ❌ ${var} ${RED}used in a compose file but not defined in env/*.env${NC}"
            missing=$((missing + 1))
        fi
    done
    [[ $missing -eq 0 ]] && echo -e "  ✅ all compose variables ${GREEN}defined${NC}"
    return $missing
}

# Main validation
echo -e "\n📁 Checking file structure:"
ERRORS=0

# Core files
FILES=(
    "env/common.env"
    "env/secrets.env"
    "stacks/base/compose.yml"
    "stacks/apps/compose.yml"
    "ansible/site.yml"
    "inventory/hosts.ini"
    "Makefile"
    "README.md"
)

for file in "${FILES[@]}"; do
    if ! check_file "$file"; then
        ERRORS=$((ERRORS + 1))
    fi
done

# Check if secrets.env exists, if not check secrets.example.env
if [[ ! -f "env/secrets.env" ]]; then
    echo -e "  ℹ️  secrets.env not found, checking example template..."
    if [[ -f "env/secrets.example.env" ]]; then
        if [[ "$CI_MODE" == "ci" ]]; then
            echo -e "  ${GREEN}✅ secrets.example.env template exists (CI mode)${NC}"
        else
            echo -e "  ${YELLOW}⚠️  Please copy secrets.example.env to secrets.env and fill in values${NC}"
        fi
    fi
else
    if [[ "$CI_MODE" != "ci" ]]; then
        validate_secrets "env/secrets.env" || ERRORS=$((ERRORS + 1))
        validate_compose_vars || ERRORS=$((ERRORS + 1))
    else
        echo -e "  ${GREEN}✅ secrets.env exists (skipping validation in CI mode)${NC}"
    fi
fi

# Check Docker Compose syntax
echo -e "\n🐳 Validating Docker Compose files:"
if command -v docker >/dev/null 2>&1; then
    for stack in stacks/*/compose.yml; do
        if docker compose -f "$stack" config >/dev/null 2>&1; then
            echo -e "  ✅ $(basename $(dirname $stack)) ${GREEN}valid${NC}"
        else
            echo -e "  ❌ $(basename $(dirname $stack)) ${RED}invalid syntax${NC}"
            ERRORS=$((ERRORS + 1))
        fi
    done
else
    echo -e "  ${YELLOW}⚠️  Docker not available, skipping syntax check${NC}"
fi

# Check Ansible syntax
echo -e "\n🔧 Validating Ansible playbooks:"
if command -v ansible-playbook >/dev/null 2>&1; then
    if ansible-playbook --syntax-check ansible/site.yml >/dev/null 2>&1; then
        echo -e "  ✅ Ansible playbook ${GREEN}syntax valid${NC}"
    else
        echo -e "  ❌ Ansible playbook ${RED}syntax error${NC}"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo -e "  ${YELLOW}⚠️  Ansible not available, skipping syntax check${NC}"
fi

# Summary
echo -e "\n📊 Validation Summary:"
if [[ $ERRORS -eq 0 ]]; then
    echo -e "  ${GREEN}🎉 All checks passed! Your homelab setup is ready.${NC}"
    echo -e "\n📋 Next step: make deploy-base (rebuilding a node? see docs/RECOVERY-LOG-2026-11-rpi-home.md)"
else
    echo -e "  ${RED}❌ $ERRORS error(s) found. Please fix them before proceeding.${NC}"
    exit 1
fi