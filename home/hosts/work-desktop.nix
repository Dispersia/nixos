{ pkgs, ... }:
{
  imports = [
    ../common.nix
    ../linux.nix
  ];

  home.packages = [ pkgs.nodejs ];
}
