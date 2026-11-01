{
  pkgs,
  lib,
  ...
}:
{
  imports = [
    ../cli

    ../development/claude
    ../development/git
    ../development/kubectl
    ../development/neovim
    ../development/node
    ../development/opencode
    ../development/postgresql

    ../environment/gpg
    ../environment/yazi
    ../environment/zellij

    ../shell/carapace
    ../shell/direnv
    ../shell/nushell
    ../shell/starship
  ];

  services.gpg-agent.pinentry.package = lib.mkForce pkgs.pinentry-curses;
}
