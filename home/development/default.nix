{ pkgs, config, ... }:
{
  imports = [
    ./git
    ./neovim
  ];

  home.packages = [
    (pkgs.callPackage ./kotlin-lsp.nix { })
    pkgs.kubectl
  ];
}
