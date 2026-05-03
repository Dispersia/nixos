{ pkgs, config, ... }:
{
  imports = [
    ./alacritty
    ./brave
    ./fcitx5
    ./kde
    ./niri
    ./yazi
    ./zellij
  ];
}
