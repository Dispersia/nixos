{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.nordvpnNetns;
  ns = cfg.namespace;
  runDir = "/run/nordlynx";
  hostVeth = "veth-ns";
  nsVeth = "veth0";
  hostAddr = "10.200.0.1";
  nsAddr = "10.200.0.2";
  resolv = pkgs.writeText "nordlynx-resolv.conf" (
    lib.concatMapStringsSep "\n" (d: "nameserver ${d}") cfg.dns + "\n"
  );
in
{
  options.services.nordvpnNetns = {
    enable = lib.mkEnableOption "NordVPN WireGuard network namespace for selected services";

    tokenFile = lib.mkOption {
      type = lib.types.path;
      description = "File containing the NordVPN access token.";
    };

    country = lib.mkOption {
      type = lib.types.str;
      default = "United States";
      description = "NordVPN server country.";
    };

    namespace = lib.mkOption {
      type = lib.types.str;
      default = "vpn";
      description = "Network namespace name.";
    };

    services = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "systemd services to run inside the VPN namespace.";
    };

    ports = lib.mkOption {
      type = lib.types.listOf lib.types.port;
      default = [ ];
      description = "TCP ports forwarded from the host into the namespace.";
    };

    hostProxyPorts = lib.mkOption {
      type = lib.types.listOf lib.types.port;
      default = [ ];
      description = "Host TCP ports exposed on the namespace's loopback.";
    };

    dns = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "1.1.1.1"
        "1.0.0.1"
      ];
      description = "DNS servers used inside the namespace.";
    };
  };

  config = lib.mkIf cfg.enable {
    networking.firewall.checkReversePath = false;
    networking.firewall.trustedInterfaces = [ hostVeth ];
    boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

    systemd.services = {
      nordlynx-config = {
        description = "Fetch NordLynx WireGuard configuration";
        wantedBy = [ "multi-user.target" ];
        before = [ "nordlynx-netns.service" ];
        requiredBy = [ "nordlynx-netns.service" ];
        path = [
          pkgs.curl
          pkgs.jq
          pkgs.coreutils
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          Restart = "on-failure";
          RestartSec = 10;
        };
        script = ''
          set -euo pipefail

          install -d -m 700 ${runDir}

          token=$(cat ${cfg.tokenFile})
          creds=$(curl -fsS -u "token:$token" https://api.nordvpn.com/v1/users/services/credentials)
          priv=$(echo "$creds" | jq -r .nordlynx_private_key)

          enc=$(jq -rn --arg c ${lib.escapeShellArg cfg.country} '$c|@uri')
          serv=$(curl -fsS "https://api.nordvpn.com/v1/servers/recommendations?filters%5Bservers_technologies%5D%5Bidentifier%5D=wireguard_udp&filters%5Bcountry%5D=$enc&limit=1")
          host=$(echo "$serv" | jq -r '.[0].hostname')
          endpoint=$(echo "$serv" | jq -r '.[0].station')
          pub=$(echo "$serv" | jq -r '.[0].technologies[] | select(.identifier=="wireguard_udp") | .metadata[] | select(.name=="public_key") | .value')

          umask 077
          cat > ${runDir}/wg0.conf <<EOF
          [Interface]
          PrivateKey = $priv

          [Peer]
          PublicKey = $pub
          Endpoint = $endpoint:51820
          AllowedIPs = 0.0.0.0/0
          PersistentKeepalive = 25
          EOF

          install -m 644 ${resolv} ${runDir}/resolv.conf
          echo "nordlynx: server $host ($endpoint)"
        '';
      };

      nordlynx-netns = {
        description = "NordVPN WireGuard network namespace";
        wantedBy = [ "multi-user.target" ];
        after = [
          "nordlynx-config.service"
          "network-online.target"
        ];
        requires = [ "nordlynx-config.service" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        path = [
          pkgs.iproute2
          pkgs.wireguard-tools
          pkgs.procps
        ];
        script = ''
          set -euo pipefail

          ip netns del ${ns} 2>/dev/null || true
          ip link del ${hostVeth} 2>/dev/null || true
          ip link del wg0 2>/dev/null || true

          ip netns add ${ns}
          ip link add ${hostVeth} type veth peer name ${nsVeth}
          ip link set ${nsVeth} netns ${ns}
          ip addr add ${hostAddr}/30 dev ${hostVeth}
          ip link set ${hostVeth} up
          ip -n ${ns} link set lo up
          ip -n ${ns} addr add ${nsAddr}/30 dev ${nsVeth}
          ip -n ${ns} link set ${nsVeth} up

          ip link add wg0 type wireguard
          wg setconf wg0 ${runDir}/wg0.conf
          ip link set wg0 netns ${ns}
          ip -n ${ns} addr add 10.5.0.2/32 dev wg0
          ip -n ${ns} link set wg0 mtu 1420
          ip -n ${ns} link set wg0 up
          ip -n ${ns} route add default dev wg0

          ip -n ${ns} route add 192.168.0.0/16 via ${hostAddr} 2>/dev/null || true
          ip -n ${ns} route add 10.0.0.0/8 via ${hostAddr} 2>/dev/null || true
          ip -n ${ns} route add 100.64.0.0/10 via ${hostAddr} 2>/dev/null || true

          ip netns exec ${ns} sysctl -q -w net.ipv4.conf.all.src_valid_mark=1 || true
        '';
        preStop = ''
          ip netns del ${ns} 2>/dev/null || true
          ip link del ${hostVeth} 2>/dev/null || true
        '';
      };

      nordlynx-egress-check = {
        description = "Public IP seen inside the NordVPN namespace";
        wantedBy = [ "multi-user.target" ];
        after = [ "nordlynx-netns.service" ];
        requires = [ "nordlynx-netns.service" ];
        serviceConfig = {
          Type = "oneshot";
          NetworkNamespacePath = "/run/netns/${ns}";
          BindReadOnlyPaths = [ "${runDir}/resolv.conf:/etc/resolv.conf" ];
          ExecStart = "${pkgs.bash}/bin/bash -c '${pkgs.curl}/bin/curl -fsS --max-time 25 https://api.ipify.org; echo'";
        };
      };
    }
    // (lib.listToAttrs (
      map (
        name:
        lib.nameValuePair name {
          requires = [ "nordlynx-netns.service" ];
          after = [ "nordlynx-netns.service" ];
          partOf = [ "nordlynx-netns.service" ];
          serviceConfig = {
            PrivateNetwork = lib.mkForce false;
            NetworkNamespacePath = "/run/netns/${ns}";
            BindReadOnlyPaths = [ "${runDir}/resolv.conf:/etc/resolv.conf" ];
          };
        }
      ) cfg.services
    ))
    // (lib.listToAttrs (
      map (
        port:
        lib.nameValuePair "nordlynx-fwd-${toString port}" {
          description = "Forward host port ${toString port} into the VPN namespace";
          wantedBy = [ "multi-user.target" ];
          requires = [ "nordlynx-netns.service" ];
          after = [ "nordlynx-netns.service" ];
          serviceConfig = {
            ExecStart = "${pkgs.socat}/bin/socat TCP-LISTEN:${toString port},fork,reuseaddr TCP:${nsAddr}:${toString port}";
            Restart = "always";
            RestartSec = 2;
          };
        }
      ) cfg.ports
    ))
    // (lib.listToAttrs (
      map (
        port:
        lib.nameValuePair "nordlynx-hostproxy-${toString port}" {
          description = "Expose host port ${toString port} on the VPN namespace loopback";
          wantedBy = [ "multi-user.target" ];
          requires = [ "nordlynx-netns.service" ];
          after = [ "nordlynx-netns.service" ];
          serviceConfig = {
            NetworkNamespacePath = "/run/netns/${ns}";
            ExecStart = "${pkgs.socat}/bin/socat TCP-LISTEN:${toString port},fork,reuseaddr,bind=127.0.0.1 TCP:${hostAddr}:${toString port}";
            Restart = "always";
            RestartSec = 2;
          };
        }
      ) cfg.hostProxyPorts
    ));
  };
}
