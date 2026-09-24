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

  users.knownUsers = [ "${username}" ];
  users.users.${username} = {
    home = "/Users/${username}";
    uid = 504;
    shell = pkgs.nushell;
  };

  system.primaryUser = username;

  homebrew.enable = false;

  system.stateVersion = 6;
}
