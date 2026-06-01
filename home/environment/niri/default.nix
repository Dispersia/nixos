{
  inputs,
  pkgs,
  config,
  ...
}:
{
  imports = [ inputs.noctalia-shell.homeModules.default ];

  home.packages = with pkgs; [
    niri
    fuzzel
    swaylock
    mako
    swayidle
    xwayland
  ];

  programs.noctalia-shell = {
    enable = true;
  };

  home.file.".config/niri" = {
    source = ./config;
    recursive = true;
  };
}
