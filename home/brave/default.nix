{ pkgs, config, ... }:
{
  programs.brave = {
    enable = true;
    package = pkgs.brave;
    extensions = [
      { id = "eimadpbcbfnmbkopoojfekhnkhdbieeh"; } # dark-reader
      { id = "nngceckbapebfimnlniiiahkandclblb"; } # bitwarden
      { id = "pnmaklegiibbioifkmfkgpfnmdehdfan"; } # 10ten
    ];
    commandLineArgs = [
      "--password-store=basic"
    ];
  };
}
