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
    uid = 501;
    shell = pkgs.nushell;
  };

  system.primaryUser = username;

  homebrew.enable = false;

  system.stateVersion = 6;

  power = {
    sleep = {
      computer = "never";
      harddisk = "never";
    };

    restartAfterPowerFailure = true;
    restartAfterFreeze = true;
  };

  system.activationScripts.disableSleep.text = ''
    echo "configuring always-on server power settings..." >&2
    /usr/bin/pmset -a sleep 0
    /usr/bin/pmset -a disablesleep 1
  '';
}
