{
  config,
  pkgs,
  hostName,
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
    open = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  services.xserver.videoDrivers = [ "nvidia" ];

  environment.sessionVariables = {
    GBM_BACKEND = "nvidia-drm";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
  };

  networking.hostName = hostName;
  networking.networkmanager.enable = true;

  system.stateVersion = "26.11";
}
