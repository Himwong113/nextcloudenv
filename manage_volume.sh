#!/bin/bash

set -e

ENV_FILE="$(dirname "$0")/.env"

VOLUME_DIR=""
PORT=""
ACTION=""

usage() {
  echo "Usage: $0 [-v <volume_directory>] [-p <port>] [--up] [--down]"
  echo "  -v <volume_directory>  Set the Nextcloud data directory (updates .env)"
  echo "  -p <port>              Set the host port (updates .env)"
  echo "  --up                   Start the Nextcloud stack via docker-compose"
  echo "  --down                 Stop and remove the Nextcloud stack"
  exit 1
}

# Parse all arguments manually (handles both --long and -short flags)
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

# Update NEXTCLOUD_DATA_DIR in .env if -v was provided
if [ -n "$VOLUME_DIR" ]; then
  mkdir -p "$VOLUME_DIR"
  if grep -q "^NEXTCLOUD_DATA_DIR=" "$ENV_FILE"; then
    sed -i "s|^NEXTCLOUD_DATA_DIR=.*|NEXTCLOUD_DATA_DIR=$VOLUME_DIR|" "$ENV_FILE"
  else
    echo "NEXTCLOUD_DATA_DIR=$VOLUME_DIR" >> "$ENV_FILE"
  fi
  echo "Volume directory set to: $VOLUME_DIR"
fi

# Update PORT in .env if -p was provided
if [ -n "$PORT" ]; then
  if grep -q "^PORT=" "$ENV_FILE"; then
    sed -i "s|^PORT=.*|PORT=$PORT|" "$ENV_FILE"
  else
    echo "PORT=$PORT" >> "$ENV_FILE"
  fi
  echo "Port set to: $PORT"
fi

# Execute action
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ "$ACTION" == "down" ]; then
  echo "Stopping and removing the Nextcloud stack..."
  (cd "$SCRIPT_DIR" && docker-compose down)
  exit 0
elif [ "$ACTION" == "up" ] || [ -n "$VOLUME_DIR" ] || [ -n "$PORT" ]; then
  echo "Starting the Nextcloud stack..."
  (cd "$SCRIPT_DIR" && docker-compose up -d)
  echo "Nextcloud is running at http://localhost:$(grep '^PORT=' "$ENV_FILE" | cut -d= -f2)"
  exit 0
else
  echo "Starting the Nextcloud stack with current .env settings..."
  (cd "$SCRIPT_DIR" && docker-compose up -d)
  echo "Nextcloud is running at http://localhost:$(grep '^PORT=' "$ENV_FILE" | cut -d= -f2)"
fi

# Update NEXTCLOUD_DATA_DIR in .env if -v was provided
if [ -n "$VOLUME_DIR" ]; then
  mkdir -p "$VOLUME_DIR"
  if grep -q "^NEXTCLOUD_DATA_DIR=" "$ENV_FILE"; then
    sed -i "s|^NEXTCLOUD_DATA_DIR=.*|NEXTCLOUD_DATA_DIR=$VOLUME_DIR|" "$ENV_FILE"
  else
    echo "NEXTCLOUD_DATA_DIR=$VOLUME_DIR" >> "$ENV_FILE"
  fi
  echo "Volume directory set to: $VOLUME_DIR"
fi

# Update PORT in .env if -p was provided
if [ -n "$PORT" ]; then
  if grep -q "^PORT=" "$ENV_FILE"; then
    sed -i "s|^PORT=.*|PORT=$PORT|" "$ENV_FILE"
  else
    echo "PORT=$PORT" >> "$ENV_FILE"
  fi
  echo "Port set to: $PORT"
fi

# Execute action
if [ "$ACTION" == "down" ]; then
  echo "Stopping and removing the Nextcloud stack..."
  docker compose --env-file "$ENV_FILE" -f "$(dirname "$0")/docker-compose.yml" down
  exit 0
elif [ "$ACTION" == "up" ] || [ -n "$VOLUME_DIR" ] || [ -n "$PORT" ]; then
  echo "Starting the Nextcloud stack..."
  docker compose --env-file "$ENV_FILE" -f "$(dirname "$0")/docker-compose.yml" up -d
  echo "Nextcloud is running at http://localhost:$(grep '^PORT=' "$ENV_FILE" | cut -d= -f2)"
  exit 0
else
  # No flags given — default: start the stack
  echo "Starting the Nextcloud stack with current .env settings..."
  docker compose --env-file "$ENV_FILE" -f "$(dirname "$0")/docker-compose.yml" up -d
  echo "Nextcloud is running at http://localhost:$(grep '^PORT=' "$ENV_FILE" | cut -d= -f2)"
fi