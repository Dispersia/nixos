{ ... }:
{
  imports = [
    ../cli

    ../development/git
    ../development/neovim
    ../development/node
    ../development/opencode

    ../environment/alacritty
    ../environment/brave
    ../environment/discord
    ../environment/gpg
    ../environment/yazi
    ../environment/zellij

    ../shell/carapace
    ../shell/direnv
    ../shell/nushell
    ../shell/starship
  ];

  # macOS "App Management" (TCC) cannot be granted to the comin deploy daemon,
  # so Home Manager's copyApps mode fails every activation and runs
  # `tccutil reset SystemPolicyAppBundles`, which wipes the permission you gave
  # Alacritty (and aborts the switch before Discord etc. get installed).
  # Symlinking the apps needs no TCC permission and works under comin.
  targets.darwin = {
    copyApps.enable = false;
    linkApps.enable = true;
  };
}
