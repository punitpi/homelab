#!/bin/bash
set -euo pipefail

# Load environment variables
source /opt/stacks/env/common.env
source /opt/stacks/env/secrets.env

# Ensure dump directory exists
mkdir -p ${DB_DUMP_PATH}
chmod 700 ${DB_DUMP_PATH}

echo "--- Starting database dump process ---"

# --- PostgreSQL Dump ---
echo "Dumping PostgreSQL databases..."
PG_DUMP_FILE="${DB_DUMP_PATH}/postgres-dump-$(date +%Y%m%d-%H%M%S).sql.gz"
docker exec postgres-base pg_dumpall -U ${POSTGRES_USER} | gzip > ${PG_DUMP_FILE}
echo "PostgreSQL dump complete: ${PG_DUMP_FILE}"

# --- MariaDB/MySQL Dump (Example, commented out) ---
# If you add a MariaDB container, you can use this section.
# echo "Dumping MariaDB databases..."
# MARIADB_DUMP_FILE="${DB_DUMP_PATH}/mariadb-dump-$(date +%Y%m%d-%H%M%S).sql.gz"
# docker exec mariadb-container sh -c 'exec mysqldump -u root -p"$MYSQL_ROOT_PASSWORD" --all-databases' | gzip > ${MARIADB_DUMP_FILE}
# echo "MariaDB dump complete: ${MARIADB_DUMP_FILE}"

echo "--- Database dump process finished ---"
