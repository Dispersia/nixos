{ pkgs, lib, ... }:
{
  programs.gpg = {
    enable = true;

    mutableKeys = true;
    mutableTrust = true;
  };

  services.gpg-agent = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    enable = true;

    defaultCacheTtl = 3600;
    pinentry.package = pkgs.pinentry-qt;
  };
}
