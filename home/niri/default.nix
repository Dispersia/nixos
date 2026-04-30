{ pkgs, config, ... }:
{
  home.packages = with pkgs; [ niri ];

  home.file.".config/niri" = {
    source = ./config;
    recursive = true;
  };
}
