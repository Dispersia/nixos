#!/usr/bin/env bash
set -euo pipefail

SECRETS_DIR=/var/lib/cluster-secrets
TOKENS_DIR="$SECRETS_DIR/bootstrap"
PASSWORD_FILE="$TOKENS_DIR/postgres-app.password"

umask 077
mkdir -p "$TOKENS_DIR"

if [[ ! -f $PASSWORD_FILE ]]; then
  head -c 24 /dev/urandom | base64 -w0 | tr '+/' '-_' > "$PASSWORD_FILE"
fi

PASSWORD=$(cat "$PASSWORD_FILE")

nixos-container run pg1 -- runuser -u postgres -- psql -v ON_ERROR_STOP=1 \
  -c "ALTER ROLE app WITH PASSWORD '$PASSWORD';"

echo "done: password for role 'app' stored in $PASSWORD_FILE"
