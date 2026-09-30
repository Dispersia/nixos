{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.cluster;
in
{
  imports = [
    ./common.nix
  ];

  services.consul.extraConfig = {
    server = false;
  };

  services.nomad = {
    dropPrivileges = false;

    extraPackages = [
      pkgs.cni-plugins
      pkgs.iptables
    ];

    settings = {
      server = {
        enabled = false;
      };

      client = {
        enabled = true;

        server_join = {
          retry_join = cfg.serverAddresses;
          retry_interval = "15s";
          retry_max = 0;
        };

        cni_path = "${pkgs.cni-plugins}/bin";

        reserved = {
          memory = 512;
          cpu = 500;

          reserved_ports = "22,4646,8301,8501,8503,8600";
        };
      }
      // lib.optionalAttrs (cfg.clientMemoryMB != null) {
        memory_total_mb = cfg.clientMemoryMB;
      };

      vault = {
        jwt_auth_backend_path = "jwt-nomad";
      };
    };
  };

  systemd.services.nomad.serviceConfig = {
    Delegate = true;
    TasksMax = "infinity";
  };

  boot.kernel.sysctl = lib.mkIf (!config.boot.isContainer) {
    "net.bridge.bridge-nf-call-iptables" = 1;
    "net.bridge.bridge-nf-call-ip6tables" = 1;
  };

  networking.firewall = {
    allowedTCPPorts = [
      8301

      8501
      8503

      4646
    ];

    allowedUDPPorts = [
      8301
    ];

    allowedTCPPortRanges = [
      {
        from = 20000;
        to = 32000;
      }
    ];

    allowedUDPPortRanges = [
      {
        from = 20000;
        to = 32000;
      }
    ];
  };
}
