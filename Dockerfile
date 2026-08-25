FROM ghcr.io/silo-server/silo-server:latest AS silo-official

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/usr/lib/postgresql/18/bin:$PATH"
ENV DATABASE_URL=postgres://silo:silo_password@127.0.0.1:5432/silo?sslmode=disable
ENV REDIS_URL=redis://127.0.0.1:6379

# Install prerequisites & add PostgreSQL Official Repository for PG18 + pgvector
RUN apt-get update && apt-get install -y curl gnupg lsb-release \
    && echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb-release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
    && curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg \
    && apt-get update && apt-get install -y \
    postgresql-18 \
    postgresql-18-pgvector \
    redis-server \
    ffmpeg \
    va-driver-all \
    mesa-va-drivers \
    intel-media-va-driver \
    ca-certificates \
    tar \
    && rm -rf /var/lib/apt/lists/*

# Install Meilisearch static binary
RUN curl -sL https://github.com/meilisearch/meilisearch/releases/download/v1.13.0/meilisearch-linux-amd64 -o /usr/local/bin/meilisearch \
    && chmod +x /usr/local/bin/meilisearch

# Copy application assets from official Silo container
COPY --from=silo-official / /

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8090 7700
ENTRYPOINT ["/entrypoint.sh"]
