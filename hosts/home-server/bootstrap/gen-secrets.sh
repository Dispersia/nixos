#!/usr/bin/env bash
set -euo pipefail

SECRETS_DIR=/var/lib/cluster-secrets
CA_DIR="$SECRETS_DIR/ca"
DOMAIN=cluster.internal
DATACENTER=dc1
REGION=global

declare -A NODES=(
  [srv1]="10.50.0.11 server"
  [srv2]="10.50.0.12 server"
  [srv3]="10.50.0.13 server"
  [cli1]="10.50.0.21 client"
  [cli2]="10.50.0.22 client"
)

umask 077
mkdir -p "$CA_DIR"

if [[ ! -f "$CA_DIR/ca.pem" ]]; then
  openssl ecparam -name prime256v1 -genkey -noout -out "$CA_DIR/ca.key"
  openssl req -x509 -new -key "$CA_DIR/ca.key" -sha256 -days 3650 \
    -subj "/CN=cluster-internal-ca" -out "$CA_DIR/ca.pem"
  echo "generated CA"
fi

issue_cert() {
  local out_dir=$1 cn=$2 sans=$3

  [[ -f "$out_dir/cert.pem" ]] && return 0

  mkdir -p "$out_dir"
  openssl ecparam -name prime256v1 -genkey -noout -out "$out_dir/key.pem"
  openssl req -new -key "$out_dir/key.pem" -subj "/CN=$cn" -out "$out_dir/csr.pem"
  openssl x509 -req -in "$out_dir/csr.pem" \
    -CA "$CA_DIR/ca.pem" -CAkey "$CA_DIR/ca.key" -CAcreateserial \
    -days 1825 -sha256 \
    -extfile <(printf 'subjectAltName=%s\nextendedKeyUsage=serverAuth,clientAuth\nkeyUsage=digitalSignature,keyEncipherment\n' "$sans") \
    -out "$out_dir/cert.pem"
  rm "$out_dir/csr.pem"
  cp "$CA_DIR/ca.pem" "$out_dir/ca.pem"
  echo "issued $out_dir/cert.pem"
}

gen_gossip_key() {
  head -c 32 /dev/urandom | base64 -w0
}

[[ -f "$CA_DIR/consul-gossip.key" ]] || gen_gossip_key > "$CA_DIR/consul-gossip.key"
[[ -f "$CA_DIR/nomad-gossip.key" ]] || gen_gossip_key > "$CA_DIR/nomad-gossip.key"

for name in "${!NODES[@]}"; do
  read -r ip role <<<"${NODES[$name]}"
  node_dir="$SECRETS_DIR/$name"

  if [[ $role == server ]]; then
    consul_role_san="DNS:server.$DATACENTER.consul"
    nomad_role_san="DNS:server.$REGION.nomad"
  else
    consul_role_san="DNS:client.$DATACENTER.consul"
    nomad_role_san="DNS:client.$REGION.nomad"
  fi

  common_sans="DNS:$name,DNS:$name.$DOMAIN,DNS:localhost,IP:127.0.0.1,IP:$ip"

  issue_cert "$node_dir/consul" "$name.$DOMAIN" "$common_sans,$consul_role_san"
  issue_cert "$node_dir/nomad" "$name.$DOMAIN" "$common_sans,$nomad_role_san"

  if [[ $role == server ]]; then
    issue_cert "$node_dir/vault" "$name.$DOMAIN" "$common_sans,DNS:vault.$DOMAIN"
  fi

  if [[ ! -f "$node_dir/consul/secrets.json" ]]; then
    jq -n --arg key "$(cat "$CA_DIR/consul-gossip.key")" '{encrypt: $key}' \
      > "$node_dir/consul/secrets.json"
  fi

  if [[ ! -f "$node_dir/nomad/consul.json" ]]; then
    echo '{"consul": {"token": ""}}' > "$node_dir/nomad/consul.json"
  fi

  if [[ $role == server && ! -f "$node_dir/nomad/server-secrets.json" ]]; then
    jq -n --arg key "$(cat "$CA_DIR/nomad-gossip.key")" '{server: {encrypt: $key}}' \
      > "$node_dir/nomad/server-secrets.json"
  fi
done

chmod -R go-rwx "$SECRETS_DIR"

echo "done: secrets under $SECRETS_DIR"
