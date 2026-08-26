#!/bin/bash
set -e

# Ensure postgres user and group exist in system
if ! id -u postgres >/dev/null 2>&1; then
    groupadd -r postgres 2>/dev/null || true
    useradd -r -g postgres -d /var/lib/silo/postgres -s /bin/bash postgres
fi

# Export paths and port variables globally
export PATH="/usr/lib/postgresql/18/bin:/app:$PATH"
export PORT="${PORT:-8090}"

# Create appdata base folders
mkdir -p /var/lib/silo/postgres /var/lib/silo/redis /var/lib/silo/meilisearch /var/lib/silo/logs

# --- Helper: generate-or-load a persisted secret file ---
# Usage: load_or_create_key <file> <length> [env_var_override]
load_or_create_key() {
    local file="$1" length="$2" override="$3" val
    if [ -f "$file" ] && [ -s "$file" ]; then
        val="$(tr -d '\r\n' < "$file")"
    elif [ -n "$override" ]; then
        val="$override"
        printf '%s' "$val" > "$file"
    else
        val="$(tr -dc A-Za-z0-9 </dev/urandom | head -c "$length")"
        printf '%s' "$val" > "$file"
    fi
    chmod 600 "$file" 2>/dev/null || true
    printf '%s' "$val"
}

# Persistent SECRET_KEY (encrypts Silo settings; MUST stay stable across rebuilds)
export SECRET_KEY="$(load_or_create_key /var/lib/silo/secret.key 48 "$SECRET_KEY")"

# Persistent MEILI_MASTER_KEY (no more public default constant)
export MEILI_MASTER_KEY="$(load_or_create_key /var/lib/silo/meili.key 48 "$MEILI_MASTER_KEY")"

# Persistent PostgreSQL password for the 'silo' role (no more hardcoded 'silo_password')
PG_PASSWORD="$(load_or_create_key /var/lib/silo/pgpass.key 32 "$PG_PASSWORD")"

# Build DATABASE_URL from the persisted password (overrides any image default)
export DATABASE_URL="postgres://silo:${PG_PASSWORD}@127.0.0.1:5432/silo?sslmode=disable"
export REDIS_URL="${REDIS_URL:-redis://127.0.0.1:6379}"

# --- Ownership: scope it, don't recursively chown the whole appdata every boot ---
# Only the postgres data dir must be owned by postgres. Fix the top-level dirs
# cheaply (non-recursive) and only deep-chown postgres if ownership is wrong.
chown postgres:postgres /var/lib/silo /var/lib/silo/postgres \
    /var/lib/silo/redis /var/lib/silo/meilisearch /var/lib/silo/logs 2>/dev/null || true
if [ "$(stat -c '%U' /var/lib/silo/postgres 2>/dev/null)" != "postgres" ]; then
    chown -R postgres:postgres /var/lib/silo/postgres
fi

# Truncate PostgreSQL log if larger than 50MB to protect appdata disk space
PG_LOG="/var/lib/silo/postgres/logfile"
if [ -f "$PG_LOG" ] && [ "$(stat -c%s "$PG_LOG" 2>/dev/null || echo 0)" -gt 52428800 ]; then
    echo "PostgreSQL log exceeds 50MB. Truncating..."
    tail -n 1000 "$PG_LOG" > "${PG_LOG}.tmp" && mv "${PG_LOG}.tmp" "$PG_LOG"
    chown postgres:postgres "$PG_LOG"
fi

# 1. Start Redis directly
redis-server --daemonize yes

