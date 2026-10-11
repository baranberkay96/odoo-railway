# Odoo 20 Business Apps Suite — Railway template spec

## Listing

| Field | Value |
|---|---|
| Name | **Odoo 20 Business Apps Suite** (version label `20` = Odoo major, written as Odoo does: "Odoo 20") |
| Description | CRM, sales, inventory, invoicing and website in one. Odoo with Postgres. (72 chars) |
| Category | Other |
| Tags | odoo, erp, crm, inventory, invoicing, website, postgres |
| User input at deploy | **None.** Master password, administrator password and database password are generated. |

**Listing change:** LISTINGS.md says "…inventory, **accounting** and website…". The full Accounting app is Odoo Enterprise only; Odoo Community (this image) ships **Invoicing** (customer/vendor bills, payments, the accounting engine without the Enterprise reports and dashboards). Replaced "accounting" with "invoicing" to keep the claim accurate.

## Base market template

- **`m3dQ_V` "Odoo"** (331 active) — chosen as base for the service pair (Odoo + Postgres with a non-`postgres` superuser, filestore volume, `/web/health`). Fixed: it starts Odoo with `--init=all` on **every** boot (reinstalls/updates every module each start), runs in threaded mode (`workers=0`) as root (`RAILWAY_RUN_UID=0`), uses the floating `odoo:19.0` tag, sets no master password and leaves the database manager open.
- `odoo-crm-erp` (26 active) — hardcodes the master password in the template (`ADMIN_PASSWD=odoo_master_2026_railway`) and sets `PORT=5432` (Odoo's entrypoint reads `PORT` as the DB port), so Railway's healthcheck cannot work. Nothing taken.
- `erp` is an ERPNext template listed for this slug; not relevant. `_upstream/praveen-ks-2001__erpnext-railway` is an ERPNext repo without a license; not used.

## Pinned versions

| Service | Image | Tag | Release date | Checked |
|---|---|---|---|---|
| Odoo (built from `services/odoo`) | `odoo` (official Docker image) | `20.0-20260926` | Odoo 20.0 added to the official image 2026-09-26 | 2026-10-10 |
| Postgres | `ghcr.io/railwayapp-templates/postgres-ssl` | `18` | Railway base | 2026-10-10 |

Odoo 20.0 is the current stable major (the official image carries 18.0, 19.0 and 20.0; 17.0 was removed on 2026-09-24). The dated tag pins one nightly build. Upgrade within 20.0: bump the tag in `services/odoo/Dockerfile`, set `ODOO_UPDATE_MODULES=all` for one deploy if the release asks for it, then clear it. **Major upgrades** (20.0 → 21.0) need a database migration (Odoo upgrade service or OpenUpgrade) before switching the tag. If you depend on community modules not yet ported to 20.0, change the `FROM` line to a `19.0-<date>` tag before the first deploy.

## Architecture

```
Internet ──HTTPS──▶ Odoo service (one container, volume = /var/lib/odoo)
                     nginx :8080 (public)
                       ├─ /websocket ─▶ 127.0.0.1:8072  Odoo gevent worker (bus, Discuss, live chat)
                       └─ /          ─▶ 127.0.0.1:8069  Odoo prefork HTTP workers (+ cron worker)
                     └─▶ Postgres (private network)
```

**Why nginx inside the container.** With `workers > 0` (needed for production: multi-process, request time/memory limits, a separate cron worker) Odoo serves HTTP on 8069 and WebSockets on the gevent port 8072. A Railway domain targets one port, so a small nginx in the same container listens on `$PORT` and routes `/websocket` to 8072 and everything else to 8069, as in Odoo's documented reverse-proxy setup. A separate proxy service would add a hop and a private-network dependency for no benefit, and Odoo 20 binds to `127.0.0.1` by default, which fits this layout (Odoo is not reachable except through nginx).

**Boot sequence** (`railway-start.sh`): fix ownership of the Railway volume (mounted as root), render `/etc/odoo/odoo.conf` from variables, wait for Postgres, create the database on first boot (`-i base`, no demo data) and set the administrator login/password from variables (on failure the database is dropped so the next start retries cleanly), optionally run `-u <modules>`, then start Odoo as user `odoo` and nginx; if either exits, the container exits and Railway restarts it.

**Production settings rendered into `odoo.conf`:** `proxy_mode = True`, `list_db = False`, `dbfilter = ^<db>$` and `db_name = <db>` (single-database instance), generated `admin_passwd` (master password), `workers = 2`, `max_cron_threads = 1`, `db_maxconn = 16`, memory limits 768 MiB soft / 1 GiB hard per worker, CPU/real time limits 600 s / 1200 s, `http_interface = 127.0.0.1`. nginx passes `X-Forwarded-Host/Proto` and the real client IP (Odoo's login cooldown is per IP).

### Deviations from upstream image defaults (and why)

- Upstream image runs Odoo directly in threaded mode with an `odoo.conf` holding defaults; here a start script renders the production config above and runs nginx next to Odoo.
- Database creation is automated instead of the interactive `/web/database/manager` (which stays disabled unless `ODOO_LIST_DB=True`).
- Odoo 20 also reads `ODOO_<OPTION>` environment variables natively; the variables `ODOO_WORKERS`, `ODOO_MAX_CRON_THREADS`, `ODOO_LIST_DB`, `ODOO_DB_MAXCONN` and `ODOO_LIMIT_*` deliberately use those names, so file and environment agree. SMTP variables use non-Odoo names (`SMTP_*`, `EMAIL_FROM`) because an empty `ODOO_SMTP_PORT` would break Odoo's option parsing.

## Services

All services are created together from the template; references resolve at deploy time. Values are entered exactly as shown.

### Odoo

- **Source:** GitHub repo `baranberkay96/odoo-railway`, root directory `/services/odoo` (Dockerfile build)
- **Start command:** image default
- **Healthcheck:** `/web/health` (timeout 900 s)
- **Public domain:** yes → target port `8080`
- **TCP proxy:** none
- **Volume:** `/var/lib/odoo`
- **Restart policy:** ON_FAILURE (max 10 retries)
- **Replicas:** 1

| Variable | Value | Description |
|---|---|---|
| `PORT` | `8080` | Port nginx listens on (public domain target). Odoo itself listens on 127.0.0.1:8069/8072. |
| `PGHOST` | `${{Postgres.RAILWAY_PRIVATE_DOMAIN}}` | Postgres host (private network). |
| `PGPORT` | `5432` | Postgres port. |
| `PGUSER` | `${{Postgres.POSTGRES_USER}}` | Database user. Must not be 'postgres' (Odoo refuses it). |
| `PGPASSWORD` | `${{Postgres.POSTGRES_PASSWORD}}` | Database password. |
| `ODOO_DB_NAME` | `odoo` | Database Odoo serves (dbfilter and db_name are pinned to it). |
| `ODOO_MASTER_PASSWORD` | `${{secret(32)}}` | Master password (admin_passwd) protecting the database manager: create, duplicate, backup, restore, drop. |
| `ODOO_ADMIN_LOGIN` | `admin` | Login of the administrator user set when the database is created. Use an e-mail address if you prefer. |
| `ODOO_ADMIN_PASSWORD` | `${{secret(20)}}` | Password of the administrator user, set once when the database is created. Change it later in Odoo. |
| `ODOO_AUTO_CREATE_DB` | `true` | Create the database on first boot (no demo data). Set false to create it yourself in /web/database/manager. |
| `ODOO_INIT_MODULES` | `base` | Modules installed at database creation, comma-separated (e.g. base,crm,sale_management,stock). Install the rest from the Apps menu. |
| `ODOO_INIT_LANG` | *(empty)* | Extra language loaded at database creation, e.g. de_DE or tr_TR. Optional. |
| `ODOO_UPDATE_MODULES` | *(empty)* | Modules to update on the next start (e.g. all after a patch upgrade). Clear it again afterwards. Optional. |
| `ODOO_LIST_DB` | `False` | Database manager and selector. Keep False in production; set True temporarily to back up or restore from the UI. |
| `ODOO_WORKERS` | `2` | HTTP worker processes (prefork). Rule of thumb: 2 x vCPU + 1. Must be > 0 for /websocket (live chat, notifications). |
| `ODOO_MAX_CRON_THREADS` | `1` | Scheduled-action workers. |
| `ODOO_DB_MAXCONN` | `16` | Max Postgres connections per Odoo process. Keep (workers + cron + 1) x this below Postgres max_connections (100). |
| `ODOO_LIMIT_MEMORY_SOFT` | `805306368` | Recycle a worker after a request once it uses more than this many bytes (768 MiB). |
| `ODOO_LIMIT_MEMORY_HARD` | `1073741824` | Kill a worker immediately above this many bytes (1 GiB). |
| `ODOO_LIMIT_TIME_CPU` | `600` | Max CPU seconds per request (imports and reports need more than Odoo's 60 s default). |
| `ODOO_LIMIT_TIME_REAL` | `1200` | Max wall-clock seconds per request. |
| `NGINX_CLIENT_MAX_BODY_SIZE` | `256m` | Max upload size (attachments, imports, database restores). |
| `SMTP_HOST` | *(empty)* | Outgoing SMTP server. Optional: you can also configure mail servers in Settings > Technical > Outgoing Mail Servers. |
| `SMTP_PORT` | `587` | SMTP port. |
| `SMTP_STARTTLS` | `True` | Use STARTTLS for SMTP. |
| `SMTP_USER` | *(empty)* | SMTP username. Optional. |
| `SMTP_PASSWORD` | *(empty)* | SMTP password. Optional. |
| `EMAIL_FROM` | *(empty)* | Default sender address, e.g. odoo@yourcompany.com. Optional. |
| `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` | `30` | Let running requests finish on redeploy. |

### Postgres

- **Source:** Docker image `ghcr.io/railwayapp-templates/postgres-ssl:18`
- **Start command:** image default
- **Healthcheck:** none (no HTTP endpoint)
- **Public domain:** no (private network only)
- **TCP proxy:** none
- **Volume:** `/var/lib/postgresql/data`
- **Restart policy:** ON_FAILURE (max 10 retries)
- **Replicas:** 1

| Variable | Value | Description |
|---|---|---|
| `PGDATA` | `/var/lib/postgresql/data/pgdata` | Location where the database will be initialized. |
| `PGHOST` | `${{RAILWAY_PRIVATE_DOMAIN}}` | Railway Private Domain Name. |
| `PGPORT` | `5432` | Port to connect to Postgres. |
| `PGUSER` | `${{ POSTGRES_USER }}` | Required variable for Data panel. |
| `PGDATABASE` | `${{POSTGRES_DB}}` | Required variable for the data panel. |
| `PGPASSWORD` | `${{POSTGRES_PASSWORD}}` | Required variable for Data panel. |
| `POSTGRES_DB` | `railway` | Default database created when image is started. |
| `DATABASE_URL` | `postgresql://${{PGUSER}}:${{POSTGRES_PASSWORD}}@${{RAILWAY_PRIVATE_DOMAIN}}:5432/${{PGDATABASE}}` | URL to connect to Postgres database. |
| `POSTGRES_USER` | `odoo` | Superuser created on first boot. 'odoo' instead of the Railway default 'postgres', which Odoo refuses to use. |
| `SSL_CERT_DAYS` | `820` | SSL certificate expiry in days. |
| `POSTGRES_PASSWORD` | `${{ secret(32, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ") }}` | Password to connect to DB. |
| `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` | `60` | Allow Postgres to cleanly shut down. |

## Improvements over market templates

| # | Change | Why |
|---|---|---|
| 1 | Prefork mode (`workers=2`, cron worker, gevent WebSocket worker) behind in-container nginx routing `/websocket` → 8072 | Production mode per Odoo docs; live chat, Discuss and notifications work through one domain. |
| 2 | No `--init=all` at every start (leader) | Starts in seconds instead of reinstalling all modules on each boot; no risk of data being reset by module re-init. |
| 3 | Database created once on first boot with a generated admin password, no demo data | No `admin/admin`, no exposed database manager during setup. |
| 4 | Generated master password, `list_db=False`, `dbfilter` + `db_name` pinned | Database manager (backup, restore, drop) is closed in production; nobody can create or drop databases from the internet. |
| 5 | Odoo runs as `odoo`, root only fixes volume ownership (market: whole process as root) | Least privilege. |
| 6 | Odoo 20 pinned to a dated build `20.0-20260926` (market: floating `19.0`) | Current stable major, reproducible deploys. |
| 7 | Worker memory/time limits, `db_maxconn` sized for Railway Postgres (100 connections) | Bounded memory, no connection exhaustion, long imports/reports do not time out at 60 s. |
| 8 | Real client IP and HTTPS scheme forwarded (`proxy_mode`, realip) | Correct URLs, secure cookies, per-IP login cooldown works per user. |
| 9 | Healthcheck `/web/health` through nginx | Verifies the full path Railway routes to. |
| 10 | Tested locally (Postgres 18, empty root-owned volume): DB auto-create, admin login with generated password, `admin/admin` rejected, `/websocket` upgrade 101 via nginx, DB manager disabled, restart on the same volume | Fewer surprises on first deploy. |

## First login

1. Wait for the first deploy (database creation takes about a minute).
2. Open the public URL and sign in with `ODOO_ADMIN_LOGIN` / `ODOO_ADMIN_PASSWORD` from the Odoo service variables. Change the password in your user preferences.
3. Install apps from the **Apps** menu (CRM, Sales, Inventory, Invoicing, Website, …). Set the company, country and fiscal localization in Settings.
4. Outgoing mail: Settings → Technical → Outgoing Mail Servers (or the `SMTP_*` variables). Set **web.base.url** if you add a custom domain (Settings → Technical → System Parameters; it updates on admin login by default).

**Backups / database manager:** set `ODOO_LIST_DB=True`, redeploy, use `/web/database/manager` with the master password (`ODOO_MASTER_PASSWORD`) to back up or restore (zip includes the filestore), then set it back to `False`. Railway volume backups of Postgres and `/var/lib/odoo` also work; keep both in sync.

**Custom addons:** fork the template repo, put modules in `services/odoo/addons/`, uncomment the `COPY` line in the Dockerfile, redeploy and install them from Apps.

## Scaling

- More concurrent users: raise `ODOO_WORKERS` (≈ 2 × vCPU + 1; each worker can use up to `ODOO_LIMIT_MEMORY_SOFT`) and keep `(workers + cron + 1) × ODOO_DB_MAXCONN` below Postgres `max_connections` (100).
- Heavy scheduled actions: raise `ODOO_MAX_CRON_THREADS`.
- The Odoo service owns the filestore volume, so it runs as a single replica; scale vertically.

## Resource estimate

Railway prices: RAM $10/GB-month, vCPU $20/vCPU-month, volume $0.15/GB-month. Idle figures measured locally after boot (Odoo 220–300 MB with 2 workers + cron + gevent + nginx; Postgres 110 MB).

| Service | Idle RAM | Typical RAM (10–30 users, a few apps) | Typical CPU |
|---|---|---|---|
| Odoo (nginx + master + 2 HTTP workers + cron + gevent) | 300 MB | 1.2 GB | 0.30 vCPU |
| Postgres | 110 MB | 350 MB | 0.08 vCPU |
| **Total** | **≈0.4 GB** (≈0.03 vCPU) | **≈1.55 GB** | **≈0.38 vCPU** |

- **Idle:** ≈ $4 RAM + $0.6 CPU + $0.3 volumes ≈ **$5/month**.
- **Typical:** ≈ $15.5 RAM + $7.6 CPU + $0.6 volumes (4 GB) ≈ **$24/month**.
- **Minimum plan:** Hobby recommended. Idle usage fits Trial's 1 GB/service, but workers grow past 1 GB with real use and reports, and Trial credit does not cover a month.

## Verification checklist

- [ ] Build from `services/odoo` succeeds; first-boot logs show `Creating database 'odoo'` → `administrator credentials updated` → `Starting Odoo (2 HTTP workers, 1 cron) behind nginx`.
- [ ] Deployment healthy on `/web/health`; the login page loads over HTTPS without mixed-content warnings.
- [ ] Sign in with the generated credentials; `admin`/`admin` is rejected.
- [ ] Install **Discuss** (or CRM) and open it in two browsers → messages appear live (WebSocket through `/websocket`); browser dev tools show a `wss://…/websocket` connection with status 101.
- [ ] Upload an attachment, redeploy the Odoo service → the attachment still downloads (filestore volume).
- [ ] `https://<domain>/web/database/manager` shows "database manager has been disabled".
- [ ] Generate a PDF report (e.g. a quotation) → wkhtmltopdf works.

## Open questions

- **Odoo 20 maturity:** 20.0 has been public for about two weeks; OCA and third-party modules may not be ported yet. Teams that depend on them should start on 19.0 (change the `FROM` tag before the first deploy).
- **First-boot module set:** only `base` is installed automatically; `ODOO_INIT_MODULES` can preinstall apps but larger sets lengthen the first boot (healthcheck timeout is 900 s).
- **Attachment round-trip** was not verified locally (Odoo 20 renamed the RPC field used by the test script); filestore persistence across restarts was verified via the asset bundles and sessions on the volume.
- **SMTP via config file** is a fallback only; Odoo's UI-managed outgoing mail servers take precedence and are the recommended path.
