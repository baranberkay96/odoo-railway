#!/bin/bash
# Odoo on Railway: render odoo.conf from variables, create the database on first
# boot, then run Odoo (as `odoo`) and nginx side by side.
set -euo pipefail

log() { echo "[railway-start] $*"; }
fail() { echo "[railway-start] ERROR: $*" >&2; exit 1; }

DATA_DIR=/var/lib/odoo
ODOO_RC="${ODOO_RC:-/etc/odoo/odoo.conf}"
DB_NAME="${ODOO_DB_NAME:-odoo}"

export PORT="${PORT:-8080}"
export NGINX_CLIENT_MAX_BODY_SIZE="${NGINX_CLIENT_MAX_BODY_SIZE:-256m}"
export PGPORT="${PGPORT:-5432}"

# --- Validate input -------------------------------------------------------------
: "${PGHOST:?PGHOST is required (Postgres private domain)}"
: "${PGUSER:?PGUSER is required}"
: "${PGPASSWORD:?PGPASSWORD is required}"
: "${ODOO_MASTER_PASSWORD:?ODOO_MASTER_PASSWORD is required}"
[ "${PGUSER}" != "postgres" ] || fail "Odoo refuses to run as the 'postgres' database user; use a dedicated superuser (template default: odoo)"
[[ "${DB_NAME}" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ ]] || fail "ODOO_DB_NAME may only contain letters, digits, '_', '.', '-'"

int_or_default() {
  local name="$1" default="$2" value="${!1:-$2}"
  [[ "${value}" =~ ^[0-9]+$ ]] || fail "${name} must be a non-negative integer (got '${value}')"
  echo "${value}"
}
WORKERS="$(int_or_default ODOO_WORKERS 2)"
CRON_THREADS="$(int_or_default ODOO_MAX_CRON_THREADS 1)"
DB_MAXCONN="$(int_or_default ODOO_DB_MAXCONN 16)"
MEM_SOFT="$(int_or_default ODOO_LIMIT_MEMORY_SOFT 805306368)"
MEM_HARD="$(int_or_default ODOO_LIMIT_MEMORY_HARD 1073741824)"
TIME_CPU="$(int_or_default ODOO_LIMIT_TIME_CPU 600)"
TIME_REAL="$(int_or_default ODOO_LIMIT_TIME_REAL 1200)"
SMTP_PORT_VALUE="$(int_or_default SMTP_PORT 587)"

case "${ODOO_LIST_DB:-False}" in
  [Tt]rue|1|yes) LIST_DB=True ;;
  *) LIST_DB=False ;;
esac
case "${SMTP_STARTTLS:-True}" in
  [Ff]alse|0|no) SMTP_SSL=False ;;
  *) SMTP_SSL=True ;;
esac

# --- Volume ownership -------------------------------------------------------------
mkdir -p "${DATA_DIR}"
rm -rf "${DATA_DIR}/lost+found"
if [ "$(stat -c %U "${DATA_DIR}")" != "odoo" ]; then
  log "Fixing ownership of ${DATA_DIR} (first boot on a new volume)"
  chown -R odoo:odoo "${DATA_DIR}"
fi

# --- odoo.conf --------------------------------------------------------------------
umask 077
{
  echo "[options]"
  # Only list the custom addons folder when it actually contains modules (Odoo warns otherwise).
  if [ -n "$(ls -A /mnt/extra-addons 2>/dev/null)" ]; then
    echo "addons_path = /mnt/extra-addons"
  fi
  echo "data_dir = ${DATA_DIR}"
  echo "admin_passwd = ${ODOO_MASTER_PASSWORD}"
  echo "db_host = ${PGHOST}"
  echo "db_port = ${PGPORT}"
  echo "db_user = ${PGUSER}"
  echo "db_password = ${PGPASSWORD}"
  echo "db_name = ${DB_NAME}"
  echo "dbfilter = ^${DB_NAME}\$"
  echo "list_db = ${LIST_DB}"
  echo "proxy_mode = True"
  echo "http_interface = 127.0.0.1"
  echo "http_port = 8069"
  echo "gevent_port = 8072"
  echo "workers = ${WORKERS}"
  echo "max_cron_threads = ${CRON_THREADS}"
  echo "db_maxconn = ${DB_MAXCONN}"
  echo "limit_memory_soft = ${MEM_SOFT}"
  echo "limit_memory_hard = ${MEM_HARD}"
  echo "limit_time_cpu = ${TIME_CPU}"
  echo "limit_time_real = ${TIME_REAL}"
  echo "limit_request = 65536"
  echo "log_level = ${ODOO_LOG_LEVEL:-info}"
  if [ -n "${SMTP_HOST:-}" ]; then
    echo "smtp_server = ${SMTP_HOST}"
    echo "smtp_port = ${SMTP_PORT_VALUE}"
    echo "smtp_ssl = ${SMTP_SSL}"
    [ -z "${SMTP_USER:-}" ] || echo "smtp_user = ${SMTP_USER}"
    [ -z "${SMTP_PASSWORD:-}" ] || echo "smtp_password = ${SMTP_PASSWORD}"
  fi
  [ -z "${EMAIL_FROM:-}" ] || echo "email_from = ${EMAIL_FROM}"
} > "${ODOO_RC}"
umask 022
chown odoo:odoo "${ODOO_RC}"
chmod 600 "${ODOO_RC}"

