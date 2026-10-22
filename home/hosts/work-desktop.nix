{ pkgs, inputs, ... }:
{
  imports = [
    ../cli

    ../development/android
    ../development/arduino
    ../development/blender
    ../development/claude
    ../development/git
    ../development/kicad
    ../development/kubectl
    ../development/neovim
    ../development/node
    ../development/opencode
    ../development/postgresql
    ../development/postman
    ../development/vscode

    ../environment/alacritty
    ../environment/brave
    ../environment/fcitx5
    ../environment/gpg
    ../environment/gtk
    ../environment/kde
    ../environment/obsidian
    ../environment/yazi
    ../environment/zellij

    ../language/anki

    ../shell/carapace
    ../shell/direnv
    ../shell/nushell
    ../shell/starship

    ../gaming
  ];

  # azure-cli from unstable currently pulls in python3.14-fabric, which nixpkgs
  # marks broken because fabric 3.2.3 is incompatible with invoke 3. Use the
  # stable input (invoke 2.x) until fabric is fixed upstream.
  home.packages = [
    inputs.nixpkgs-stable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.azure-cli
  ];
}
