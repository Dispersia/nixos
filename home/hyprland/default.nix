{ pkgs, config, ... }:
{
  home.packages = [
    pkgs.hyprland
  ];

  home.file.".config/hypr" = {
    source = ./config;
    recursive = true;
  };
}
