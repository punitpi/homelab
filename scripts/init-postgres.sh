#!/bin/bash
set -e

# This script creates databases and users for applications
# It runs when PostgreSQL container first starts

echo "Creating paperless database and user..."
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE USER paperless WITH PASSWORD '${PAPERLESS_DB_PASSWORD}';
    CREATE DATABASE paperless OWNER paperless;
    GRANT ALL PRIVILEGES ON DATABASE paperless TO paperless;
EOSQL

echo "Database initialization complete!"
