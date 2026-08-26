# Silo Server AIO for Unraid

An all-in-one Docker container and Unraid template for [Silo Server](https://github.com/SomeoneLis/silo-aio-unraid). This image packages the complete backend stack under `s6-overlay v3` process supervision into a single container:

- **Silo Server** — core media application
- **PostgreSQL 18** — hardened with `scram-sha-256` authentication, `pgvector`, and `citext` extensions
- **Redis** — in-memory caching engine
- **Meilisearch v1.13.0** — full-text search engine
- **Hardware acceleration drivers** — Intel Quick Sync, AMD VA-API, and NVIDIA NVENC/NVDEC
- **Node.js 20.x & toolchain** — for on-demand Jellyfin Web UI compilation

---

## Contents

- [Features](#features)
- [Installation on Unraid](#installation-on-unraid)
- [Configuration Reference](#configuration-reference)
- [Hardware Acceleration Setup](#hardware-acceleration-setup)
- [Post-Installation Steps](#post-installation-steps)
- [Troubleshooting](#troubleshooting)
- [License](#license)

---

## Features

- **s6-Overlay v3 Supervision:** Independent process management for PostgreSQL, Redis, Meilisearch, and Silo with automatic restart and health monitoring.
- **Zero-Trust Hardened Database:** Automatically initializes PostgreSQL 18 with enforced `scram-sha-256` password authentication, `pgvector`, and `citext` extensions on first boot.
- **Persistent Key Management:** Generates and locks permanent keys (`secret.key`, `meili.key`, `pgpass.key`, `pgsuper.key`) inside your Unraid `appdata` path to preserve encrypted application settings across container updates.
- **Seamless Transcoding Detection:** Ships with built-in FFmpeg path symlinking (`/usr/lib/jellyfin-ffmpeg/ffmpeg -> /usr/bin/ffmpeg`) so Silo detects hardware capabilities out-of-the-box.
- **Jellyfin Compatibility Toolchain:** Includes Node.js 20.x, `git`, and build utilities required to build and serve the optional Jellyfin Web UI proxy.
- **Performance Optimized:** Scoped appdata permissions prevent slow recursive `chown` operations on boot, and automated log rotation truncates PostgreSQL logs exceeding 50 MB.

---

## Installation on Unraid

### Private App Template (Recommended)

1. Open the **Unraid Terminal** (`>_`) from the WebUI.
2. Download the template directly into your Unraid local template directories:

```bash
curl -sL [https://raw.githubusercontent.com/SomeoneLis/silo-aio-unraid/main/templates/silo-aio.xml](https://raw.githubusercontent.com/SomeoneLis/silo-aio-unraid/main/templates/silo-aio.xml) \
  -o /boot/config/plugins/community.applications/private/LTM/silo-aio.xml
curl -sL [https://raw.githubusercontent.com/SomeoneLis/silo-aio-unraid/main/templates/silo-aio.xml](https://raw.githubusercontent.com/SomeoneLis/silo-aio-unraid/main/templates/silo-aio.xml) \
  -o /boot/config/plugins/dockerMan/templates-user/my-silo-aio.xml

```

3. Navigate to **Apps > Private Apps** in the Unraid WebUI, select **silo-aio**, and click **Install**.

> **Note:** The GHCR image path (`ghcr.io/someonelis/silo-aio`) is lowercase as required by container registries. Repository and raw-file URLs use the canonical `SomeoneLis` casing and are case-sensitive—copy the commands exactly.

---

## Configuration Reference

### Volume Mappings

| Host Path | Container Path | Mode | Description |
| --- | --- | --- | --- |
| `/mnt/user/appdata/silo` | `/var/lib/silo` | Read/Write | Persistent storage for PostgreSQL, Redis, Meilisearch indexes, and key files. |
| `/mnt/user/Media/` | `/mnt/media` | Read-Only | Primary media share containing Movies and TV Shows. |
| `/tmp/silo-transcode` | `/tmp/silo-transcode` | Read/Write | Temporary transcoding buffer stored in RAM (`/tmp`). |

> **Memory Note:** On servers with 16 GB of RAM or less, change the transcode host path from `/tmp/silo-transcode` to an SSD cache share (e.g., `/mnt/cache/appdata/silo/transcode`) to avoid exhausting system memory during heavy transcodes.

---

### Port Mappings

| Host Port | Container Port | Protocol | Description |
| --- | --- | --- | --- |
| `8090` | `8090` | TCP | Web interface and API access. |
| `7700` | `7700` | TCP | Meilisearch API (Optional). |

---

### Environment Variables

| Variable | Default | Description |
| --- | --- | --- |
| `PORT` | `8090` | Internal listening port for the Silo application. |
| `SECRET_KEY` | *(auto-generated)* | Key for securing user tokens. Stored permanently in `/var/lib/silo/secret.key`. |
| `MEILI_MASTER_KEY` | *(auto-generated)* | Master key for internal Meilisearch service. Stored in `/var/lib/silo/meili.key`. |
| `NVIDIA_DRIVER_CAPABILITIES` | `compute,video,utility` | Enables NVENC/NVDEC GPU transcoding capabilities. |
| `NVIDIA_VISIBLE_DEVICES` | `all` | Selects target NVIDIA GPUs (`all` or a specific GPU UUID). |

---

## Hardware Acceleration Setup

### Intel Quick Sync & AMD VA-API

Pass the `/dev/dri` device through to the container. This device path is included by default in the Unraid template.

### NVIDIA GPUs

1. Install the **Nvidia Driver** plugin from the Unraid Community Apps store.
2. Keep `NVIDIA_DRIVER_CAPABILITIES` set to `compute,video,utility`.
3. Keep `NVIDIA_VISIBLE_DEVICES` set to `all` (or enter a specific GPU UUID).

---

## Post-Installation Steps

### 1. Initial Access

Open `http://[YOUR-UNRAID-IP]:8090` in a browser to create your primary administrator account.

### 2. Enable Jellyfin App Support (Optional)

1. In Silo, navigate to **Settings > Compatibility Proxies**.
2. Enable **Jellyfin Proxy**.
3. Click **Install Web UI**. The container's Node.js 20 environment will automatically fetch and build the `jellyfin-web` assets.

---

## Troubleshooting

* **Template Doesn't Appear under Private Apps:** Confirm both `curl` commands completed without errors. A 404 error usually indicates the repository casing was entered incorrectly.
* **GPU Transcoding Not Working:** Verify `/dev/dri` is passed through (Intel/AMD) or the Nvidia Driver plugin is installed (NVIDIA). Check the container log for device probe logs.
* **Settings Reset After Container Rebuild:** Confirm `/mnt/user/appdata/silo` is mapped Read/Write so key files (`secret.key`, `pgpass.key`) persist across container updates.

---

## License

Released under the AGPL-3.0 license. See [`LICENSE`](https://www.google.com/search?q=https://github.com/SomeoneLis/silo-aio-unraid/blob/main/LICENSE).

```

```