# 2. Initialize PostgreSQL 18 inside persistent appdata
if [ ! -f "/var/lib/silo/postgres/PG_VERSION" ]; then
    echo "No valid database cluster found. Preparing directory and initializing PostgreSQL..."
    rm -rf /var/lib/silo/postgres/* /var/lib/silo/postgres/.* 2>/dev/null || true
    chown -R postgres:postgres /var/lib/silo/postgres
    su postgres -c "/usr/lib/postgresql/18/bin/initdb -D /var/lib/silo/postgres --locale=C.UTF-8 --encoding=UTF8"
fi

su postgres -c "/usr/lib/postgresql/18/bin/pg_ctl -D /var/lib/silo/postgres -l /var/lib/silo/postgres/logfile start"

# 3. Wait for PostgreSQL readiness
until /usr/lib/postgresql/18/bin/pg_isready -h 127.0.0.1 -p 5432; do
  echo "Waiting for PostgreSQL database..."
  sleep 1
done

# 4. Provision database user, database, and vector extensions.
#    Password is set via a parameterized variable so it never appears in shell history
#    or process listings in cleartext, and is (re)applied every boot in case it rotated.
su postgres -c "/usr/lib/postgresql/18/bin/psql -h 127.0.0.1 -v pw=\"'$PG_PASSWORD'\" -c \"CREATE USER silo WITH PASSWORD :pw;\"" 2>/dev/null || true
su postgres -c "/usr/lib/postgresql/18/bin/psql -h 127.0.0.1 -v pw=\"'$PG_PASSWORD'\" -c \"ALTER USER silo WITH PASSWORD :pw;\"" 2>/dev/null || true
su postgres -c "/usr/lib/postgresql/18/bin/psql -h 127.0.0.1 -c \"CREATE DATABASE silo OWNER silo;\"" 2>/dev/null || true
su postgres -c "/usr/lib/postgresql/18/bin/psql -h 127.0.0.1 -d silo -c \"CREATE EXTENSION IF NOT EXISTS vector; CREATE EXTENSION IF NOT EXISTS citext;\""

# Auto-clear corrupted encrypted VAPID setting if present from previous key mismatches
su postgres -c "/usr/lib/postgresql/18/bin/psql -h 127.0.0.1 -d silo -c \"DELETE FROM settings WHERE key = 'notifications.web_push.vapid_keypair';\"" 2>/dev/null || true

# 5. Start Meilisearch in background
meilisearch --db-path /var/lib/silo/meilisearch --http-addr 127.0.0.1:7700 --master-key "$MEILI_MASTER_KEY" --no-analytics &

# 6. Polling loop: Inject Meilisearch credentials once Silo creates settings table.
#    Failures are logged instead of silently discarded, so a schema change upstream
#    is diagnosable via /var/lib/silo/logs/meili-inject.log.
INJECT_LOG="/var/lib/silo/logs/meili-inject.log"
(
  for i in {1..30}; do
    sleep 3
    if su postgres -c "/usr/lib/postgresql/18/bin/psql -h 127.0.0.1 -d silo -c \"SELECT 1 FROM settings LIMIT 1;\"" >/dev/null 2>&1; then
      if su postgres -c "/usr/lib/postgresql/18/bin/psql -h 127.0.0.1 -d silo -v key=\"'$MEILI_MASTER_KEY'\" -c \"
        INSERT INTO settings (key, value)
        VALUES
          ('search.provider', 'meilisearch'),
          ('search.meili_url', 'http://127.0.0.1:7700'),
          ('search.meili_key', :key)
        ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
      \"" >>"$INJECT_LOG" 2>&1; then
        echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') Meilisearch settings injected successfully." >>"$INJECT_LOG"
      else
        echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') WARNING: settings table present but injection failed (schema change?). See errors above." >>"$INJECT_LOG"
      fi
      break
    fi
    if [ "$i" -eq 30 ]; then
      echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') WARNING: settings table never appeared after 90s; Meilisearch not auto-configured." >>"$INJECT_LOG"
    fi
  done
)&

# 7. Locate main Silo binary
SILO_EXEC="/app/silo"
if [ ! -f "$SILO_EXEC" ]; then
    SILO_EXEC=$(which silo 2>/dev/null || which silo-server 2>/dev/null || find / -name "silo" -type f 2>/dev/null | head -n 1)
fi

if [ -z "$SILO_EXEC" ] || [ ! -f "$SILO_EXEC" ]; then
    echo "ERROR: Could not locate Silo executable!"
    exit 1
fi

# 8. Graceful shutdown handler for Unraid stop/restart signals
cleanup() {
    echo "Received termination signal. Shutting down background services gracefully..."
    if [ -n "$SILO_PID" ]; then kill -TERM "$SILO_PID" 2>/dev/null || true; fi
    su postgres -c "/usr/lib/postgresql/18/bin/pg_ctl -D /var/lib/silo/postgres -m fast stop" 2>/dev/null || true
    redis-cli shutdown 2>/dev/null || true
    pkill -f meilisearch 2>/dev/null || true
    exit 0
}

trap cleanup SIGTERM SIGINT

# 9. Start Silo in background and wait
echo "Starting Silo server executable on port $PORT from: $SILO_EXEC"
"$SILO_EXEC" &
SILO_PID=$!

wait "$SILO_PID"
