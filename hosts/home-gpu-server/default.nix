{
  lib,
  pkgs,
  hostName,
  username,
  ...
}:
{
  imports = [
    ../../modules/comin.nix
  ]
  # Generated on the device after install (`nixos-generate-config`).
  ++ lib.optional (builtins.pathExists ./hardware-configuration.nix) ./hardware-configuration.nix
  # Placeholder so the flake still evaluates before the machine exists. Once
  # `hardware-configuration.nix` is generated it takes over.
  ++ lib.optional (!builtins.pathExists ./hardware-configuration.nix) {
    fileSystems."/" = {
      device = "tmpfs";
      fsType = "tmpfs";
    };
    boot.loader.grub.enable = false;
    boot.loader.systemd-boot.enable = false;
  };

  hardware.nvidia-jetpack = {
    enable = true;
    som = "orin-nano";
    carrierBoard = "devkit";
  };

  hardware.graphics.enable = true;

  # GPU containers (CUDA passthrough via CDI: `--device=nvidia.com/gpu=all`).
  hardware.nvidia-container-toolkit.enable = true;
  virtualisation.docker.enable = true;

  nixpkgs.config.allowUnfree = true;

  networking.hostName = hostName;
  networking.networkmanager.enable = true;

  users.users.${username} = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "video"
      "docker"
    ];
    shell = pkgs.nushell;

    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDdHpd3gl8yy7jn4YPArVSj6bBNwaSMs8aewIF2/rmSqKy7yVfXdND3wESZHqH5FV69pQrEHk6ANe6nKmIqG+bKQ3UjLCJh9X+g7Ox8ZZBN7uakHYtetF9KtX3+h6hUBUsBDQvqdJucsUHZAz5P0tv+Zm+GsUuAscAu0wF7ZSOXtSX1MgJ4N86YnFCmYZEQ8Uvn7QJqmIm+1/SkIQLoSb8W1ZE8pygvjPwEK8Jc2hTl7WsmQt/xAeaOqY5Rk6dJM3Np9Rh6XY3LZOBck6ZwsSvIzK4imzhnUItscgu8lVmNX7s4bMlQz95270Hyby5ZcoM3xPlzhnA4dR5Z+ve55g+aHLhc/wdem+N2slVBhigvo0pHfKsoc+qNjcvqiUcrEurhlMV14kwLWaNGZz67qw9G2zt/SM+/RRVjvpHzvslXf85+dTJz9fP3XE3Cs6uGUW6tAhbIfsCbZ7V9tCnElGEyEd5ldpvYUPCsUby1nUvp3hI0ogioHQ20XFx6ufQrDas= dispe@desktop"
    ];
  };

  environment.shells = [ pkgs.nushell ];

  services.openssh = {
    enable = true;

    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  environment.systemPackages = with pkgs; [
    git
    vim
  ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 3d";
  };

  system.stateVersion = "26.11";
}
