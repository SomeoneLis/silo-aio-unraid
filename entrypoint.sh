#!/bin/bash
set -e

# Ensure postgres user and group exist in system
if ! id -u postgres >/dev/null 2>&1; then
    groupadd -r postgres 2>/dev/null || true
    useradd -r -g postgres -d /var/lib/silo/postgres -s /bin/bash postgres
fi

# Export PostgreSQL binary path globally
export PATH="/usr/lib/postgresql/18/bin:$PATH"

# Auto-generate SECRET_KEY if empty
if [ -z "$SECRET_KEY" ]; then
    export SECRET_KEY=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 48)
fi

# Fallback MEILI_MASTER_KEY
if [ -z "$MEILI_MASTER_KEY" ]; then
    export MEILI_MASTER_KEY="silo_aio_meili_default_key_32bytes!"
fi

# Create persistent appdata subdirectories and assign ownership
mkdir -p /var/lib/silo/postgres /var/lib/silo/redis /var/lib/silo/meilisearch
chown -R postgres:postgres /var/lib/silo/postgres

# 1. Start Redis
service redis-server start

# 2. Initialize and start PostgreSQL 18 inside persistent appdata (/var/lib/silo/postgres)
if [ ! -s "/var/lib/silo/postgres/PG_VERSION" ]; then
    echo "Initializing new PostgreSQL database cluster in appdata..."
    su postgres -c "/usr/lib/postgresql/18/bin/initdb -D /var/lib/silo/postgres"
fi

su postgres -c "/usr/lib/postgresql/18/bin/pg_ctl -D /var/lib/silo/postgres -l /var/lib/silo/postgres/logfile start"

# 3. Wait for PostgreSQL readiness
until /usr/lib/postgresql/18/bin/pg_isready -h 127.0.0.1 -p 5432; do
  echo "Waiting for PostgreSQL database..."
  sleep 1
done

# 4. Provision database user, database, and vector extensions
su postgres -c "/usr/lib/postgresql/18/bin/psql -h 127.0.0.1 -c \"CREATE USER silo WITH PASSWORD 'silo_password';\"" 2>/dev/null || true
su postgres -c "/usr/lib/postgresql/18/bin/psql -h 127.0.0.1 -c \"CREATE DATABASE silo OWNER silo;\"" 2>/dev/null || true
su postgres -c "/usr/lib/postgresql/18/bin/psql -h 127.0.0.1 -d silo -c \"CREATE EXTENSION IF NOT EXISTS vector; CREATE EXTENSION IF NOT EXISTS citext;\""

# 5. Start Meilisearch in background
meilisearch --db-path /var/lib/silo/meilisearch --http-addr 127.0.0.1:7700 --master-key "$MEILI_MASTER_KEY" --no-analytics &

# 6. Polling loop: Wait until Silo creates the settings table before injecting Meilisearch credentials
(
  for i in {1..30}; do
    sleep 3
    if su postgres -c "/usr/lib/postgresql/18/bin/psql -h 127.0.0.1 -d silo -c \"SELECT 1 FROM settings LIMIT 1;\"" >/dev/null 2>&1; then
      su postgres -c "/usr/lib/postgresql/18/bin/psql -h 127.0.0.1 -d silo -c \"
        INSERT INTO settings (key, value) 
        VALUES 
          ('search.provider', 'meilisearch'), 
          ('search.meili_url', 'http://127.0.0.1:7700'), 
          ('search.meili_key', '$MEILI_MASTER_KEY') 
        ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
      \"" >/dev/null 2>&1
      break
    fi
  done
)&

# 7. Start main Silo application
exec /app/silo
