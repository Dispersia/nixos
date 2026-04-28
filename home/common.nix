{ pkgs, config, ... }:
{
  imports = [
    ./alacritty
    ./brave
    ./carapace
    ./fcitx5
    ./git
    ./kde
    ./hyprland
    ./neovim
    ./nushell
    ./starship
    ./vscode
    ./waybar
    ./yazi
    ./zellij
  ];

  home.packages = with pkgs; [
    vim
    git

    neofetch
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

    tree-sitter

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
