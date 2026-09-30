{
  config,
  lib,
  pkgs,
  ...
}:

let
  serverModule = ../../modules/cluster/server.nix;
  clientModule = ../../modules/cluster/client.nix;

  nodes = {
    srv1 = {
      ip = "10.50.0.11";
      role = "server";
    };
    srv2 = {
      ip = "10.50.0.12";
      role = "server";
    };
    srv3 = {
      ip = "10.50.0.13";
      role = "server";
    };
    cli1 = {
      ip = "10.50.0.21";
      role = "client";
    };
    cli2 = {
      ip = "10.50.0.22";
      role = "client";
    };
  };

  postgresIP = "10.50.0.31";

  serverNames = lib.attrNames (lib.filterAttrs (_: node: node.role == "server") nodes);

  serverAddresses = map (name: "${name}.cluster.internal") serverNames;

  hosts =
    lib.mapAttrs' (
      name: node:
      lib.nameValuePair node.ip (
        [
          name
          "${name}.cluster.internal"
        ]
        ++ lib.optional (node.role == "server") "vault.cluster.internal"
      )
    ) nodes
    // {
      "${postgresIP}" = [
        "pg1"
        "pg1.cluster.internal"
      ];
    };

  baseNetwork = { lib, ... }: {
    networking.hosts = hosts;

    networking.defaultGateway = {
      address = "10.50.0.1";
      interface = "eth0";
    };

    networking.nameservers = [
      "1.1.1.1"
      "9.9.9.9"
    ];

    networking.useHostResolvConf = lib.mkForce false;

    system.stateVersion = "26.05";
  };

  mkContainer = name: node: {
    autoStart = true;

    privateNetwork = true;

    hostBridge = "br-cluster";

    localAddress = "${node.ip}/24";

    privateUsers = "no";

    bindMounts = {
      "/var/lib/cluster-secrets" = {
        hostPath = "/var/lib/cluster-secrets/${name}";

        isReadOnly = true;
      };
    };

    additionalCapabilities = [
      "CAP_SYS_ADMIN"
      "CAP_NET_ADMIN"
    ];

    config =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      {
        imports = [
          baseNetwork

          (if node.role == "server" then serverModule else clientModule)
        ];

        networking.hostName = name;

        cluster.serverAddresses = serverAddresses;

        cluster.clientMemoryMB = node.memoryMB or null;
      };
  };

in
{
  networking.bridges.br-cluster.interfaces = [ ];

  networking.interfaces.br-cluster.ipv4.addresses = [
    {
      address = "10.50.0.1";
      prefixLength = 24;
    }
  ];

  networking.nat = {
    enable = true;

    internalInterfaces = [
      "br-cluster"
    ];

    externalInterface = "eno1";
  };

  boot.kernelModules = [
    "bridge"
    "br_netfilter"
  ];

  boot.kernel.sysctl = {
    "net.bridge.bridge-nf-call-iptables" = 1;
    "net.bridge.bridge-nf-call-ip6tables" = 1;
  };

  containers = lib.mapAttrs mkContainer nodes // {
    pg1 = {
      autoStart = true;

      privateNetwork = true;

      hostBridge = "br-cluster";

      localAddress = "${postgresIP}/24";

      privateUsers = "no";

      config =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        {
          imports = [
            baseNetwork
          ];

          networking.hostName = "pg1";

          services.postgresql = {
            enable = true;

            enableTCPIP = true;

            authentication = ''
              host all all 10.50.0.0/24 scram-sha-256
            '';

            ensureDatabases = [ "app" ];

            ensureUsers = [
              {
                name = "app";
                ensureDBOwnership = true;
              }
            ];
          };

          networking.firewall.allowedTCPPorts = [ 5432 ];
        };
    };
  };

  systemd.services = lib.mapAttrs' (
    name: _:
    lib.nameValuePair "container@${name}" {
      serviceConfig.Delegate = true;
    }
  ) nodes;
}
