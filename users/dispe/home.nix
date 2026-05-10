{ pkgs, hostName, username, ... }:
{
  imports = [
    ../../home/core.nix
    ../../home/hosts/${hostName}.nix
  ];

  home.homeDirectory = "/home/${username}";

  home.shellAliases = {
    nix-switch = "sudo nixos-rebuild switch --flake ~/.config/nixos";
  };

  home.stateVersion = "26.05";
}
