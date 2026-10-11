# Deploy and Host Odoo with Railway

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/odoo-20-business-apps-suite)

Odoo is an open-source suite of business apps: CRM, sales, inventory, invoicing, website, e-commerce, project, helpdesk and more, all on one database. This community template deploys Odoo 20 Community from the official image on Railway with Postgres, production worker mode, a persistent filestore and a secured database manager.

## About Hosting Odoo

A production Odoo server runs several worker processes for web requests, a cron worker for scheduled actions and a separate gevent process for WebSockets (live chat, Discuss, notifications), behind a reverse proxy that sends `/websocket` to the gevent port. It needs Postgres and a persistent data directory for attachments and sessions. This template runs Odoo and a small nginx in one service with a volume for the data directory, renders `odoo.conf` from Railway variables, creates the database on first boot with a generated administrator password, disables the public database manager and pins the database filter. Postgres runs as its own service.

## Common Use Cases

- Running CRM and sales quotations for a growing company without per-user SaaS fees
- Managing inventory, warehouses and purchase orders together with invoicing
- Publishing a company website or simple web shop backed by the same product catalogue
- Starting a self-hosted ERP that grows by installing additional Odoo apps over time

## Dependencies for Odoo Hosting

- Odoo 20 Community (official `odoo:20.0-20260926` image, extended with nginx)
- PostgreSQL (Railway Postgres 18, superuser `odoo`)
- Persistent volume for `/var/lib/odoo` (filestore and sessions)

### Deployment Dependencies

- Odoo official Docker image: https://hub.docker.com/_/odoo
- Odoo deployment guide (workers, proxy mode, WebSocket routing): https://www.odoo.com/documentation/master/administration/on_premise/deploy.html
- Odoo Community source: https://github.com/odoo/odoo
- Railway Postgres: https://docs.railway.com/databases/postgresql

### Implementation Details

| Service | Image | Role |
|---|---|---|
| Odoo | built from `services/odoo` (`odoo:20.0-20260926` + nginx) | nginx on the public domain; Odoo HTTP workers, cron worker and WebSocket worker on localhost; filestore volume |
| Postgres | `ghcr.io/railwayapp-templates/postgres-ssl:18` | Database (volume) |

**First login:** open the public URL and sign in with `ODOO_ADMIN_LOGIN` and the generated `ODOO_ADMIN_PASSWORD` from the Odoo service variables. Install the apps you need from the Apps menu. The database manager is disabled; to back up or restore from the UI, set `ODOO_LIST_DB=True` temporarily and use the generated `ODOO_MASTER_PASSWORD`.

**Scaling:** raise `ODOO_WORKERS` (about two per vCPU plus one) and the service memory; keep `(workers + cron + 1) × ODOO_DB_MAXCONN` below Postgres' connection limit. The service owns the filestore volume, so it scales vertically.

**Versions:** the Odoo build is pinned in `services/odoo/Dockerfile`. Newer 20.0 builds can be pinned there (run `ODOO_UPDATE_MODULES=all` once if needed). Moving to a new major version requires a database migration first.

### Why Deploy Odoo on Railway?

Railway gives Odoo a managed Postgres, a persistent volume and an HTTPS domain in one project, with usage-based billing and simple vertical scaling. You get a production-mode Odoo with WebSockets and a locked-down database manager without running your own server or proxy.
