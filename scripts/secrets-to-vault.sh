#!/usr/bin/env bash
# Print env/secrets.env as a vault_stack_secrets YAML block, ready to paste into
#   ansible-vault edit inventory/group_vars/all.yml
#
# Run it in your own terminal. Its output contains every secret in plain text:
# do not paste it into chats, issues or logs, and do not redirect it to a file.
#
# Usage: scripts/secrets-to-vault.sh [path/to/secrets.env]
set -euo pipefail

src="${1:-env/secrets.env}"
[[ -f "$src" ]] || { echo "ERROR: $src not found" >&2; exit 1; }

echo "vault_stack_secrets:"
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
  [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || { echo "WARNING: skipped a line that is not KEY=value" >&2; continue; }
  key="${BASH_REMATCH[1]}"
  value="${BASH_REMATCH[2]}"
  # YAML single-quoted scalar: double any single quote
  printf "  %s: !unsafe '%s'\n" "$key" "${value//\'/\'\'}"
done < "$src"
