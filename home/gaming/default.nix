{ pkgs, ... }:
{
  home.packages = with pkgs; [
    protonup-qt
    mangohud
    goverlay

    (symlinkJoin {
      name = "discord";
      paths = [ discord ];
      nativeBuildInputs = [ makeWrapper ];
      postBuild = ''
        wrapProgram $out/bin/discord \
          --add-flags "--enable-wayland-ime"
      '';
    })
  ];
}
