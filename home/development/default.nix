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
    pkgs.kubectl
  ];
}
