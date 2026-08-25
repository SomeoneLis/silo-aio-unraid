#!/bin/bash
set -e

# Auto-generate SECRET_KEY if not provided
if [ -z "$SECRET_KEY" ]; then
    export SECRET_KEY=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 48)
fi

# Auto-generate MEILI_MASTER_KEY if not provided
if [ -z "$MEILI_MASTER_KEY" ]; then
    export MEILI_MASTER_KEY=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32)
    echo "Generated MEILI_MASTER_KEY: $MEILI_MASTER_KEY"
fi

# Start Redis and PostgreSQL
service redis-server start
service postgresql start

# Wait until PostgreSQL is ready
until pg_isready; do
  echo "Waiting for PostgreSQL database..."
  sleep 1
done

# Initialize database user and database schema
su - postgres -c "psql -tc \"SELECT 1 FROM pg_user WHERE usename = 'silo'\" | grep -q 1 || psql -c \"CREATE USER silo WITH PASSWORD 'silo_password';\""
su - postgres -c "psql -tc \"SELECT 1 FROM pg_database WHERE datname = 'silo'\" | grep -q 1 || psql -c \"CREATE DATABASE silo OWNER silo;\""

# Start Meilisearch in background
mkdir -p /var/lib/silo/meilisearch
meilisearch --db-path /var/lib/silo/meilisearch --http-addr 127.0.0.1:7700 --master-key "$MEILI_MASTER_KEY" --no-analytics &

# Start Silo application
exec /app/silo
