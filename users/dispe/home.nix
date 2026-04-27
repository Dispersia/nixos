{ pkgs, hostName, ... }: {
  imports = [
    ../../home/core.nix
    ../../home/common.nix

    ../../home/alacritty
    ../../home/fcitx5
    ../../home/git
    ../../home/hyprland
    ../../home/neovim
    ../../home/waybar
    ../../home/yazi
    ../../home/zellij
  ];

  programs.vscode = {
    enable = true;
    package = pkgs.vscode.fhs;
  };

  home.shellAliases = {
    nix-switch = "sudo nixos-rebuild switch --flake ~/.config/nixos#${hostName}";
  };

  programs.bash.enable = true;

  

  programs.brave = {
    enable = true;
    package = pkgs.brave;
    extensions = [
      { id = "eimadpbcbfnmbkopoojfekhnkhdbieeh"; } # dark-reader
      { id = "nngceckbapebfimnlniiiahkandclblb"; } # bitwarden
    ];
  };

  programs.alacritty = {
    enable = true;
    settings = {
      env.TERM = "xterm-256color";
    };
  };

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

  home.stateVersion = "25.11";
}
