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
    xwayland-satellite
    swaybg
  ];

  dconf.settings."org/gnome/desktop/interface" = {
    color-scheme = "prefer-dark";
  };

  programs.noctalia-shell = {
    enable = true;
    settings = {
      colorSchemes = {
        darkMode = true;
        predefinedScheme = "Tokyo-Night";
      };
      general = {
        enableShadows = false;
      };
      bar = {
        outerCorners = false;
      };
    };
  };

  home.file.".config/niri" = {
    source = ./config;
    recursive = true;
  };
}
