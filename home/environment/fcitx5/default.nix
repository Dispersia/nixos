{ config, pkgs, ... }:
{
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5 = {
      addons = with pkgs; [
        fcitx5-mozc
        fcitx5-hangul
        fcitx5-chewing

        fcitx5-gtk
        kdePackages.fcitx5-qt
        qt6Packages.fcitx5-configtool
      ];
      settings = {
        inputMethod = {
          GroupOrder."0" = "Default";
          "Groups/0" = {
            Name = "Default";
            "Default Layout" = "us";
            DefaultIM = "mozc";
          };
          "Groups/0/Items/0".Name = "keyboard-us";
          "Groups/0/Items/1".Name = "mozc";
          "Groups/0/Items/2".Name = "hangul";
          "Groups/0/Items/3".Name = "chewing";
        };
      };
      waylandFrontend = true;
    };
  };
}
