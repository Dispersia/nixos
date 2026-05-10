{
  pkgs,
  lib,
  username,
  ...
}:
{ 
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];

    substituters = [
      "https://cache.nixos.org"
    ];

    builders-use-substitutes = true;
  };

  nix.gc = {
    automatic = lib.mkDefault true;
    options = lib.mkDefault " --delete-older-than 7d";
  };

  nixpkgs.config.allowUnfree = true;

  users.users.${username} = {
    shell = pkgs.nushell;
  };


  /*fonts = {
    packages = with pkgs; [
      material-design-icons

      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-color-emoji

      nerd-fonts.symbols-only
      nerd-fonts.fira-code
      nerd-fonts.jetbrains-mono
    ];

    fontconfig.defaultFonts = {
      serif = [
        "Noto Serif"
        "Noto Color Emoji"
      ];
      sansSerif = [
        "Noto Sans"
        "Noto Color Emoji"
      ];
      monospace = [
        "JetBrainsMono Nerd Font"
        "Noto Color Emoji"
      ];
      emoji = [ "Noto Color Emoji" ];
    };
  };*/
}
