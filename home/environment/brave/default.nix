{
  pkgs,
  lib,
  config,
  ...
}:
let
  brave = pkgs.brave // {
    override =
      {
        commandLineArgs ? "",
        ...
      }:
      pkgs.brave.overrideAttrs (old: {
        preFixup = (old.preFixup or "") + ''
          gappsWrapperArgs+=(--add-flags ${lib.escapeShellArg commandLineArgs})
        '';
      });
  };
in
{
  programs.chromium = {
    enable = true;
    package = brave;
    extensions = [
      { id = "eimadpbcbfnmbkopoojfekhnkhdbieeh"; } # dark-reader
      { id = "nngceckbapebfimnlniiiahkandclblb"; } # bitwarden
      { id = "pnmaklegiibbioifkmfkgpfnmdehdfan"; } # 10ten
      { id = "dhdgffkkebhmkfjojejmpbldmpobfkfo"; } # Tampermonkey
      { id = "gebbhagfogifgggkldgodflihgfeippi"; } # Return Youtube Dislike
      { id = "ldmgbgaoglmaiblpnphffibpbfchjaeg"; } # New TongWenTang
      { id = "khncfooichmfjbepaaaebmommgaepoid"; } # Unhook
      { id = "eiimnmioipafcokbfikbljfdeojpcgbh"; } # BlockSite
    ];
    commandLineArgs = [
      "--password-store=basic"
      "--disable-features=OutdatedBuildDetector,UseChromeOSDirectVideoDecoder,WebRtcAllowInputVolumeAdjustment"
    ];
  };

  xdg.dataFile."applications/mimeapps.list".force = true;

  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "x-scheme-handler/http" = "brave-browser.desktop";
      "x-scheme-handler/https" = "brave-browser.desktop";
      "text/html" = "brave-browser.desktop";
    };
  };
}
