{ config, pkgs, ... }:
{
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5 = {
      addons = with pkgs; [
        fcitx5-mozc
        fcitx5-rime
        fcitx5-hangul

        fcitx5-gtk
        qt6Packages.fcitx5-configtool
      ];
      settings = {
        inputMethod = {
          "Groups/0/Items/0" = { Name = "keyboard-us"; };
          "Groups/0/Items/1" = { Name = "mozc"; };
          "Groups/0/Items/2" = { Name = "chewing"; };
          "Groups/0/Items/3" = { Name = "hangul"; };
        };
      };
      waylandFrontend = true;
    };
  };
}
