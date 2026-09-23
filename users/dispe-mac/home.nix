{
  pkgs,
  hostName,
  username,
  ...
}:
{
  imports = [
    ../../home/core.nix
    ../../home/hosts/${hostName}.nix
  ];

  home.homeDirectory = "/Users/dispe";

  home.stateVersion = "26.11";
}
