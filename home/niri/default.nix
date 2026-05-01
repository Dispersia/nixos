{
  inputs,
  pkgs,
  config,
  ...
}:
{
  imports = [ inputs.dms.homeModules.dank-material-shell ];

  home.packages = with pkgs; [
    niri
    fuzzel
    swaylock
    mako
    swayidle
  ];

  programs.dank-material-shell = {
    enable = true;
    enableSystemMonitoring = true;
  };

  home.file.".config/niri" = {
    source = ./config;
    recursive = true;
  };
}
