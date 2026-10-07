{
  config,
  lib,
  pkgs,
  ...
}:
{
  services.tailscale = {
    enable = true;

    # Linux clients ignore advertised subnet routes unless told to accept them.
    # The home-server advertises 192.168.4.50/32 (where *.home.arpa resolves),
    # so non-subnet-router hosts need this to keep reaching those names when
    # off-LAN.
    extraSetFlags = lib.mkIf (config.services.tailscale.useRoutingFeatures != "server") [
      "--accept-routes"
    ];
  };

  # extraSetFlags are applied by the `tailscaled-set` oneshot, which only runs
  # when tailscaled starts. Restart tailscaled when the flags change so a
  # deploy actually applies them.
  systemd.services.tailscaled.restartTriggers = [ config.services.tailscale.extraSetFlags ];

  networking.nftables.enable = true;
  networking.firewall = {
    enable = true;
    trustedInterfaces = [ config.services.tailscale.interfaceName ];
    allowedUDPPorts = [ config.services.tailscale.port ];
  };

  systemd.services.tailscaled.serviceConfig.Environment = [
    "TS_DEBUG_FIREWALL_MODE=nftables"
  ];

  systemd.network.wait-online.enable = false;
  boot.initrd.systemd.network.wait-online.enable = false;
}
