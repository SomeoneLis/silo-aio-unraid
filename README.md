# Silo Server AIO for Unraid

An all-in-one Docker container and Unraid template for [Silo Server](https://github.com/SomeoneLis/silo-aio-unraid). This image packages the backend stack into a single container:

- **Silo Server** — core media application
- **PostgreSQL 18** — with `pgvector` and `citext` extensions
- **Redis** — in-memory caching
- **Meilisearch v1.13.0** — full-text search engine
- **Hardware acceleration drivers** — Intel Quick Sync, AMD VA-API, and NVIDIA NVENC/NVDEC
- **Node.js 20.x & toolchain** — for on-demand Jellyfin Web UI generation

## Contents

- [Features](#features)
- [Installation on Unraid](#installation-on-unraid)
- [Configuration reference](#configuration-reference)
- [Hardware acceleration setup](#hardware-acceleration-setup)
- [Post-installation steps](#post-installation-steps)
- [Troubleshooting](#troubleshooting)
- [License](#license)

## Features

- **Zero-config database stack** — initializes PostgreSQL 18 with the required vector extensions, Redis, and Meilisearch on first boot.
- **Persistent secret management** — generates and locks a permanent `secret.key` inside your Unraid appdata path, preserving encrypted settings across container rebuilds.
- **Jellyfin compatibility** — ships with Node.js 20.x, git, and the build utilities needed to build and serve the optional Jellyfin Web UI proxy.
- **Automated log rotation** — truncates PostgreSQL logs when they exceed 50 MB, preventing log overflow.
- **Graceful shutdown** — intercepts container stop signals (`SIGTERM`/`SIGINT`) to cleanly stop PostgreSQL, Redis, and Meilisearch, avoiding database corruption.

## Installation on Unraid

### Current Method — Private app template

Open the Unraid terminal (`>_`) from the WebUI and download the template. The two commands place the same file in the Community Applications private directory and the Docker Manager user-template directory, so the template appears under **Apps > Private Apps**:

```bash
curl -sL https://raw.githubusercontent.com/SomeoneLis/silo-aio-unraid/main/templates/silo-aio.xml \
  -o /boot/config/plugins/community.applications/private/LTM/silo-aio.xml
curl -sL https://raw.githubusercontent.com/SomeoneLis/silo-aio-unraid/main/templates/silo-aio.xml \
  -o /boot/config/plugins/dockerMan/templates-user/my-silo-aio.xml
```

Then go to **Apps > Private Apps**, select **silo-aio**, and click **Install**.


> **Note:** The GHCR image path is lowercase (`someonelis`) because container registries normalize namespaces to lowercase. The GitHub repository and raw-file URLs above use the canonical `SomeoneLis` casing and are case-sensitive — copy them exactly.

## Configuration reference

### Volume mappings

| Host path | Container path | Mode | Description |
| --- | --- | --- | --- |
| `/mnt/user/appdata/silo` | `/var/lib/silo` | Read/Write | Persistent storage for PostgreSQL, Redis, Meilisearch indexes, and `secret.key`. |
| `/mnt/user/Media/` | `/mnt/media` | Read-Only | Primary media share containing Movies and TV Shows. |
| `/tmp/silo-transcode` | `/tmp/silo-transcode` | Read/Write | Temporary transcoding buffer, stored in RAM (`/tmp`). |

> **Memory note:** On servers with 16 GB of RAM or less, change the transcode host path from `/tmp/silo-transcode` to an SSD cache share (for example `/mnt/cache/appdata/silo/transcode`) to avoid exhausting system memory during transcodes.

### Port mappings

| Host port | Container port | Protocol | Description |
| --- | --- | --- | --- |
| 8090 | 8090 | TCP | Web interface and API access. |
| 7700 | 7700 | TCP | Meilisearch API (optional). |

### Environment variables

| Variable | Default | Description |
| --- | --- | --- |
| `PORT` | `8090` | Internal listening port for the Silo application. |
| `SECRET_KEY` | *(auto-generated)* | Secures user tokens. Stored permanently in `/var/lib/silo/secret.key`. |
| `MEILI_MASTER_KEY` | *(auto-generated)* | Master key for the internal Meilisearch service. |
| `NVIDIA_DRIVER_CAPABILITIES` | `compute,video,utility` | Enables NVENC/NVDEC GPU transcoding. |
| `NVIDIA_VISIBLE_DEVICES` | `all` | Selects target NVIDIA GPUs (`all` or a GPU UUID). |

## Hardware acceleration setup

### Intel Quick Sync & AMD VA-API

Pass the `/dev/dri` device through to the container. The Unraid template includes this by default.

### NVIDIA GPUs

1. Install the **Nvidia Driver** plugin from the Unraid Community Apps store.
2. Keep `NVIDIA_DRIVER_CAPABILITIES` set to `compute,video,utility`.
3. Keep `NVIDIA_VISIBLE_DEVICES` set to `all`, or enter a specific GPU UUID.

## Post-installation steps

### 1. Initial access

Open `http://[YOUR-UNRAID-IP]:8090` in a browser to create your administrator account.

### 2. Enable Jellyfin app support (optional)

1. In Silo, go to **Settings > Compatibility Proxies**.
2. Enable **Jellyfin Proxy**.
3. Click **Install Web UI**. The built-in Node.js 20 environment fetches and assembles the `jellyfin-web` assets.

## Troubleshooting

- **Template doesn't appear under Private Apps** — confirm both `curl` commands completed without errors and that the `.xml` files exist at the two target paths. A 404 usually means the repository name was copied with the wrong casing.
- **GPU transcoding not working** — verify `/dev/dri` is passed through (Intel/AMD) or the Nvidia Driver plugin is installed (NVIDIA), then check the container log for device-detection messages.
- **Settings reset after a rebuild** — check that `/mnt/user/appdata/silo` is mapped Read/Write so `secret.key` persists.

## License

Released under the AGPL-3.0 license. See [`LICENSE`](https://github.com/SomeoneLis/silo-aio-unraid/blob/main/LICENSE).
