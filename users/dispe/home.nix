{ pkgs, hostName, ... }: {
  imports = [
    ../../home/core.nix
    ../../home/common.nix

    ../../home/alacritty
    ../../home/brave
    ../../home/carapace
    ../../home/fcitx5
    ../../home/git
    ../../home/kde
    ../../home/hyprland
    ../../home/neovim
    ../../home/nushell
    ../../home/starship
    ../../home/vscode
    ../../home/waybar
    ../../home/yazi
    ../../home/zellij
  ];

  home.shellAliases = {
    nix-switch = "sudo nixos-rebuild switch --flake ~/.config/nixos";
  };

  home.stateVersion = "25.11";
}
