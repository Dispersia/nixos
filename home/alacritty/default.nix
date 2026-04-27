{ pkgs, config, ... }: {
  home.packages = [
    pkgs.alacritty
  ];
  
  home.file.".config/alacritty" = {
    source = ./config;
    recursive = true;
  };
}