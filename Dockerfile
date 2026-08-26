FROM ghcr.io/silo-server/silo-server:latest AS silo-official

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/usr/lib/postgresql/18/bin:/app:$PATH"
ENV PORT=8090
# NOTE: DATABASE_URL / MEILI / PG credentials are generated and exported at runtime
# by the init script (persisted under /var/lib/silo). They are intentionally NOT baked
# into the image so no secret ends up in a public image layer.
ENV REDIS_URL=redis://127.0.0.1:6379
# s6-overlay behaviour: wait for init (cont-init.d) to finish before starting
# supervised services, and bring the whole container down if a service keeps failing.
ENV S6_BEHAVIOUR_IF_STAGE2_FAILS=2
ENV S6_CMD_WAIT_FOR_SERVICES_MAXTIME=0
ENV S6_KEEP_ENV=1

ARG S6_OVERLAY_VERSION=3.2.0.2

# 1. Install PostgreSQL 18, Redis, FFmpeg, libvips, GPU drivers, git, Node.js 20, and xz for s6
RUN apt-get update && apt-get install -y --no-install-recommends curl gnupg ca-certificates xz-utils \
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

# 2. Install s6-overlay (process supervisor)
RUN curl -sL "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz" -o /tmp/s6-noarch.tar.xz \
    && curl -sL "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-x86_64.tar.xz" -o /tmp/s6-x86_64.tar.xz \
    && tar -C / -Jxpf /tmp/s6-noarch.tar.xz \
    && tar -C / -Jxpf /tmp/s6-x86_64.tar.xz \
    && rm -f /tmp/s6-noarch.tar.xz /tmp/s6-x86_64.tar.xz

# 3. Install Meilisearch static binary
RUN curl -sL https://github.com/meilisearch/meilisearch/releases/download/v1.13.0/meilisearch-linux-amd64 -o /usr/local/bin/meilisearch \
    && chmod +x /usr/local/bin/meilisearch

# 4. Extract Silo application assets
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

# 5. Install s6 service definitions and the one-time init script
COPY rootfs/ /
RUN chmod +x /etc/cont-init.d/* /etc/services.d/*/run /etc/services.d/*/finish 2>/dev/null || true

# Healthcheck verifies the web app AND the bundled data services, so a dead
# Postgres/Redis/Meili marks the container unhealthy instead of silently degrading.
HEALTHCHECK --interval=30s --timeout=5s --start-period=45s --retries=3 \
  CMD curl -f http://localhost:8090/ >/dev/null 2>&1 \
      && /usr/lib/postgresql/18/bin/pg_isready -h 127.0.0.1 -p 5432 >/dev/null 2>&1 \
      && redis-cli ping >/dev/null 2>&1 \
      && curl -f http://127.0.0.1:7700/health >/dev/null 2>&1 \
      || exit 1

EXPOSE 8090 7700
ENTRYPOINT ["/init"]
