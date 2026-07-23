# Nextcloud Ops & Maintenance Guide

This guide covers day-to-day changes, troubleshooting, and upkeep for the Nextcloud stack.

---

## 1. Start / stop / restart

Use the wrapper script from the project folder:

```bash
# Start
./manage_volume.sh --up

# Stop and remove containers
./manage_volume.sh --down

# Restart
./manage_volume.sh --down && ./manage_volume.sh --up
```

`manage_volume.sh` reads `.env`, starts the containers, and then runs `configure_nextcloud.sh` to sync domains and URLs.

---

## 2. What lives where

| File / path | Purpose |
|-------------|---------|
| `.env` | Secrets, data path, port, domain, tunnel token |
| `docker-compose.yml` | Service definitions (Nextcloud, MariaDB, Cloudflare Tunnel) |
| `manage_volume.sh` | Wrapper: set data dir / port, start, stop |
| `configure_nextcloud.sh` | Syncs `trusted_domains`, `overwrite.cli.url`, `trusted_proxies` into the running Nextcloud config |
| `setup_users.sh` | Creates family accounts from `users.conf` |
| `users.conf.example` | Template for family accounts |
| `NEXTCLOUD_DATA_DIR` (external drive) | Nextcloud source, config, and user files |
| `./db_data` | MariaDB database files (accounts, shares, calendars, etc.) |

**Important:** Your accounts live in the database (`./db_data`), not just in the files on the external drive.

---

## 3. Change the data directory or port

### Option A: use the wrapper flag

```bash
./manage_volume.sh -v /run/media/mc/萤捷/nasDB --up
./manage_volume.sh -p 9090 --up
```

This updates `.env` and restarts the stack.

### Option B: edit `.env` directly

```bash
NEXTCLOUD_DATA_DIR=/run/media/mc/萤捷/nasDB
PORT=8080
```

Then restart:

```bash
./manage_volume.sh --down && ./manage_volume.sh --up
```

---

## 4. Fix a drive that seems to have moved (`萤捷` vs `萤捷1`)

After reboots Linux sometimes creates a new mount folder if the old one is still present.

1. Find the real mount point:

   ```bash
   lsblk
   findmnt -T /run/media/mc/萤捷/nasDB
   findmnt -T /run/media/mc/萤捷1/nasDB
   ```

   The path that returns `tmpfs` or no output is **not** the drive.

2. Update `.env` to the real path:

   ```bash
   NEXTCLOUD_DATA_DIR=/run/media/mc/萤捷/nasDB
   ```

3. Restart the stack.

If you point Nextcloud at an empty folder, it will show the **installer page** instead of the login page.

---

## 5. Add or remove family users

1. Copy the template if you have not already:

   ```bash
   cp users.conf.example users.conf
   ```

2. Edit `users.conf`:

   ```text
   username password Display Name
   mum      Pass123  Mum
   dad      Pass456  Dad
   ```

3. Run the script:

   ```bash
   ./setup_users.sh
   ```

   Existing users are skipped; new users are created.

To remove a user, use OCC directly:

```bash
docker exec nextcloud_container php occ user:delete username
```

---

## 6. Update trusted domains or public URL

Edit `.env`:

```bash
OWN_DOMAIN=drive.example.com
NEXTCLOUD_TRUSTED_DOMAINS=localhost
NEXTCLOUD_OVERWRITE_CLI_URL=https://drive.example.com
NEXTCLOUD_TRUSTED_PROXIES=127.0.0.1 cloudflared
```

Then run:

```bash
./configure_nextcloud.sh
```

`OWN_DOMAIN` is added automatically; you do not need to list it again in `NEXTCLOUD_TRUSTED_DOMAINS`.

---

## 7. Update the Nextcloud image

```bash
./manage_volume.sh --down
docker compose pull
./manage_volume.sh --up
```

After a major version jump, Nextcloud may ask for a database upgrade. Run:

```bash
docker exec nextcloud_container php occ upgrade
```

Always back up first (see section 9).

---

## 8. Back up

Put Nextcloud into maintenance mode before a large backup:

```bash
docker exec nextcloud_container php occ maintenance:mode --on
```

Back up both locations:

```bash
# Nextcloud files and config (replace with your actual path)
rsync -aP /run/media/mc/萤捷/nasDB/ /path/to/backup/nextcloud_data/

# MariaDB database
rsync -aP ./db_data/ /path/to/backup/db_data/
```

Turn maintenance mode off:

```bash
docker exec nextcloud_container php occ maintenance:mode --off
```

---

## 9. Restore

1. Stop the stack:

   ```bash
   ./manage_volume.sh --down
   ```

2. Restore the backups to their original locations.

3. Make sure `.env` points at the restored data directory.

4. Start the stack:

   ```bash
   ./manage_volume.sh --up
   ```

---

## 10. Cloudflare Tunnel

The tunnel token is in `.env`:

```bash
CLOUDFLARE_TUNNEL_TOKEN=...
```

If you change or rotate the token, just update `.env` and restart:

```bash
./manage_volume.sh --down && ./manage_volume.sh --up
```

In the Cloudflare Zero Trust dashboard, the public hostname service should point to:

- **Service type:** `HTTP`
- **URL:** `nextcloud:80`

Cloudflare terminates HTTPS; Nextcloud receives plain HTTP internally.

---

## 11. Common issues

| Symptom | Cause / fix |
|---------|-------------|
| Web shows install page instead of login | Nextcloud is pointing at an empty or wrong data directory. Check `lsblk`, `findmnt`, and `NEXTCLOUD_DATA_DIR` in `.env`. |
| `Untrusted domain` error | Add the domain to `OWN_DOMAIN` or `NEXTCLOUD_TRUSTED_DOMAINS`, then run `./configure_nextcloud.sh`. |
| Uploads fail over HTTPS | Make sure `trusted_proxies` includes `cloudflared`/`127.0.0.1` and do not force `overwriteprotocol=https`. |
| `403` on `/data/htaccesstest.txt` in logs | Normal; `.htaccess` blocks that file. |
| `occ` says "Nextcloud is not installed" | Wait for the container to finish startup, or verify the data directory contains `config/config.php` with `'installed' => true`. |

Check container logs:

```bash
docker logs nextcloud_container --tail 100
docker logs nextcloud_db --tail 100
```

Run OCC commands:

```bash
docker exec nextcloud_container php occ status
docker exec nextcloud_container php occ user:list
```

---

## 12. Security & stability tips

- Never commit `.env`, `users.conf`, or `db_data` to Git (they are already in `.gitignore`).
- Use strong, unique passwords for admin, database, and family accounts.
- Keep regular backups of both the Nextcloud data directory **and** `./db_data`.
- If you want the database on the same external drive as the files, move `./db_data` to the drive and update the MariaDB volume path in `docker-compose.yml`.
