#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
CONTAINER="nextcloud_container"
PORT="8080"

get_env_value() {
  local key="$1"

  if [ ! -f "$ENV_FILE" ]; then
    return 1
  fi

  grep -E "^${key}=" "$ENV_FILE" | tail -n 1 | cut -d= -f2-
}

PORT="${PORT:-$(get_env_value PORT || echo 8080)}"
NEXTCLOUD_ADMIN_USER="${NEXTCLOUD_ADMIN_USER:-$(get_env_value NEXTCLOUD_ADMIN_USER || true)}"
NEXTCLOUD_ADMIN_PASSWORD="${NEXTCLOUD_ADMIN_PASSWORD:-$(get_env_value NEXTCLOUD_ADMIN_PASSWORD || true)}"
MYSQL_DATABASE="${MYSQL_DATABASE:-$(get_env_value MYSQL_DATABASE || true)}"
MYSQL_USER="${MYSQL_USER:-$(get_env_value MYSQL_USER || true)}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-$(get_env_value MYSQL_PASSWORD || true)}"
OWN_DOMAIN="${OWN_DOMAIN:-$(get_env_value OWN_DOMAIN || true)}"
NEXTCLOUD_TRUSTED_DOMAINS="${NEXTCLOUD_TRUSTED_DOMAINS:-$(get_env_value NEXTCLOUD_TRUSTED_DOMAINS || echo localhost)}"
NEXTCLOUD_OVERWRITE_CLI_URL="${NEXTCLOUD_OVERWRITE_CLI_URL:-$(get_env_value NEXTCLOUD_OVERWRITE_CLI_URL || true)}"
NEXTCLOUD_TRUSTED_PROXIES="${NEXTCLOUD_TRUSTED_PROXIES:-$(get_env_value NEXTCLOUD_TRUSTED_PROXIES || true)}"

log() {
  echo "[nextcloud-config] $*"
}

container_running() {
  docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null | grep -q '^true$'
}

wait_for_occ() {
  local max_attempts=60
  local attempt=1

  while [ "$attempt" -le "$max_attempts" ]; do
    if docker exec "$CONTAINER" php occ status >/tmp/nextcloud_occ_status.$$ 2>/dev/null; then
      rm -f /tmp/nextcloud_occ_status.$$
      return 0
    fi

    sleep 2
    attempt=$((attempt + 1))
  done

  rm -f /tmp/nextcloud_occ_status.$$ 2>/dev/null || true
  return 1
}

is_installed() {
  docker exec "$CONTAINER" php occ status 2>/dev/null | grep -q 'installed: true'
}

run_occ() {
  docker exec "$CONTAINER" php occ "$@"
}

ensure_installed() {
  if is_installed; then
    return 0
  fi

  if [ -z "${NEXTCLOUD_ADMIN_USER:-}" ] || [ -z "${NEXTCLOUD_ADMIN_PASSWORD:-}" ] || \
     [ -z "${MYSQL_DATABASE:-}" ] || [ -z "${MYSQL_USER:-}" ] || \
     [ -z "${MYSQL_PASSWORD:-}" ]; then
    log "Skipping automatic install because required environment variables are missing."
    return 1
  fi

  log "Nextcloud is not installed yet. Running initial installation..."
  run_occ maintenance:install \
    --database mysql \
    --database-host db \
    --database-name "$MYSQL_DATABASE" \
    --database-user "$MYSQL_USER" \
    --database-pass "$MYSQL_PASSWORD" \
    --admin-user "$NEXTCLOUD_ADMIN_USER" \
    --admin-pass "$NEXTCLOUD_ADMIN_PASSWORD"
}

sync_trusted_domains() {
  local domains="${NEXTCLOUD_TRUSTED_DOMAINS:-localhost}"
  local domain index=0

  if [ -n "${OWN_DOMAIN:-}" ]; then
    case " $domains " in
      *" ${OWN_DOMAIN} "*) ;;
      *) domains="${domains} ${OWN_DOMAIN}" ;;
    esac
  fi

  for domain in $domains; do
    run_occ config:system:set trusted_domains "$index" --value="$domain" >/dev/null
    index=$((index + 1))
  done

  while run_occ config:system:get trusted_domains "$index" >/dev/null 2>&1; do
    run_occ config:system:delete trusted_domains "$index" >/dev/null
    index=$((index + 1))
  done

  log "Trusted domains synchronized: $domains"
}

sync_overwrite_url() {
  local overwrite_url="${NEXTCLOUD_OVERWRITE_CLI_URL:-}"

  if [ -z "$overwrite_url" ]; then
    if [ -n "${OWN_DOMAIN:-}" ]; then
      overwrite_url="https://${OWN_DOMAIN}"
    else
      local first_public_domain=""
      local domain

      for domain in ${NEXTCLOUD_TRUSTED_DOMAINS:-localhost}; do
        if [ "$domain" != "localhost" ]; then
          first_public_domain="$domain"
          break
        fi
      done

      if [ -n "$first_public_domain" ]; then
        overwrite_url="https://$first_public_domain"
      else
        overwrite_url="http://localhost:${PORT}"
      fi
    fi
  fi

  run_occ config:system:set overwrite.cli.url --value="$overwrite_url" >/dev/null

  case "$overwrite_url" in
    https://*)
      run_occ config:system:set overwriteprotocol --value=https >/dev/null
      ;;
    http://*)
      run_occ config:system:set overwriteprotocol --value=http >/dev/null
      ;;
  esac

  log "overwrite.cli.url set to: $overwrite_url"
}

sync_trusted_proxies() {
  local proxies="${NEXTCLOUD_TRUSTED_PROXIES:-}"
  local proxy index=0

  if [ -z "$proxies" ]; then
    return 0
  fi

  for proxy in $proxies; do
    run_occ config:system:set trusted_proxies "$index" --value="$proxy" >/dev/null
    index=$((index + 1))
  done

  while run_occ config:system:get trusted_proxies "$index" >/dev/null 2>&1; do
    run_occ config:system:delete trusted_proxies "$index" >/dev/null
    index=$((index + 1))
  done

  log "Trusted proxies synchronized: $proxies"
}

main() {
  if ! container_running; then
    log "Container $CONTAINER is not running."
    exit 1
  fi

  log "Waiting for Nextcloud OCC to become available..."
  if ! wait_for_occ; then
    log "Timed out waiting for Nextcloud to become ready."
    exit 1
  fi

  ensure_installed || true

  if ! is_installed; then
    log "Nextcloud is still not installed, so configuration sync was skipped."
    exit 1
  fi

  sync_trusted_domains
  sync_overwrite_url
  sync_trusted_proxies
  log "Nextcloud configuration sync completed."
}

main "$@"
