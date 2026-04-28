{ pkgs, config, ... }:
{
  home.packages = [
    pkgs.yazi
  ];

  home.file.".config/yazi" = {
    source = ./config;
    recursive = true;
  };
}
