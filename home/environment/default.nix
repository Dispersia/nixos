{ pkgs, config, ... }:
{
  imports = [
    ./alacritty
    ./brave
    ./yazi
    ./zellij
  ];
}
