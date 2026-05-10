{ pkgs, hostName, username, ... }:
{
  imports = [
    ../../home/core.nix
    ../../home/hosts/${hostName}.nix
  ];

  home.homeDirectory = "/Users/${username}";

  home.stateVersion = "26.05";
}
