{
  pkgs,
  inputs,
  lib,
  config,
  ...
}:
let
  # `brave` was removed from nixpkgs-unstable (no maintainers left to unblock
  # security issues), so take it from the pinned nixpkgs-stable. Everything
  # else stays on the unstable `pkgs`.
  stable = inputs.nixpkgs-stable.legacyPackages.${pkgs.stdenv.hostPlatform.system};

  brave = if pkgs.stdenv.hostPlatform.isLinux then
   stable.brave // {
    override =
      {
        commandLineArgs ? "",
        ...
      }:
      stable.brave.overrideAttrs (old: {
        preFixup = (old.preFixup or "") + ''
          gappsWrapperArgs+=(
            --add-flags ${lib.escapeShellArg commandLineArgs}
            --prefix LD_LIBRARY_PATH : ${stable.vulkan-loader}/lib
            --prefix XDG_DATA_DIRS : /run/opengl-driver/share
          )
        '';
      });
  }
  else
    stable.brave;
in
{
  programs.chromium = {
    enable = true;
    package = brave;
    # macOS 27 (Golden Gate) protects Brave's user-data directory with the new
    # kTCCServiceSystemPolicyAppDataDetailed / com.apple.macl rule, so Home
    # Manager can no longer create External Extensions/*.json there (native
    # messaging hosts are the only exempt path). Only manage extensions on
    # Linux; on macOS install them from the Web Store, where they persist in
    # the profile (and restore via Brave Sync).
    extensions = lib.optionals pkgs.stdenv.hostPlatform.isLinux [
      { id = "eimadpbcbfnmbkopoojfekhnkhdbieeh"; } # dark-reader
      { id = "nngceckbapebfimnlniiiahkandclblb"; } # bitwarden
      { id = "pnmaklegiibbioifkmfkgpfnmdehdfan"; } # 10ten
      { id = "dhdgffkkebhmkfjojejmpbldmpobfkfo"; } # Tampermonkey
      { id = "gebbhagfogifgggkldgodflihgfeippi"; } # Return Youtube Dislike
      { id = "iokfkfickldinmejhpfcngiocoedkpkh"; } # LingLook
      { id = "khncfooichmfjbepaaaebmommgaepoid"; } # Unhook
      { id = "eiimnmioipafcokbfikbljfdeojpcgbh"; } # BlockSite
      { id = "jnnihcnhddahioablihllmfgilcffppc"; } # Gemini Blocker
    ];
    commandLineArgs = [
      "--password-store=basic"
      "--disable-features=OutdatedBuildDetector,UseChromeOSDirectVideoDecoder,WebRtcAllowInputVolumeAdjustment"
    ];
  };

  xdg = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    dataFile."applications/mimeapps.list".force = true;
    configFile."mimeapps.list".force = true;

    mimeApps = {
    enable = true;
    defaultApplications = {
      "x-scheme-handler/http" = "brave-browser.desktop";
      "x-scheme-handler/https" = "brave-browser.desktop";
      "text/html" = "brave-browser.desktop";
      "x-scheme-handler/postman" = "Postman.desktop";
    };
    associations.added = {
      "x-scheme-handler/postman" = "Postman.desktop";
    };
  };
};
}
