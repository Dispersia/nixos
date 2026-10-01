{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.cluster;

  serverCount = builtins.length cfg.serverAddresses;
in
{
  imports = [
    ./common.nix
  ];

  services.consul.extraConfig = {
    server = true;

    bootstrap_expect = serverCount;

    ui_config = {
      enabled = true;
    };
  };

  services.nomad = {
    dropPrivileges = true;

    settings = {
      server = {
        enabled = true;

        bootstrap_expect = serverCount;

        server_join = {
          retry_join = cfg.serverAddresses;

          retry_interval = "15s";

          retry_max = 0;
        };
      };

      client = {
        enabled = false;
      };

      vault = {
        default_identity = {
          aud = [ "vault.io" ];
          ttl = "1h";
        };
      };
    };

    extraSettingsPaths = [
      "/run/credentials/nomad.service/server-secrets.json"
    ];
  };

  systemd.services.nomad.serviceConfig.LoadCredential = [
    "server-secrets.json:/var/lib/cluster-secrets/nomad/server-secrets.json"
  ];

  services.openbao = {
    enable = true;

    settings = {
      ui = true;

      disable_mlock = true;

      api_addr = "https://${config.networking.hostName}.cluster.internal:8200";
      cluster_addr = "https://${config.networking.hostName}.cluster.internal:8201";

      listener.default = {
        type = "tcp";

        address = "0.0.0.0:8200";
        cluster_address = "0.0.0.0:8201";

        tls_cert_file = "/run/credentials/openbao.service/cert.pem";
        tls_key_file = "/run/credentials/openbao.service/key.pem";
        tls_min_version = "tls12";
      };

      storage.raft = {
        path = "/var/lib/openbao";

        node_id = config.networking.hostName;

        retry_join = map (addr: {
          leader_api_addr = "https://${addr}:8200";
          leader_ca_cert_file = "/run/credentials/openbao.service/ca.pem";
        }) cfg.serverAddresses;
      };
    };
  };

  systemd.services.openbao.serviceConfig.LoadCredential = [
    "ca.pem:/var/lib/cluster-secrets/vault/ca.pem"
    "cert.pem:/var/lib/cluster-secrets/vault/cert.pem"
    "key.pem:/var/lib/cluster-secrets/vault/key.pem"
  ];

  environment.variables = {
    BAO_ADDR = "https://127.0.0.1:8200";
    BAO_CACERT = "/var/lib/cluster-secrets/vault/ca.pem";
  };

  networking.firewall = {
    allowedTCPPorts = [
      8300

      8301
      8302

      8501
      8503

      4646

      4647

      4648

      8200
      8201
    ];

    allowedUDPPorts = [
      8301
      8302

      4648
    ];
  };
}
