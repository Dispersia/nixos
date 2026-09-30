{
  pkgs,
  lib,
  config,
  ...
}:
let
  brave = if pkgs.stdenv.hostPlatform.isLinux then
   pkgs.brave // {
    override =
      {
        commandLineArgs ? "",
        ...
      }:
      pkgs.brave.overrideAttrs (old: {
        preFixup = (old.preFixup or "") + ''
          gappsWrapperArgs+=(
            --add-flags ${lib.escapeShellArg commandLineArgs}
            --prefix LD_LIBRARY_PATH : ${pkgs.vulkan-loader}/lib
            --prefix XDG_DATA_DIRS : /run/opengl-driver/share
          )
        '';
      });
  }
 else
    pkgs.brave;
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
