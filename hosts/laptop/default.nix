{
  config,
  pkgs,
  username,
  ...
}:
{
  imports = [
    ../../modules/system.nix

    ./hardware-configuration.nix
  ];

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.kernelParams = [ "nvidia-drm.modeset=1" ];

  hardware.nvidia = {
    modesetting.enable = true;
    open = false;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  services.xserver.videoDrivers = [ "nvidia" ];

  networking.hostName = "${username}";
  networking.networkmanager.enable = true;

  system.stateVersion = "25.11";
}
