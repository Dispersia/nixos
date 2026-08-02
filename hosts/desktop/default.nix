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

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  systemd.services.bluetooth-link-key-sync = {
    description = "Sync BR/EDR link key with Windows dual-boot";
    before = [ "bluetooth.service" ];
    wantedBy = [ "bluetooth.service" ];
    serviceConfig.Type = "oneshot";
    script = ''
      info="/var/lib/bluetooth/00:1A:7D:DA:71:15/01:29:B5:0A:13:BD/info"
      [ -f "$info" ] || exit 0
      ${pkgs.gnused}/bin/sed -i 's/^Key=.*/Key=8D45FD33B5A7B9B60638BC91B6D038FC/' "$info"
    '';
  };

  system.stateVersion = "26.11";
}
