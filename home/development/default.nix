{ pkgs, config, ... }:
{
  imports = [
    ./claude
    ./git
    ./neovim
  ];

  home.packages = [
    (pkgs.callPackage ./kotlin-lsp.nix { })
    pkgs.kubectl
  ];
}
