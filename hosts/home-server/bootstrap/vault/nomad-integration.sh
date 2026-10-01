#!/usr/bin/env bash
set -euo pipefail

SECRETS_DIR=/var/lib/cluster-secrets
TOKENS_DIR="$SECRETS_DIR/bootstrap"
INIT_FILE="$TOKENS_DIR/vault-init.json"

BAO_TOKEN=$(jq -r .root_token "$INIT_FILE")

vault_in() {
  nixos-container run srv1 -- env \
    BAO_ADDR=https://127.0.0.1:8200 \
    BAO_CACERT=/var/lib/cluster-secrets/vault/ca.pem \
    BAO_TOKEN="$BAO_TOKEN" \
    bao "$@"
}

if ! vault_in auth list -format=json | jq -e '."jwt-nomad/"' >/dev/null; then
  vault_in auth enable -path=jwt-nomad jwt
fi

vault_in write auth/jwt-nomad/config \
  jwks_url="https://srv1.cluster.internal:4646/.well-known/jwks.json" \
  jwks_ca_pem=@/var/lib/cluster-secrets/nomad/ca.pem \
  jwt_supported_algs=RS256,EdDSA \
  default_role=nomad-workloads

POLICY_DIR="$SECRETS_DIR/srv1/policies"
mkdir -p "$POLICY_DIR"

cat > "$POLICY_DIR/nomad-workloads.hcl" <<'EOF'
path "secret/data/nomad/*" {
  capabilities = ["read"]
}
path "secret/metadata/nomad/*" {
  capabilities = ["read", "list"]
}
EOF

vault_in policy write nomad-workloads /var/lib/cluster-secrets/policies/nomad-workloads.hcl

if ! vault_in secrets list -format=json | jq -e '."secret/"' >/dev/null; then
  vault_in secrets enable -path=secret -version=2 kv
fi

vault_in write auth/jwt-nomad/role/nomad-workloads \
  role_type=jwt \
  bound_audiences=vault.io \
  user_claim=/nomad_job_id \
  user_claim_json_pointer=true \
  claim_mappings=nomad_namespace=nomad_namespace \
  claim_mappings=nomad_job_id=nomad_job_id \
  claim_mappings=nomad_task=nomad_task \
  token_type=service \
  token_policies=nomad-workloads \
  token_period=30m \
  token_explicit_max_ttl=0

echo "done: nomad workload identity wired to vault (auth path jwt-nomad, role nomad-workloads)"
