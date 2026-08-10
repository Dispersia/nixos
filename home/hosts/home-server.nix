{ pkgs, ... }:
{
  imports = [
    ../common.nix
    ../development/git
    ../development/neovim
    ../environment/alacritty
    ../environment/brave
    ../environment/kde
    ../environment/yazi
    ../environment/zellij
    ../shell
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
  ];

  services.gpg-agent = {
    enable = true;

    defaultCacheTtl = 3600;
    pinentry.package = pkgs.pinentry-qt;
  };
}
