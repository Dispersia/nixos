{ pkgs, ... }:
{
  imports = [
    ./language
    ./gaming
    ./environment/fcitx5
    ./environment/kde
    ./environment/niri
    ./development/android
    ./development/freecad
    ./development/kicad
    ./development/postman
    ./development/vscode
  ];

  gtk = {
    enable = true;
    theme = {
      name = "Adwaita-dark";
      package = pkgs.gnome-themes-extra;
    };
  };

  home.packages = with pkgs; [
    wl-clipboard
    postgresql
  ];

  services.gpg-agent = {
    enable = true;

    defaultCacheTtl = 3600;
    pinentry.package = pkgs.pinentry-qt;
  };
}
