{ pkgs, ... }:
let
  blenderScripts = pkgs.runCommand "blender-user-scripts" { } ''
    mkdir -p $out/addons
    cp -r ${./addons}/. $out/addons/
  '';

  blenderWithAddons = pkgs.symlinkJoin {
    name = "blender-with-addons";
    paths = [ pkgs.blender ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/blender \
        --set BLENDER_USER_SCRIPTS ${blenderScripts}
    '';
  };
in
{
  home.packages = [ blenderWithAddons ];
}
