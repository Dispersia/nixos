#!/usr/bin/env bash
set -euo pipefail

SECRETS_DIR=/var/lib/cluster-secrets
TOKENS_DIR="$SECRETS_DIR/bootstrap"
NODES=(srv1 srv2 srv3 cli1 cli2)

umask 077
mkdir -p "$TOKENS_DIR"

CONSUL_HTTP_TOKEN=""

consul_in() {
  local node=$1
  shift
  nixos-container run "$node" -- env \
    CONSUL_HTTP_ADDR=https://127.0.0.1:8501 \
    CONSUL_CACERT=/var/lib/cluster-secrets/consul/ca.pem \
    CONSUL_HTTP_TOKEN="$CONSUL_HTTP_TOKEN" \
    consul "$@"
}

nomad_in() {
  local node=$1
  shift
  nixos-container run "$node" -- env \
    NOMAD_ADDR=https://127.0.0.1:4646 \
    NOMAD_CACERT=/var/lib/cluster-secrets/nomad/ca.pem \
    nomad "$@"
}

CONSUL_MGMT_FILE="$TOKENS_DIR/consul-management.token"

if [[ ! -f $CONSUL_MGMT_FILE ]]; then
  for _ in $(seq 1 60); do
    if out=$(consul_in srv1 acl bootstrap -format=json 2>/dev/null); then
      jq -r .SecretID <<<"$out" > "$CONSUL_MGMT_FILE"
      echo "consul ACL system bootstrapped"
      break
    fi
    sleep 3
  done
fi

if [[ ! -f $CONSUL_MGMT_FILE ]]; then
  echo "failed to bootstrap consul ACLs" >&2
  exit 1
fi

CONSUL_HTTP_TOKEN=$(cat "$CONSUL_MGMT_FILE")

POLICY_DIR="$SECRETS_DIR/srv1/policies"
mkdir -p "$POLICY_DIR"

cat > "$POLICY_DIR/agent.hcl" <<'EOF'
node_prefix "" {
  policy = "write"
}
service_prefix "" {
  policy = "read"
}
EOF

cat > "$POLICY_DIR/nomad-agent.hcl" <<'EOF'
agent_prefix "" {
  policy = "read"
}
node_prefix "" {
  policy = "read"
}
service_prefix "" {
  policy = "write"
}
key_prefix "" {
  policy = "read"
}
acl = "write"
EOF

ensure_policy() {
  local name=$1
  if ! consul_in srv1 acl policy read -name "$name" >/dev/null 2>&1; then
    consul_in srv1 acl policy create -name "$name" \
      -rules "@/var/lib/cluster-secrets/policies/$name.hcl" >/dev/null
    echo "created consul policy $name"
  fi
}

ensure_policy agent
ensure_policy nomad-agent

for node in "${NODES[@]}"; do
  token_file="$TOKENS_DIR/consul-agent-$node.token"

  if [[ ! -f $token_file ]]; then
    consul_in srv1 acl token create \
      -description "agent token for $node" \
      -policy-name agent -format=json | jq -r .SecretID > "$token_file"
  fi

  consul_in "$node" acl set-agent-token agent "$(cat "$token_file")"
  echo "$node consul agent token set"
done

for node in "${NODES[@]}"; do
  consul_json="$SECRETS_DIR/$node/nomad/consul.json"

  if [[ $(jq -r .consul.token "$consul_json") == "" ]]; then
    token_file="$TOKENS_DIR/consul-nomad-$node.token"

    if [[ ! -f $token_file ]]; then
      consul_in srv1 acl token create \
        -description "nomad agent token for $node" \
        -policy-name nomad-agent -format=json | jq -r .SecretID > "$token_file"
    fi

    jq -n --arg token "$(cat "$token_file")" '{consul: {token: $token}}' > "$consul_json"
    chmod 600 "$consul_json"

    nixos-container run "$node" -- systemctl restart nomad
    echo "$node nomad consul token installed"
  fi
done

NOMAD_MGMT_FILE="$TOKENS_DIR/nomad-management.token"

if [[ ! -f $NOMAD_MGMT_FILE ]]; then
  for _ in $(seq 1 60); do
    out=$(nixos-container run srv1 -- curl -s \
      --cacert /var/lib/cluster-secrets/nomad/ca.pem \
      -X POST https://127.0.0.1:4646/v1/acl/bootstrap || true)

    if jq -e .SecretID <<<"$out" >/dev/null 2>&1; then
      jq -r .SecretID <<<"$out" > "$NOMAD_MGMT_FILE"
      echo "nomad ACL system bootstrapped"
      break
    fi

    if grep -qi "already bootstrapped" <<<"$out"; then
      echo "nomad ACLs already bootstrapped but $NOMAD_MGMT_FILE is missing; restore the token manually" >&2
      exit 1
    fi

    sleep 3
  done
fi

if [[ ! -f $NOMAD_MGMT_FILE ]]; then
  echo "failed to bootstrap nomad ACLs" >&2
  exit 1
fi

echo "done: management tokens in $TOKENS_DIR"
