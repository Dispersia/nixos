{ pkgs, hostName, ... }:
{
  imports = [
    ../../home/core.nix
    ../../home/hosts/${hostName}.nix
  ];

  home.stateVersion = "26.05";
}
