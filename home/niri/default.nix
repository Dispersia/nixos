{ inputs, pkgs, config, ... }:
{
  home.packages = with pkgs; [ niri ];

  home.file.".config/niri" = {
    source = ./config;
    recursive = true;
  };

  imports = [ inputs.dms.homeModules.dank-material-shell ];
}
