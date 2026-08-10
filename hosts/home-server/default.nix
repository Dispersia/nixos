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

  system.stateVersion = "26.11";
}
