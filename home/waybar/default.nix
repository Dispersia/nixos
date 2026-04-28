{ pkgs, config, ... }:
{
  home.packages = [
    pkgs.waybar
  ];

  home.file.".config/waybar" = {
    source = ./config;
    recursive = true;
  };
}
