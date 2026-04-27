{ pkgs, config, ... }: {
  home.packages = [
    pkgs.zellij
  ];
  
  home.file.".config/zellij" = {
    source = ./config;
    recursive = true;
  };
}