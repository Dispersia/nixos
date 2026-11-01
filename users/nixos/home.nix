{
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
}
