{ pkgs, config, ... }:
{
  imports = [
    ./android
    ./claude
    ./git
    ./kicad
    ./neovim
    ./postman
    ./vscode
  ];

  home.packages = [
    (pkgs.callPackage ./kotlin-lsp.nix { })
  ];
}
