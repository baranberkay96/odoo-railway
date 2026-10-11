# Odoo for Railway: official image + a small in-container nginx.
#
# With workers > 0 Odoo serves HTTP on 8069 and WebSockets (bus, live chat,
# notifications) on the gevent port 8072. Railway routes one public domain to one
# port, so nginx listens on $PORT and splits /websocket -> 8072, everything else -> 8069,
# as in Odoo's documented reverse-proxy setup. Odoo itself only listens on 127.0.0.1.
#
# Upgrade inside the 20.0 series: bump the dated tag below and redeploy
# (set ODOO_UPDATE_MODULES=all for one deploy if the release notes ask for it).
# A major upgrade (e.g. 20.0 -> 21.0) needs a database migration first; do not just bump the tag.
FROM odoo:20.0-20260926

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends nginx gettext-base \
    && rm -rf /var/lib/apt/lists/* /etc/nginx/sites-enabled/default

COPY nginx.conf.template /etc/railway/nginx.conf.template
COPY --chmod=0755 railway-start.sh /usr/local/bin/railway-start.sh

# Custom or OCA addons: put them in ./addons next to this Dockerfile and uncomment.
# COPY --chown=odoo:odoo addons /mnt/extra-addons

ENV ODOO_RC=/etc/odoo/odoo.conf

EXPOSE 8080

# Starts as root to fix volume ownership; Odoo itself runs as the `odoo` user.
ENTRYPOINT ["/usr/local/bin/railway-start.sh"]
CMD []
