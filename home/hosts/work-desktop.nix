{ pkgs, ... }:
{
  imports = [
    ../common.nix
    ../development
    ../environment
    ../shell
    ../linux.nix
  ];

  home.packages = [ pkgs.nodejs ];
}
