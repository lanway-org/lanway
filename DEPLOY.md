# Deploying a Lanway server

There are three ways to run a server. Pick the one that matches what you have.

| Mode | Use when | Owns port 443? |
|---|---|---|
| **REALITY** (default) | A fresh VPS with nothing else on it | Yes |
| **TLS** | A VPS + a domain, nothing else on 443 | Yes |
| **Proxy** | A VPS that already runs a website on 443 | No — sits behind your site |

---

## Reuse a server that already hosts a website (proxy mode)

This adds Lanway to a box that already serves a site on port 443, **without changing
your website**. Your existing nginx keeps terminating TLS and serving the site; Lanway runs
locally and your nginx forwards one secret path to it. To anyone scanning the server, it's just
your normal website.

### Requirements

- A VPS with **root/SSH** (not shared/cPanel hosting).
- **nginx** already serving your site on 443 with a valid certificate (you have this if the site
  loads over `https://`).
- Docker (the installer adds it if missing).

### 1. Install Lanway in proxy mode

```bash
sudo LANWAY_MODE=proxy LANWAY_DOMAIN=yourdomain.com \
  bash <(curl -fsSL https://get.lanway.org)
```

Lanway starts bound to `127.0.0.1:8444` (only nginx can reach it) and prints:

- a **Manager API URL** and **access key**, and
- an **nginx `location` block** with a randomly generated secret path.

### 2. Add the printed block to your nginx site

Open your site's server block (e.g. `/etc/nginx/sites-enabled/yourdomain`) and paste the
`location …` block the installer printed **inside** the `server { … }` that listens on 443. Then:

```bash
nginx -t && systemctl reload nginx
```

That's it. Normal visitors to `https://yourdomain.com` still get your website. Only Lanway
clients, using the secret WebSocket path, get the tunnel.

### 3. Manage it

Open the **Lanway Manager** app → *Connect to a server* → paste the Manager API URL and access
key. Create users and share keys exactly as normal.

### Good to know

- **Same IP risk:** the VPN and your website share one IP. If a censor blocks that IP, both go
  down together. For a production site you care about, a separate cheap/free VM is safer
  (see below) — but reusing the box is perfectly fine to start.
- **The management API (port 8080)** is served over TLS with a self-signed certificate, so your
  access key is never sent in cleartext. The Manager app trusts it automatically.

---

## Fresh server, no domain (REALITY mode)

```bash
sudo bash <(curl -fsSL https://get.lanway.org)
```

Strongest stealth, nothing to configure. Needs port 443 free.

---

## Fresh server with your own domain (TLS mode)

```bash
sudo LANWAY_DOMAIN=vpn.yourdomain.com bash <(curl -fsSL https://get.lanway.org)
```

Point the domain's DNS at the server first. Needs port 443 free.

---

## Free hosting options

If you'd rather not pay and not touch an existing site:

- **Oracle Cloud — Always Free.** Genuinely free forever; an Arm VM that comfortably runs Lanway.
- **Google Cloud `e2-micro`** free tier.
- **AWS** free tier (12 months).

Spin up an Ubuntu VM on any of them and run the REALITY one-liner above.
