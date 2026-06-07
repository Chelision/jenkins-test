#!/usr/bin/env bash
set -euo pipefail

SITE_NAME="${SITE_NAME:-www.mumup.asia}"
SOURCE_DIR="${SOURCE_DIR:-dist}"
DEPLOY_ROOT="${DEPLOY_ROOT:-/var/www}"
NGINX_CONF_DIR="${NGINX_CONF_DIR:-/etc/nginx/conf.d}"
PROJECT_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

SOURCE_PATH="${PROJECT_ROOT}/${SOURCE_DIR}"
VHOST_SOURCE="${PROJECT_ROOT}/nginx/vhost/${SITE_NAME}.conf"
DEPLOY_DIR="${DEPLOY_ROOT}/${SITE_NAME}/dist"
VHOST_TARGET="${NGINX_CONF_DIR}/${SITE_NAME}.conf"

if [ ! -d "$SOURCE_PATH" ]; then
  echo "ERROR: build output not found: $SOURCE_PATH"
  echo "Run npm run build before deploying."
  exit 1
fi

if [ ! -f "$VHOST_SOURCE" ]; then
  echo "ERROR: nginx vhost config not found: $VHOST_SOURCE"
  exit 1
fi

echo "Deploy site: $SITE_NAME"
echo "Source dist: $SOURCE_PATH"
echo "Deploy dir: $DEPLOY_DIR"
echo "Nginx config: $VHOST_TARGET"

mkdir -p "$DEPLOY_DIR"
rm -rf "${DEPLOY_DIR:?}/"*
cp -R "$SOURCE_PATH"/. "$DEPLOY_DIR"/

cp "$VHOST_SOURCE" "$VHOST_TARGET"

nginx -t
systemctl reload nginx

echo "Deploy complete: http://${SITE_NAME}"
