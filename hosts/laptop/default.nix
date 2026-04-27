{ config, pkgs, username, ... }: {
  imports = [
    ../../modules/system.nix

    ./hardware-configuration.nix
  ];

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  boot.kernelPackages = pkgs.linuxPackages_latest;

  networking.hostName = "${username}";
  networking.networkmanager.enable = true;

  system.stateVersion = "25.11";
}