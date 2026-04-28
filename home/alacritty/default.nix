{ pkgs, config, ... }: {
  programs.alacritty = {
    enable = true;
    settings = {
      env.TERM = "xterm-256color";
    };
  };

  home.file.".config/alacritty" = {
    source = ./config;
    recursive = true;
  };
}
