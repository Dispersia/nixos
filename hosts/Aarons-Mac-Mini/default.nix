{
  config,
  pkgs,
  hostName,
  username,
  ...
}:
{
  imports = [
    ../../modules/darwin-system.nix
  ];

  users.users.${username}.home = "/Users/dispe";

  system.primaryUser = username;

  homebrew.enable = false;

  system.stateVersion = 6;
}
