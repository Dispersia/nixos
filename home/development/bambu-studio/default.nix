{ pkgs, ... }:
let
  pname = "bambu-studio";
  version = "02.07.01.57";

  src = pkgs.fetchurl {
    url = "https://github.com/bambulab/BambuStudio/releases/download/v${version}/BambuStudio_ubuntu-24.04-v${version}-20260601192128.AppImage";
    hash = "sha256-hbBThT8aI4d1zXri1NGVRONSYFkkKNInbKJ9y9X461M=";
  };

  appimageContents = pkgs.appimageTools.extractType2 { inherit pname version src; };

  base = pkgs.appimageTools.wrapType2 {
    inherit pname version src;
    extraPkgs = pkgs: with pkgs; [ webkitgtk_4_1 glib-networking ];
  };

  bambu-studio = pkgs.symlinkJoin {
    name = "${pname}-${version}";
    paths = [ base ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      install -Dm444 ${appimageContents}/BambuStudio.desktop \
        $out/share/applications/${pname}.desktop
      install -Dm444 ${appimageContents}/BambuStudio.png \
        $out/share/icons/hicolor/192x192/apps/${pname}.png
      substituteInPlace $out/share/applications/${pname}.desktop \
        --replace-fail 'Exec=AppRun' 'Exec=${pname}' \
        --replace-fail 'Icon=BambuStudio' 'Icon=${pname}'

      rm $out/bin/${pname}
      makeWrapper ${base}/bin/${pname} $out/bin/${pname} \
        --set GIO_EXTRA_MODULES ${pkgs.glib-networking}/lib/gio/modules
    '';
  };
in
{
  home.packages = [ bambu-studio ];
}
