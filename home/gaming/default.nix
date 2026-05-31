{ pkgs, ... }:
{
  home.packages = with pkgs; [
    protonup-qt
    mangohud
    goverlay
  ];
}
