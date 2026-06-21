# Lanway server

A small Go service that supervises an [Xray-core](https://github.com/XTLS/Xray-core) process and
exposes a Bearer-token REST API for the Manager app. It stores its state only on the machine it
runs on — there is no external database and no Lanway-operated backend.

## Run with Docker

```bash
bash <(curl -fsSL https://get.lanway.org)
```

Or manually:

```bash
docker compose up -d
docker logs lanway        # shows the Manager API URL and access key
```

State (config, user list, generated keys) lives in `/opt/lanway` on the host.

## Run from source

Requires Go 1.22+ and the `xray` binary on your `PATH`.

```bash
LANWAY_CONFIG_DIR=./data LANWAY_XRAY_BIN=$(which xray) go run ./cmd/lanway
```

## Stealth modes

| Mode | When | How it hides |
|---|---|---|
| `reality` (default) | No domain | VLESS + XTLS-Vision + REALITY. Borrows the TLS handshake of a real site (`reality.dest`, default `www.microsoft.com:443`). |
| `tls` | You own a domain | VLESS + WebSocket + TLS with a Let's Encrypt certificate; a decoy site is served on `/`. |

Switch modes by editing `mode` in `/opt/lanway/lanway.json` and restarting the container.

## Environment

| Variable | Default | Purpose |
|---|---|---|
| `LANWAY_CONFIG_DIR` | `/config` | Where state is stored |
| `LANWAY_XRAY_BIN` | `xray` | Path to the Xray executable |
| `LANWAY_PUBLIC_HOST` | _(auto)_ | IP/domain advertised in share links |
| `LANWAY_API_KEY` | _(generated)_ | Pre-seed the access key (used by one-click deploy) |

## API

See the table in the [root README](../README.md#server-api). All routes except `/api/health`
require `Authorization: Bearer <access-key>`.
