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
    if grep -q "^$1=" "$2" 2>/dev/null; then
        echo -e "  ✅ $1 ${GREEN}defined${NC}"
        return 0
    else
        echo -e "  ❌ $1 ${RED}missing from $2${NC}"
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
        "PG_PASSWORD"
        "CODE_PASSWORD"
        "ADGUARD_PASSWORD"
    )
    
    echo -e "\n📋 Checking required secrets in $env_file:"
    local missing=0
    
    for var in "${required_vars[@]}"; do
        if ! check_env_var "$var" "$env_file"; then
            ((missing++))
        fi
    done
    
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
        ((ERRORS++))
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
        validate_secrets "env/secrets.env"
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
            ((ERRORS++))
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
        ((ERRORS++))
    fi
else
    echo -e "  ${YELLOW}⚠️  Ansible not available, skipping syntax check${NC}"
fi

# Summary
echo -e "\n📊 Validation Summary:"
if [[ $ERRORS -eq 0 ]]; then
    echo -e "  ${GREEN}🎉 All checks passed! Your homelab setup is ready.${NC}"
    echo -e "\n📋 Next steps:"
    echo "  1. Copy env/secrets.example.env to env/secrets.env"
    echo "  2. Fill in all secret values in secrets.env"  
    echo "  3. Update Tailscale IPs in inventory/hosts.ini"
    echo "  4. Run: make deploy-base"
else
    echo -e "  ${RED}❌ $ERRORS error(s) found. Please fix them before proceeding.${NC}"
    exit 1
fi