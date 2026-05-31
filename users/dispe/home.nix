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

  home.homeDirectory = "/home/${username}";

  home.stateVersion = "26.11";
}
