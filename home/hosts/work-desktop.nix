{ pkgs, ... }:
{
  imports = [
    ../common.nix
    ../development
    ../development/claude
    ../environment
    ../shell
    ../linux.nix
  ];

  home.packages = [
    pkgs.azure-cli
  ];
}
