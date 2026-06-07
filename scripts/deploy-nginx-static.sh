#!/usr/bin/env bash
set -euo pipefail

SITE_NAME="${SITE_NAME:-www.mumup.asia}"
SOURCE_DIR="${SOURCE_DIR:-dist}"
DEPLOY_ROOT="${DEPLOY_ROOT:-/var/www}"
NGINX_CONF_DIR="${NGINX_CONF_DIR:-/etc/nginx/conf.d}"
PROJECT_KEY="${PROJECT_KEY:-${JOB_NAME:-unknown-project}}"
RELEASE_ID="${RELEASE_ID:-${BUILD_NUMBER:-$(date +%Y%m%d%H%M%S)}}"
PROJECT_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

SOURCE_PATH="${PROJECT_ROOT}/${SOURCE_DIR}"
VHOST_SOURCE="${PROJECT_ROOT}/nginx/vhost/${SITE_NAME}.conf"
SITE_ROOT="${DEPLOY_ROOT}/${SITE_NAME}"
RELEASES_DIR="${SITE_ROOT}/releases"
CURRENT_LINK="${SITE_ROOT}/current"
SAFE_RELEASE_ID="$(printf '%s' "$RELEASE_ID" | tr -c 'A-Za-z0-9._-' '-')"
RELEASE_DIR="${RELEASES_DIR}/${SAFE_RELEASE_ID}"
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
echo "Project key: $PROJECT_KEY"
echo "Source dist: $SOURCE_PATH"
echo "Release dir: $RELEASE_DIR"
echo "Current link: $CURRENT_LINK"
echo "Nginx config: $VHOST_TARGET"

mkdir -p "$RELEASES_DIR"

if [ -e "$RELEASE_DIR" ]; then
  echo "ERROR: release already exists: $RELEASE_DIR"
  exit 1
fi

mkdir -p "$RELEASE_DIR"
cp -R "$SOURCE_PATH"/. "$RELEASE_DIR"/

ln -sfn "$RELEASE_DIR" "$CURRENT_LINK"

cp "$VHOST_SOURCE" "$VHOST_TARGET"

nginx -t
systemctl reload nginx

echo "Deploy complete: http://${SITE_NAME}"
