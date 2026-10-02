{
  lib,
  pkgs,
  hostName,
  username,
  ...
}:
{
  imports = [
    ../../modules/jellyfin.nix
    ../../modules/tailscale.nix
    ../../modules/hashicorp-bin.nix
    ../../modules/comin.nix

    ./cluster-containers.nix
    ./nfs.nix

    ./hardware-configuration.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 10;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = hostName;
  networking.useDHCP = true;

  nixpkgs.config.allowUnfreePredicate =
    pkg:
    builtins.elem (lib.getName pkg) [
      "consul"
      "nomad"
    ];

  users.users.${username} = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
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

  services.tailscale = {
    useRoutingFeatures = "server";
    extraSetFlags = [ "--advertise-routes=10.50.0.0/24" ];
  };

  environment.systemPackages = with pkgs; [
    git
    vim
    consul
    nomad
    openbao
    jq
    openssl
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

  nix.optimise.automatic = true;

  system.stateVersion = "26.05";
}
