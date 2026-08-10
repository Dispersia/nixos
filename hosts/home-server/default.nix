{
  config,
  pkgs,
  lib,
  hostName,
  ...
}:
{
  imports = [
    ../../modules/system.nix
    ../../modules/nordvpn.nix
    ../../modules/tailscale.nix

    ./hardware-configuration.nix
  ];

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  boot.kernelPackages = pkgs.linuxPackages_latest;

  services.displayManager.sddm = {
    enable = lib.mkForce true;
    wayland.enable = true;
  };

  networking.hostName = hostName;
  networking.networkmanager.enable = true;
  networking.firewall.allowedTCPPorts = [
    3724
    8085
  ];

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = true;
      PermitRootLogin = "no";
    };
  };

  services.komga = {
    enable = true;
    settings = {
      server.port = 25500;
    };
  };

  systemd.targets.sleep.enable = false;
  systemd.targets.suspend.enable = false;
  systemd.targets.hibernate.enable = false;
  systemd.targets.hybrid-sleep.enable = false;

  system.stateVersion = "26.11";
}
