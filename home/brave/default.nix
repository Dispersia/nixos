{ pkgs, config, ... }:
{
  programs.brave = {
    enable = true;
    package = pkgs.brave;
    extensions = [
      { id = "eimadpbcbfnmbkopoojfekhnkhdbieeh"; } # dark-reader
      { id = "nngceckbapebfimnlniiiahkandclblb"; } # bitwarden
    ];
    commandLineArgs = [
      "--password-store=basic"
    ];
  };
}