if [ "${WORKERS}" = "0" ]; then
  log "WARNING: ODOO_WORKERS=0 runs Odoo in threaded mode; /websocket on port 8072 is then unused"
fi

as_odoo() { setpriv --reuid=odoo --regid=odoo --init-groups env HOME="${DATA_DIR}" "$@"; }

# --- Database -----------------------------------------------------------------------
as_odoo /usr/local/bin/wait-for-psql.py --timeout=180 || fail "Postgres not reachable at ${PGHOST}:${PGPORT}"

db_exists() {
  [ "$(as_odoo psql -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname = '${DB_NAME}'" 2>/dev/null)" = "1" ]
}

if ! db_exists; then
  if [ "${ODOO_AUTO_CREATE_DB:-true}" = "true" ]; then
    : "${ODOO_ADMIN_PASSWORD:?ODOO_ADMIN_PASSWORD is required to create the database}"
    log "Creating database '${DB_NAME}' (modules: ${ODOO_INIT_MODULES:-base}); this takes a few minutes"
    init_args=(-c "${ODOO_RC}" -d "${DB_NAME}" -i "${ODOO_INIT_MODULES:-base}" --stop-after-init --no-http)
    [ -z "${ODOO_INIT_LANG:-}" ] || init_args+=("--load-language=${ODOO_INIT_LANG}")
    if ! as_odoo odoo "${init_args[@]}"; then
      log "Database initialisation failed; dropping '${DB_NAME}' so the next start retries cleanly"
      as_odoo dropdb --if-exists "${DB_NAME}" || true
      exit 1
    fi
    log "Setting the administrator login and password"
    if ! as_odoo odoo shell -c "${ODOO_RC}" -d "${DB_NAME}" --no-http <<'PY'
import os
admin = env.ref('base.user_admin')
vals = {'password': os.environ['ODOO_ADMIN_PASSWORD']}
login = (os.environ.get('ODOO_ADMIN_LOGIN') or '').strip()
if login:
    vals['login'] = login
    if '@' in login:
        vals['email'] = login
admin.write(vals)
env.cr.commit()
print('railway-start: administrator credentials updated')
PY
    then
      log "Could not set administrator credentials; dropping '${DB_NAME}' so the next start retries cleanly"
      as_odoo dropdb --if-exists "${DB_NAME}" || true
      exit 1
    fi
  else
    log "Database '${DB_NAME}' does not exist and ODOO_AUTO_CREATE_DB=false."
    log "Set ODOO_LIST_DB=true and open /web/database/manager to create it with the master password."
  fi
fi

if [ -n "${ODOO_UPDATE_MODULES:-}" ] && db_exists; then
  log "Updating modules: ${ODOO_UPDATE_MODULES}"
  as_odoo odoo -c "${ODOO_RC}" -d "${DB_NAME}" -u "${ODOO_UPDATE_MODULES}" --stop-after-init --no-http
fi

# --- nginx + Odoo ----------------------------------------------------------------------
envsubst '${PORT} ${NGINX_CLIENT_MAX_BODY_SIZE}' < /etc/railway/nginx.conf.template > /etc/nginx/nginx.conf
nginx -t -q

log "Starting Odoo (${WORKERS} HTTP workers, ${CRON_THREADS} cron) behind nginx on :${PORT}"
as_odoo odoo -c "${ODOO_RC}" &
ODOO_PID=$!
nginx -g 'daemon off;' &
NGINX_PID=$!

shutdown() {
  kill -TERM "${ODOO_PID}" "${NGINX_PID}" 2>/dev/null || true
}
trap shutdown TERM INT

# Exit (and let Railway restart the container) as soon as either process stops.
set +e
wait -n "${ODOO_PID}" "${NGINX_PID}"
status=$?
shutdown
wait
[ "${status}" -ne 0 ] || status=1
exit "${status}"
