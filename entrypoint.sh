#!/bin/bash
set -e

# Generate a random encryption key if none is supplied
if [ -z "$SECRET_KEY" ]; then
    export SECRET_KEY=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 48)
fi

# Start internal services
service redis-server start
service postgresql start

# Wait until PostgreSQL is fully ready
until pg_isready; do
  echo "Waiting for PostgreSQL database..."
  sleep 1
done

# Initialize database user and schema
su - postgres -c "psql -tc \"SELECT 1 FROM pg_user WHERE usename = 'silo'\" | grep -q 1 || psql -c \"CREATE USER silo WITH PASSWORD 'silo_password';\""
su - postgres -c "psql -tc \"SELECT 1 FROM pg_database WHERE datname = 'silo'\" | grep -q 1 || psql -c \"CREATE DATABASE silo OWNER silo;\""

# Start Silo application
exec /app/silo
