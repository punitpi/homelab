#!/bin/bash
# Runs ON a node (piped over ssh by `make check-urls`): checks each app endpoint.
# A service that is still starting is retried, so slow Pi boots are not reported as DOWN.
# Exit status is non-zero when any service is DOWN after the retries.
#
# Tunables: CHECK_RETRIES (default 6), CHECK_DELAY seconds between tries (default 5).

set -u

RETRIES="${CHECK_RETRIES:-6}"
DELAY="${CHECK_DELAY:-5}"

# service-label:container-name:port
SERVICES=(
    "mealie:mealie:9925"
    "wallos:wallos:8282"
    "sterling-pdf:sterling-pdf:8082"
    "searxng:searxng:8083"
    "code-server:code-server:8443"
    "open-webui:open-webui:8084"
    "audiobookshelf:audiobookshelf:13378"
    "n8n:n8n:5678"
    "homarr:homarr:7575"
    "paperless:paperless-ngx:8000"
)

http_code() {
    # "localhost" (not 127.0.0.1) so Host-validating apps such as Paperless accept the request.
    curl -4 -s -o /dev/null -w "%{http_code}" --max-time 5 "http://localhost:$1" 2>/dev/null
}

container_state() {
    docker inspect -f '{{.State.Status}}{{if .State.Health}}/{{.State.Health.Status}}{{end}}' "$1" 2>/dev/null || echo "missing"
}

printf "%-16s %-7s %-22s %s\n" "Service" "Port" "Container" "HTTP"
printf "%-16s %-7s %-22s %s\n" "-------" "----" "---------" "----"

down=0
for entry in "${SERVICES[@]}"; do
    IFS=: read -r label container port <<<"$entry"

    code="000"
    for ((i = 1; i <= RETRIES; i++)); do
        code="$(http_code "$port")"
        [[ "$code" != "000" ]] && break
        ((i < RETRIES)) && sleep "$DELAY"
    done

    case "$code" in
        2* | 3* | 401 | 403) result="OK ($code)" ;;
        000) result="DOWN"; down=$((down + 1)) ;;
        *) result="? ($code)" ;;
    esac

    printf "%-16s %-7s %-22s %s\n" "$label" ":$port" "$(container_state "$container")" "$result"
done

echo
if ((down > 0)); then
    echo "$down service(s) DOWN after ${RETRIES} tries ${DELAY}s apart. Check: docker logs <container>"
    exit 1
fi
echo "All services answering."
