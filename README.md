# Nextcloud Family Cloud Setup

## Summary

This project turns your PC into a private cloud storage server for your whole family using **Nextcloud** on Docker. Family members can upload photos, videos, documents, and more — from home or anywhere in the world.

| Feature | Detail |
|---|---|
| Storage backend | Nextcloud (latest) |
| Database | MariaDB (local `./db_data/` on your drive) |
| Users supported | 4–6 family members |
| Local access | `http://localhost:8080` |
| Remote access | Free Cloudflare Tunnel (HTTPS, no port forwarding) |
| Upload limit | 16 GB per file (photos, videos, docs) |
| User management | Script-based (`setup_users.sh`) |

**How it works:**
1. Nextcloud + MariaDB run as Docker containers on your PC
2. Your family connects locally over Wi-Fi, or remotely through a secure Cloudflare Tunnel
3. Each family member gets their own login and private storage space
4. All data stays on your own hard drive — no third-party cloud

---

## Prerequisites
- Docker and Docker Compose installed
- A free [Cloudflare](https://www.cloudflare.com/) account (for remote access)

## Files
| File | Purpose |
|---|---|
| `Dockerfile` | Nextcloud container definition |
| `docker-compose.yml` | Full stack: Nextcloud + MariaDB + Cloudflare Tunnel |
| `manage_volume.sh` | Start/stop the stack; set volume dir and port |
| `configure_nextcloud.sh` | Sync trusted domains / overwrite URL into live Nextcloud config |
| `setup_users.sh` | Create family accounts via Nextcloud OCC CLI |
| `.env` | Secret credentials (not committed to Git) |
| `.env.example` | Template for `.env` |
| `users.conf.example` | Template for family user accounts |

---

## Setup

### 1. Configure environment
```bash
cp .env.example .env
```
Edit `.env` and fill in:
- `NEXTCLOUD_ADMIN_USER` / `NEXTCLOUD_ADMIN_PASSWORD` — admin login
- `MYSQL_ROOT_PASSWORD` / `MYSQL_PASSWORD` — database credentials
- `CLOUDFLARE_TUNNEL_TOKEN` — from Cloudflare dashboard (see step 3)
- `OWN_DOMAIN` — your Cloudflare public hostname
- `NEXTCLOUD_OVERWRITE_CLI_URL` — optional explicit public URL
- `NEXTCLOUD_TRUSTED_DOMAINS` — optional extra trusted domains besides `localhost` and `OWN_DOMAIN`
- `NEXTCLOUD_TRUSTED_PROXIES` — optional reverse proxies such as `127.0.0.1 cloudflared`

### 2. Start the stack
```bash
# Start with defaults
./manage_volume.sh --up

# Start with a custom data directory
./manage_volume.sh -v /mnt/my_drive/nextcloud_data --up

# Start with a custom port
./manage_volume.sh -p 9090 --up
```
`manage_volume.sh --up` now also syncs `trusted_domains`, `overwrite.cli.url`, and optional `trusted_proxies` into the live Nextcloud config so a fresh install on another PC is much less likely to hit the untrusted-domain issue.

Access Nextcloud locally at: `http://localhost:8080`

### 3. Set up Cloudflare Tunnel (remote access)

Cloudflare Tunnel gives your family a secure public HTTPS URL to access Nextcloud from anywhere — no router port forwarding, no static IP needed. It's free.

#### Step-by-step

**A. Create a Cloudflare account**
1. Go to [https://www.cloudflare.com/](https://www.cloudflare.com/) and sign up for a free account
2. You do **not** need to own a domain — Cloudflare provides a free `*.trycloudflare.com` subdomain, or you can use your own

**B. Create a tunnel**
1. Log in to [Cloudflare Zero Trust](https://one.dash.cloudflare.com/)
2. In the left sidebar go to **Networks → Tunnels**
3. Click **Create a tunnel**
4. Choose **Cloudflared** as the connector type
5. Name your tunnel (e.g. `home-nextcloud`) and click **Save tunnel**
6. On the next screen, copy the **tunnel token** — it looks like a long string starting with `eyJ...`

**C. Configure your `.env`**
```bash
# Paste your token into .env
CLOUDFLARE_TUNNEL_TOKEN=eyJ.....your_token_here
```

**D. Add a public hostname**
1. Still in the tunnel settings, go to the **Public Hostname** tab
2. Click **Add a public hostname**
3. Fill in:
   - **Subdomain**: e.g. `cloud` (or leave blank for root)
   - **Domain**: your domain, or use the free Cloudflare one
   - **Service Type**: `HTTP`
   - **URL**: `nextcloud:80`
4. Click **Save**
5. Note your full public URL (e.g. `https://cloud.yourfamily.com`)

**E. Trust the domain in Nextcloud**

Add your hostname to `OWN_DOMAIN` in `.env`:
```bash
OWN_DOMAIN=cloud.yourfamily.com
NEXTCLOUD_TRUSTED_DOMAINS=localhost
```

Optional if you want to force a specific public URL or proxy list:
```bash
NEXTCLOUD_OVERWRITE_CLI_URL=https://cloud.yourfamily.com
NEXTCLOUD_TRUSTED_PROXIES=127.0.0.1 cloudflared
```

**F. Restart the stack**
```bash
./manage_volume.sh --down && ./manage_volume.sh --up
```

The startup script will automatically add `OWN_DOMAIN` to Nextcloud's live `trusted_domains`.

Family members can now open `https://cloud.yourfamily.com` in any browser or the Nextcloud mobile app.

> **Security tip:** Cloudflare handles HTTPS automatically. You can also enable Cloudflare Access policies to require login before even reaching the Nextcloud login page.

### 4. Create family accounts
```bash
cp users.conf.example users.conf
```
Edit `users.conf` — one user per line:
```
username   password   Display Name
mum        SecurePass Mum
dad        SecurePass Dad
alice      SecurePass Alice
```
Then run:
```bash
chmod +x setup_users.sh
./setup_users.sh
```
Use a custom config file:
```bash
./setup_users.sh --conf /path/to/users.conf
```

---

## Managing the Stack

| Command | Description |
|---|---|
| `ls "/run/media/mc/萤捷/nasDB"` | Start the stack |
| `./manage_volume.sh --down` | Stop and remove the stack |
| `./manage_volume.sh -v /path/to/data` | Change data dir and restart |
| `./manage_volume.sh -p 9090` | Change port and restart |

## Notes
- MariaDB data is stored locally in `./db_data/` (excluded from Git)
- Nextcloud data defaults to `/var/nextcloud_data` (overridable via `-v`)
- Upload limit is set to **16GB** to support large video files
- `db_data/`, `.env`, and `users.conf` are excluded from Git via `.gitignore`

## Stopping and Removing the Container
```bash
./manage_volume.sh --down
```# nextcloudenv
