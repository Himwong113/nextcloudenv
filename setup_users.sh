#!/bin/bash

# setup_users.sh — Create Nextcloud family user accounts via OCC CLI
# Reads from users.conf (one entry per line: username password displayname)
# Usage: ./setup_users.sh [--conf <users.conf>]

set -e

USERS_CONF="$(dirname "$0")/users.conf"
CONTAINER="nextcloud_container"

usage() {
  echo "Usage: $0 [--conf <path_to_users.conf>]"
  echo "  --conf <file>   Path to the users config file (default: ./users.conf)"
  echo ""
  echo "users.conf format (one user per line):"
  echo "  username password Display Name"
  exit 1
}

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --conf)
      USERS_CONF="$2"
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

if [ ! -f "$USERS_CONF" ]; then
  echo "Error: users.conf not found at $USERS_CONF"
  echo "Copy users.conf.example to users.conf and fill in your family members."
  exit 1
fi

echo "Creating Nextcloud users from $USERS_CONF..."

while IFS= read -r line || [ -n "$line" ]; do
  # Skip blank lines and comments
  [[ -z "$line" || "$line" == \#* ]] && continue

  read -r USERNAME PASSWORD DISPLAYNAME <<< "$(echo "$line" | xargs)"

  # Ignore the example/header row if it was copied into users.conf.
  if [[ "$USERNAME" == "username" && "$PASSWORD" == "password" ]]; then
    continue
  fi

  if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
    echo "Skipping invalid line: $line"
    continue
  fi

  if docker exec "$CONTAINER" php occ user:info "$USERNAME" >/dev/null 2>&1; then
    echo "Skipping existing user: $USERNAME"
    continue
  fi

  echo "Creating user: $USERNAME ($DISPLAYNAME)..."
  docker exec -e OC_PASS="$PASSWORD" "$CONTAINER" \
    php occ user:add \
    --password-from-env \
    --display-name="$DISPLAYNAME" \
    "$USERNAME"

  echo "  Done: $USERNAME"
done < "$USERS_CONF"

echo ""
echo "All users created. They can log in at http://localhost:$(grep '^PORT=' "$(dirname "$0")/.env" | cut -d= -f2)"
