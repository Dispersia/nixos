{ pkgs, ... }:
{
  imports = [
    ./language
    ./gaming
    ./environment/fcitx5
    ./environment/kde
    ./development/android
    ./development/arduino
    ./development/bambu-studio
    ./development/blender
    ./development/kicad
    ./development/postman
    ./development/unityhub
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
    qbittorrent
    podman-desktop
  ];

  services.gpg-agent = {
    enable = true;

    defaultCacheTtl = 3600;
    pinentry.package = pkgs.pinentry-qt;
  };
}
