{
  inputs,
  pkgs,
  hostName,
  username,
  ...
}:
{
  imports = [
    inputs.nixos-wsl.nixosModules.default
    ../../modules/comin.nix
    ../../modules/kimaki.nix
  ];

  wsl = {
    enable = true;
    defaultUser = username;
  };

  # Kimaki (the Discord bot for OpenCode 2) in gateway mode. It starts at boot
  # and keeps running; the first start prints a one-time install URL that has
  # to be authorized once in Discord. Read it with `journalctl -u kimaki -f`.
  services.kimaki = {
    enable = true;
    user = username;
    machineName = hostName;
  };

  networking.hostName = hostName;

  users.mutableUsers = false;

  users.users.${username} = {
    isNormalUser = true;
    description = username;
    extraGroups = [
      "wheel"
      "docker"
    ];
    shell = pkgs.nushell;
    hashedPassword = "$6$VJJxmf.mb9Z5qP8/$tqID2ttKzN/d9tELnVdrR1MVDeMy.JdxEOuOhRWKDDg809IGo5E2s/QSknrw72Lmk/Vl.gRCuf9K1fvDrd1N81";
  };

  environment.shells = [ pkgs.nushell ];

  virtualisation.docker.enable = true;

  programs.nix-ld.enable = true;

  nix.settings = {
    trusted-users = [ username ];
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    substituters = [ "https://cache.nixos.org" ];
    builders-use-substitutes = true;
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = " --delete-older-than 7d";
  };

  nixpkgs.config.allowUnfree = true;

  i18n.defaultLocale = "en_US.UTF-8";
  time.timeZone = "America/Phoenix";

  environment.systemPackages = with pkgs; [
    git
    vim
    curl
    wget
    ripgrep
    jq
    unzip
    which
    tree
    btop
    lsof
  ];

  system.stateVersion = "26.05";
}
