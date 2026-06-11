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

  programs.noctalia = {
    enable = true;
    settings = {
      theme = {
        mode = "dark";
        source = "builtin";
        builtin = "Tokyo-Night";
      };
      shell = {
        enable_shadows = false;
      };
    };
  };

  home.file.".config/niri" = {
    source = ./config;
    recursive = true;
  };
}
