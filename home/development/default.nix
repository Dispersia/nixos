{ pkgs, config, ... }:
{
  imports = [
    ./claude
    ./git
    ./neovim
    ./opencode
  ];

  home.packages = [
    (pkgs.callPackage ./kotlin-lsp.nix { })
    pkgs.bun
    pkgs.kubectl
    pkgs.nodejs
  ];
}
