{ pkgs, hostName, ... }:
{
  imports = [
    ../../home/core.nix
    ../../home/common.nix
  ];

  home.shellAliases = {
    nix-switch = "sudo nixos-rebuild switch --flake ~/.config/nixos";
  };

  home.stateVersion = "26.05";
}
