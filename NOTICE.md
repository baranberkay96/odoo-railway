# NOTICE — Odoo 20 Business Apps Suite

## Software deployed (not redistributed)

| Component | Source | License |
|---|---|---|
| Odoo Community 20.0 | official Docker image `odoo:20.0-20260926` (maintained in https://github.com/odoo/docker) | LGPL-3.0 (Odoo Community; see Odoo's `LICENSE`) |
| nginx | Ubuntu package installed at build time | BSD-2-Clause |
| PostgreSQL | `ghcr.io/railwayapp-templates/postgres-ssl:18` (Railway base) | PostgreSQL License |

## Upstream files checked (2026-10-10)

- `odoo/docker` (branch `master`, commit "[ADD] Odoo: 20.0", 2026-09-26): `20.0/Dockerfile`, `20.0/entrypoint.sh`, `20.0/odoo.conf`, `20.0/wait-for-psql.py`.
- `odoo/odoo` branch `20.0`: `odoo/tools/config.py` (option names, defaults: `http_interface=127.0.0.1`, demo data off by default, `ODOO_<OPTION>` environment mapping) and `odoo/cli/server.py` (refuses the `postgres` DB user).
- Odoo documentation, "System configuration / Deploying Odoo" (workers, `proxy_mode`, `/websocket` routing to the gevent port).

## Original files in this package

- `services/odoo/Dockerfile`, `railway-start.sh`, `nginx.conf.template` — written for this template. The nginx routing follows the requirements in Odoo's deployment documentation; no configuration text was copied from other templates. `railway-start.sh` calls the image's own `wait-for-psql.py`.

## Reused material

- **Railway base definition** `_railway-base/postgres.json`: copied as instructed by STANDARD.md, with `POSTGRES_USER` changed from `postgres` to `odoo` (Odoo refuses to run as `postgres`).
- **Market template `m3dQ_V` "Odoo"** (no license): service pairing and the non-`postgres` superuser idea only. No text copied; all prose and variable descriptions are original.
- `_upstream/praveen-ks-2001__erpnext-railway` (present in this folder) is an ERPNext repository without a license; not used.
