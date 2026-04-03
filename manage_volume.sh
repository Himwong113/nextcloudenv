#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

VOLUME_DIR=""
PORT=""
ACTION=""

usage() {
  echo "Usage: $0 [-v <volume_directory>] [-p <port>] [--up] [--down]"
  echo "  -v <volume_directory>  Set the Nextcloud data directory (updates .env)"
  echo "  -p <port>              Set the host port (updates .env)"
  echo "  --up                   Start the Nextcloud stack and sync Nextcloud config"
  echo "  --down                 Stop and remove the Nextcloud stack"
  exit 1
}

compose_cmd() {
  if docker compose version >/dev/null 2>&1; then
    echo "docker compose"
  elif command -v docker-compose >/dev/null 2>&1; then
    echo "docker-compose"
  else
    echo "Error: neither 'docker compose' nor 'docker-compose' is available." >&2
    exit 1
  fi
}

set_env_value() {
  local key="$1"
  local value="$2"

  if grep -q "^${key}=" "$ENV_FILE"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
  else
    echo "${key}=${value}" >> "$ENV_FILE"
  fi
}

print_access_url() {
  local current_port
  current_port="$(grep '^PORT=' "$ENV_FILE" | cut -d= -f2)"
  echo "Nextcloud is running at http://localhost:${current_port}"
}

sync_nextcloud_runtime_config() {
  echo "Synchronizing Nextcloud trusted domains and overwrite settings..."
  "$SCRIPT_DIR/configure_nextcloud.sh"
}

run_compose() {
  local compose_bin
  compose_bin="$(compose_cmd)"

  if [ "$compose_bin" = "docker compose" ]; then
    docker compose --env-file "$ENV_FILE" -f "$SCRIPT_DIR/docker-compose.yml" "$@"
  else
    docker-compose --file "$SCRIPT_DIR/docker-compose.yml" "$@"
  fi
}

compose_up() {
  local compose_bin
  compose_bin="$(compose_cmd)"

  if [ "$compose_bin" = "docker compose" ]; then
    run_compose up -d
    return
  fi

  local log_file
  log_file="$(mktemp)"

  if docker-compose --file "$SCRIPT_DIR/docker-compose.yml" up -d >"$log_file" 2>&1; then
    cat "$log_file"
    rm -f "$log_file"
    return
  fi

  cat "$log_file"

  if grep -q "ContainerConfig" "$log_file"; then
    echo "docker-compose hit a legacy recreate bug. Retrying with a compatibility fallback..."
    docker-compose --file "$SCRIPT_DIR/docker-compose.yml" up -d --no-recreate
    rm -f "$log_file"
    return
  fi

  rm -f "$log_file"
  return 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --up)
      ACTION="up"
      shift
      ;;
    --down)
      ACTION="down"
      shift
      ;;
    -v)
      VOLUME_DIR="$2"
      shift 2
      ;;
    -p)
      PORT="$2"
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

if [ -n "$VOLUME_DIR" ]; then
  mkdir -p "$VOLUME_DIR"
  set_env_value "NEXTCLOUD_DATA_DIR" "$VOLUME_DIR"
  echo "Volume directory set to: $VOLUME_DIR"
fi

if [ -n "$PORT" ]; then
  set_env_value "PORT" "$PORT"
  echo "Port set to: $PORT"
fi

if [ "$ACTION" = "down" ]; then
  echo "Stopping and removing the Nextcloud stack..."
  run_compose down
  exit 0
fi

if [ "$ACTION" = "up" ] || [ -n "$VOLUME_DIR" ] || [ -n "$PORT" ]; then
  echo "Starting the Nextcloud stack..."
else
  echo "Starting the Nextcloud stack with current .env settings..."
fi

compose_up
sync_nextcloud_runtime_config
print_access_url
