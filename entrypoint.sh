#!/bin/bash
set -e

# Auto-generate SECRET_KEY if not provided
if [ -z "$SECRET_KEY" ]; then
    export SECRET_KEY=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 48)
fi

# Set a fallback MEILI_MASTER_KEY if empty
if [ -z "$MEILI_MASTER_KEY" ]; then
    export MEILI_MASTER_KEY="silo_aio_meili_default_key_32bytes!"
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

# Background script: Pre-inject Meilisearch configuration directly into PostgreSQL
(
  # Wait for Silo process to start up
  sleep 12
  
  # Inject Meilisearch provider, URL, and key into Silo settings table
  su - postgres -c "psql -d silo -c \"
    INSERT INTO settings (key, value) 
    VALUES 
      ('search.provider', 'meilisearch'), 
      ('search.meili_url', 'http://127.0.0.1:7700'), 
      ('search.meili_key', '$MEILI_MASTER_KEY') 
    ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
  \"" 2>/dev/null || true
)&

# Start Silo application
exec /app/silo
