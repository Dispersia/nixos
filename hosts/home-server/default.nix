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

  # Force 192.168.4.50. The eero DHCP reservation for MAC
  # 84:47:09:8e:c1:96 is not being honored, so pin the address statically.
  networking.interfaces.eno1 = {
    useDHCP = false;
    ipv4.addresses = [
      {
        address = "192.168.4.50";
        prefixLength = 22;
      }
    ];
  };
  networking.defaultGateway = "192.168.4.1";

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
      # Aarons-Mac-Mini (the yomifin-ocr sidecar host) for remote diagnostics.
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDvZJllZzaxzzsigwwN4UdTfrb3xDkZuZY9n2H13XawBXi88bRrHLfFiSOoJjJAbm166lNoaFoewf4cw4xGZNj/1UCPQlHEzFZTe3TiNooOuB5qrPe6mhDVx97QyDVC1ZBmO+WgDnJXx6V6DfAsROzswu4410uIswk+5gommpG4aro00yrdoABtCdaUpwWLdO6iU8nzVFoa3J6+nIuOx4IFWNepM/2FqFbHtJ4SxpH9ZzeHl26d+RG2L0kD7YKSBxS1eP6ayLqCMKaCqqOPUN+kUxqA9GkJGXi57LYR+uY5Ftzh5WP+Fm8dAKz3yQfLaycvaOx6noor6Hhbh1I3234w3O3SJGNbRTPcAAjbRfeVNjFU8/xuHGnq1haLMUq1Zact5UYtwJ9JGIf7fNQ4/w7qho3xyhIRqdeq3uLdpe90zd0PA70oH3aQK46spB9pIXe2dYfd+HK3QtLcDrB/vlwTqfjQnjmEJijMlTnY5pVH4gzlBVWdztMn6i+0jAsTRD8= dispe@Aarons-Mac-Mini.local"
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
