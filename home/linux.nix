{ pkgs, ... }:
{
  imports = [
    ./environment/fcitx5
    ./environment/kde
    ./environment/niri
    ./development/android
    ./development/kicad
    ./development/postman
    ./development/vscode
  ];

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
