FROM ghcr.io/silo-server/silo-server:latest AS silo-official

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV DATABASE_URL=postgres://silo:silo_password@127.0.0.1:5432/silo?sslmode=disable
ENV REDIS_URL=redis://127.0.0.1:6379

RUN apt-get update && apt-get install -y \
    postgresql postgresql-contrib \
    redis-server \
    ffmpeg \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

COPY --from=silo-official / /

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8090
ENTRYPOINT ["/entrypoint.sh"]
