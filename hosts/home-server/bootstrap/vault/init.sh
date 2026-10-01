#!/usr/bin/env bash
set -euo pipefail

SECRETS_DIR=/var/lib/cluster-secrets
TOKENS_DIR="$SECRETS_DIR/bootstrap"
INIT_FILE="$TOKENS_DIR/vault-init.json"
SERVERS=(srv1 srv2 srv3)

umask 077
mkdir -p "$TOKENS_DIR"

vault_in() {
  local node=$1
  shift
  nixos-container run "$node" -- env \
    BAO_ADDR=https://127.0.0.1:8200 \
    BAO_CACERT=/var/lib/cluster-secrets/vault/ca.pem \
    bao "$@"
}

vault_status() {
  vault_in "$1" status -format=json 2>/dev/null || true
}

wait_for() {
  local node=$1 jq_expr=$2 want=$3 what=$4
  for _ in $(seq 1 90); do
    local status
    status=$(vault_status "$node")
    if [[ -n $status && $(jq -r "$jq_expr" <<<"$status") == "$want" ]]; then
      return 0
    fi
    sleep 2
  done
  echo "timed out waiting for $node to be $what" >&2
  return 1
}

unseal() {
  local node=$1
  for i in 0 1 2; do
    key=$(jq -r ".unseal_keys_b64[$i]" "$INIT_FILE")
    vault_in "$node" operator unseal "$key" >/dev/null
  done
  echo "$node unsealed"
}

wait_for srv1 '.initialized != null' true "reachable"

if [[ $(vault_status srv1 | jq -r .initialized) == false ]]; then
  vault_in srv1 operator init -format=json > "$INIT_FILE"
  echo "initialized: unseal keys and root token saved to $INIT_FILE"
fi

if [[ ! -f $INIT_FILE ]]; then
  echo "vault is initialized but $INIT_FILE is missing" >&2
  exit 1
fi

for node in "${SERVERS[@]}"; do
  wait_for "$node" .initialized true "initialized/joined"
  if [[ $(vault_status "$node" | jq -r .sealed) == true ]]; then
    unseal "$node"
  fi
done

BAO_TOKEN=$(jq -r .root_token "$INIT_FILE")

nixos-container run srv1 -- env \
  BAO_ADDR=https://127.0.0.1:8200 \
  BAO_CACERT=/var/lib/cluster-secrets/vault/ca.pem \
  BAO_TOKEN="$BAO_TOKEN" \
  bao operator raft list-peers || true

echo "done: vault cluster is up; guard $INIT_FILE carefully"
