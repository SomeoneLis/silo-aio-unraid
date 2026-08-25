FROM ghcr.io/silo-server/silo-server:latest AS silo-official

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/usr/lib/postgresql/18/bin:/app:$PATH"
ENV PORT=8090
ENV DATABASE_URL=postgres://silo:silo_password@127.0.0.1:5432/silo?sslmode=disable
ENV REDIS_URL=redis://127.0.0.1:6379

# 1. Install PostgreSQL 18, Redis, FFmpeg, libvips, GPU drivers, git, and Node.js 20
RUN apt-get update && apt-get install -y --no-install-recommends curl gnupg ca-certificates \
    && curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg \
    && echo "deb http://apt.postgresql.org/pub/repos/apt bookworm-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get update && apt-get install -y --no-install-recommends \
    postgresql-18 \
    postgresql-18-pgvector \
    redis-server \
    ffmpeg \
    libvips42 \
    libvips-tools \
    intel-media-va-driver \
    mesa-va-drivers \
    git \
    nodejs \
    findutils \
    tar \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /root/.npm

# 2. Install Meilisearch static binary
RUN curl -sL https://github.com/meilisearch/meilisearch/releases/download/v1.13.0/meilisearch-linux-amd64 -o /usr/local/bin/meilisearch \
    && chmod +x /usr/local/bin/meilisearch

# 3. Extract Silo application assets
COPY --from=silo-official / /silo-src/
RUN mkdir -p /app \
    && SILO_BIN=$(find /silo-src -type f \( -name "silo" -o -name "silo-server" \) | head -n 1) \
    && echo "Found Silo binary at: $SILO_BIN" \
    && if [ -n "$SILO_BIN" ]; then cp -f "$SILO_BIN" /app/silo; fi \
    && if [ -d "/silo-src/app" ]; then cp -rn /silo-src/app/* /app/ 2>/dev/null || true; fi \
    && if [ -d "/silo-src/web" ]; then cp -rn /silo-src/web /app/ 2>/dev/null || true; fi \
    && if [ -d "/silo-src/usr/local/lib" ]; then cp -rn /silo-src/usr/local/lib/* /usr/local/lib/ 2>/dev/null || true; fi \
    && chmod +x /app/silo 2>/dev/null || true \
    && ldconfig \
    && rm -rf /silo-src /root/.npm

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD curl -f http://localhost:8090/ || exit 1

EXPOSE 8090 7700
ENTRYPOINT ["/entrypoint.sh"]
