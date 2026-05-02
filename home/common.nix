{ pkgs, config, ... }:
{
  imports = [
    ./alacritty
    ./android
    ./brave
    ./carapace
    ./claude
    ./fcitx5
    ./git
    ./kde
    ./kicad
    ./hyprland
    ./neovim
    ./niri
    ./nushell
    ./postman
    ./starship
    ./vscode
    ./yazi
    ./zellij
  ];

  home.packages = with pkgs; [
    vim
    git

    nnn

    zip
    xz
    unzip

    ripgrep
    jq
    fzf
    eza

    file
    which
    tree
    zstd

    btop

    lsof

    wl-clipboard
  ];

  programs.bash.enable = true;

  programs.gpg = {
    enable = true;

    mutableKeys = true;
    mutableTrust = true;
  };

  services.gpg-agent = {
    enable = true;

    defaultCacheTtl = 3600;
    pinentry.package = pkgs.pinentry-qt;
  };
}
