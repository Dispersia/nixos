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

  programs.dms-shell = {
    enable = true;

    systemd = {
      enable = false;
    };
  };

  home.file.".config/niri" = {
    source = ./config;
    recursive = true;
  };
}
