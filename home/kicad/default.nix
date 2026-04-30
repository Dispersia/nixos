{ pkgs, config, ... }:
{
  home.packages = with pkgs; [ kicad ];
}
