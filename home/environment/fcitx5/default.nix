{ config, pkgs, ... }:
{
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5 = {
      addons = with pkgs; [
        fcitx5-mozc
        fcitx5-rime

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
          "Groups/0/Items/2".Name = "rime";
        };
      };
      waylandFrontend = true;
    };
  };

  # Rime: Taiwanese Traditional Mandarin with Zhuyin (Bopomofo).
  # rime-data (pulled in by fcitx5-rime) ships the bopomofo / bopomofo_tw
  # schemas; this restricts deployment to 注音·臺灣正體.
  xdg.dataFile."fcitx5/rime/default.custom.yaml".text = ''
    patch:
      schema_list:
        - schema: bopomofo_tw
  '';
}
