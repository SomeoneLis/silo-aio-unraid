FROM ghcr.io/silo-server/silo-server:latest AS silo-official

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/usr/lib/postgresql/18/bin:/app:$PATH"
ENV DATABASE_URL=postgres://silo:silo_password@127.0.0.1:5432/silo?sslmode=disable
ENV REDIS_URL=redis://127.0.0.1:6379

# 1. Install PostgreSQL 18, Redis, FFmpeg, and GPU drivers on clean Debian
RUN apt-get update && apt-get install -y curl gnupg ca-certificates \
    && curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg \
    && echo "deb http://apt.postgresql.org/pub/repos/apt bookworm-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
    && apt-get update && apt-get install -y \
    postgresql-18 \
    postgresql-18-pgvector \
    redis-server \
    ffmpeg \
    va-driver-all \
    mesa-va-drivers \
    intel-media-va-driver \
    tar \
    findutils \
    && rm -rf /var/lib/apt/lists/*

# 2. Install Meilisearch static binary
RUN curl -sL https://github.com/meilisearch/meilisearch/releases/download/v1.13.0/meilisearch-linux-amd64 -o /usr/local/bin/meilisearch \
    && chmod +x /usr/local/bin/meilisearch

# 3. Copy official image assets and automatically locate/extract the Silo binary
COPY --from=silo-official / /silo-src/
RUN mkdir -p /app \
    && SILO_BIN=$(find /silo-src -type f \( -name "silo" -o -name "silo-server" \) | head -n 1) \
    && echo "Found Silo binary at: $SILO_BIN" \
    && if [ -n "$SILO_BIN" ]; then cp -f "$SILO_BIN" /app/silo; fi \
    && if [ -d "/silo-src/app" ]; then cp -rn /silo-src/app/* /app/ 2>/dev/null || true; fi \
    && if [ -d "/silo-src/web" ]; then cp -rn /silo-src/web /app/ 2>/dev/null || true; fi \
    && chmod +x /app/silo 2>/dev/null || true \
    && rm -rf /silo-src

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8090 7700
ENTRYPOINT ["/entrypoint.sh"]
