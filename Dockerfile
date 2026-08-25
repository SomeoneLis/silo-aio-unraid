FROM ghcr.io/silo-server/silo-server:latest AS silo-official

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV DATABASE_URL=postgres://silo:silo_password@127.0.0.1:5432/silo?sslmode=disable
ENV REDIS_URL=redis://127.0.0.1:6379

# Install PostgreSQL, Redis, FFmpeg, and Intel/AMD GPU drivers
RUN apt-get update && apt-get install -y \
    postgresql postgresql-contrib \
    redis-server \
    ffmpeg \
    va-driver-all \
    mesa-va-drivers \
    intel-media-va-driver \
    ca-certificates \
    curl \
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
