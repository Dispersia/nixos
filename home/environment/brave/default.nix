{ pkgs, config, ... }:
{
  programs.chromium = {
    enable = true;
    package = pkgs.brave;
    extensions = [
      { id = "eimadpbcbfnmbkopoojfekhnkhdbieeh"; } # dark-reader
      { id = "nngceckbapebfimnlniiiahkandclblb"; } # bitwarden
      { id = "pnmaklegiibbioifkmfkgpfnmdehdfan"; } # 10ten
      { id = "dhdgffkkebhmkfjojejmpbldmpobfkfo"; } # Tampermonkey
    ];
    commandLineArgs = [
      "--password-store=basic"
      "--disable-features=WebRtcAllowInputVolumeAdjustment"
    ];
  };
}
