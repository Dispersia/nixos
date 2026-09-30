# Cluster bootstrap

Nomad + Consul + OpenBao (Vault-compatible) running in NixOS containers on
`home-server`, plus a standalone PostgreSQL container. Nomad and Consul use
HashiCorp's official release binaries (`modules/hashicorp-bin.nix`) so nothing
gets compiled from source; OpenBao comes prebuilt from cache.nixos.org.

| Node | IP         | Role                          |
|------|------------|-------------------------------|
| srv1 | 10.50.0.11 | consul/nomad server, openbao  |
| srv2 | 10.50.0.12 | consul/nomad server, openbao  |
| srv3 | 10.50.0.13 | consul/nomad server, openbao  |
| cli1 | 10.50.0.21 | nomad client (docker)         |
| cli2 | 10.50.0.22 | nomad client (docker)         |
| pg1  | 10.50.0.31 | postgresql                    |

All scripts run **as root on the host** and are idempotent — safe to re-run.

## First boot

```sh
sudo ./gen-secrets.sh
sudo nixos-rebuild switch --flake /etc/nixos#home-server
sudo ./vault/init.sh
sudo ./acl-bootstrap.sh
sudo ./vault/nomad-integration.sh
sudo ./set-postgres-password.sh
```

1. `gen-secrets.sh` — creates the internal CA, per-node TLS certs, and gossip
   keys under `/var/lib/cluster-secrets/<node>/`. Must run **before** the first
   rebuild: the containers bind-mount these paths and the services load them
   via systemd `LoadCredential`.
2. `nixos-rebuild switch` — builds and starts all six containers.
3. `vault/init.sh` — initializes OpenBao on srv1, saves unseal keys + root
   token to `/var/lib/cluster-secrets/bootstrap/vault-init.json`, unseals all
   three nodes (srv2/srv3 auto-join the raft cluster).
4. `acl-bootstrap.sh` — bootstraps Consul ACLs, installs per-node agent
   tokens, issues Nomad's Consul tokens, then bootstraps Nomad ACLs.
5. `vault/nomad-integration.sh` — enables JWT auth at `jwt-nomad` so Nomad
   workload identities can read `secret/data/nomad/*` (role
   `nomad-workloads`, audience `vault.io`).
6. `set-postgres-password.sh` — sets a random password for the `app` role;
   stored in `/var/lib/cluster-secrets/bootstrap/postgres-app.password`.

## After a host reboot

OpenBao does not auto-unseal. Run:

```sh
sudo ./vault/init.sh
```

It skips initialization and just unseals.

## Secrets layout

```
/var/lib/cluster-secrets/
  ca/                 CA key + gossip keys (host only, never mounted)
  bootstrap/          management tokens, vault unseal keys, pg password
  <node>/consul/      ca.pem cert.pem key.pem secrets.json
  <node>/nomad/       ca.pem cert.pem key.pem consul.json [server-secrets.json]
  <node>/vault/       ca.pem cert.pem key.pem  (openbao certs, servers only)
```

`/var/lib/cluster-secrets/bootstrap/` holds the keys to the kingdom
(vault unseal keys, root token, management tokens). Back it up somewhere
safe; consider moving the vault root token offline after setup.

## Using the cluster

Inside any node (`sudo nixos-container root-login srv1`) the CLIs are
pre-configured via `CONSUL_HTTP_ADDR`, `NOMAD_ADDR`, `BAO_ADDR`, and the CA
env vars. The OpenBao CLI is `bao` (drop-in replacement for `vault`).
Authenticate with the tokens from `/var/lib/cluster-secrets/bootstrap/`.

Nomad jobs reach OpenBao secrets through Nomad's `vault` integration
(OpenBao is API-compatible):

```hcl
vault {}

template {
  data = "{{ with secret \"secret/data/nomad/myapp\" }}{{ .Data.data.key }}{{ end }}"
}
```

Postgres from a Nomad job: `pg1.cluster.internal:5432`, database `app`,
user `app`.

## Adding a node

1. Add it to `nodes` in `hosts/home-server/cluster-containers.nix`.
2. Add the same entry to `NODES` in `gen-secrets.sh` and re-run it.
3. Rebuild. Server counts (`bootstrap_expect`, vault `retry_join`) and
   `/etc/hosts` entries are derived from the node list automatically.
4. For a new node run the agent-token part of `acl-bootstrap.sh` again
   (it is idempotent — just re-run the whole script).
