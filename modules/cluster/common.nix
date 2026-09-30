{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.cluster;

  privateIP = "{{ GetPrivateIP }}";
in
{
  imports = [
    ../hashicorp-bin.nix
  ];

  options.cluster = {
    datacenter = lib.mkOption {
      type = lib.types.str;
      default = "dc1";
    };

    region = lib.mkOption {
      type = lib.types.str;
      default = "global";
    };

    serverAddresses = lib.mkOption {
      type = lib.types.listOf lib.types.str;

      default = [
        "srv1.cluster.internal"
        "srv2.cluster.internal"
        "srv3.cluster.internal"
      ];
    };

    clientMemoryMB = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
    };
  };

  config = {
    nixpkgs.config.allowUnfreePredicate =
      pkg:
      builtins.elem (lib.getName pkg) [
        "consul"
        "nomad"
      ];

    environment.systemPackages = with pkgs; [
      consul
      nomad
      openbao
      curl
      jq
    ];

    services.consul = {
      enable = true;
      dropPrivileges = true;

      extraConfig = {
        datacenter = cfg.datacenter;
        node_name = config.networking.hostName;

        data_dir = "/var/lib/consul";
        bind_addr = privateIP;

        client_addr = "127.0.0.1 ${privateIP}";

        retry_join = cfg.serverAddresses;

        acl = {
          enabled = true;
          default_policy = "deny";
          enable_token_persistence = true;
        };

        ports = {
          http = -1;
          https = 8501;

          grpc = -1;
          grpc_tls = 8503;
        };

        tls = {
          defaults = {
            ca_file = "/run/credentials/consul.service/ca.pem";

            cert_file = "/run/credentials/consul.service/cert.pem";

            key_file = "/run/credentials/consul.service/key.pem";

            verify_outgoing = true;
          };

          internal_rpc = {
            verify_incoming = true;
            verify_server_hostname = true;
          };

          https = {
            verify_incoming = false;
          };

          grpc = {
            verify_incoming = false;
          };
        };
      };

      extraConfigFiles = [
        "/run/credentials/consul.service/secrets.json"
      ];
    };

    systemd.services.consul.serviceConfig.LoadCredential = [
      "ca.pem:/var/lib/cluster-secrets/consul/ca.pem"
      "cert.pem:/var/lib/cluster-secrets/consul/cert.pem"
      "key.pem:/var/lib/cluster-secrets/consul/key.pem"
      "secrets.json:/var/lib/cluster-secrets/consul/secrets.json"
    ];

    services.nomad = {
      enable = true;

      enableDocker = true;

      settings = {
        region = cfg.region;
        datacenter = cfg.datacenter;

        data_dir = "/var/lib/nomad";

        bind_addr = privateIP;

        acl = {
          enabled = true;
        };

        tls = {
          http = true;
          rpc = true;

          ca_file = "/run/credentials/nomad.service/ca.pem";

          cert_file = "/run/credentials/nomad.service/cert.pem";

          key_file = "/run/credentials/nomad.service/key.pem";

          verify_server_hostname = true;

          verify_https_client = false;

          tls_min_version = "tls12";
        };

        consul = {
          address = "127.0.0.1:8501";
          ssl = true;
          ca_file = "/run/credentials/nomad.service/ca.pem";

          grpc_address = "127.0.0.1:8503";
          grpc_ca_file = "/run/credentials/nomad.service/ca.pem";
        };

        vault = {
          enabled = true;
          address = "https://vault.cluster.internal:8200";
          ca_file = "/run/credentials/nomad.service/ca.pem";
        };
      };

      extraSettingsPaths = [
        "/run/credentials/nomad.service/consul.json"
      ];
    };

    systemd.services.nomad.serviceConfig = {
      LoadCredential = [
        "ca.pem:/var/lib/cluster-secrets/nomad/ca.pem"
        "cert.pem:/var/lib/cluster-secrets/nomad/cert.pem"
        "key.pem:/var/lib/cluster-secrets/nomad/key.pem"
        "consul.json:/var/lib/cluster-secrets/nomad/consul.json"
      ];
    };

    environment.variables = {
      CONSUL_HTTP_ADDR = "https://127.0.0.1:8501";
      CONSUL_CACERT = "/var/lib/cluster-secrets/consul/ca.pem";

      NOMAD_ADDR = "https://127.0.0.1:4646";
      NOMAD_CACERT = "/var/lib/cluster-secrets/nomad/ca.pem";
    };
  };
}
