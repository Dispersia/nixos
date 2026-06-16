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

  services.mako = {
    enable = true;
    settings = {
      font = "sans-serif 11";
      width = 360;
      height = 120;
      margin = "12";
      padding = "14";
      border-size = 2;
      border-radius = 10;
      default-timeout = 5000;
      anchor = "top-right";
      max-visible = 5;

      background-color = "#1a1b26";
      text-color = "#c0caf5";
      border-color = "#7aa2f7";
      progress-color = "over #292e42";

      "urgency=low" = {
        border-color = "#565f89";
        default-timeout = 3000;
      };
      "urgency=critical" = {
        border-color = "#f7768e";
        default-timeout = 0;
      };
    };
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
