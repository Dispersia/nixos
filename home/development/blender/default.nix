{ pkgs, ... }:
let
  blenderScripts = pkgs.runCommand "blender-user-scripts" { } ''
    mkdir -p $out/addons
    cp -r ${./addons}/. $out/addons/
  '';

  quadRemesherLauncher = pkgs.writeShellScript "quadremesher-launcher" ''
    engineDir="$(dirname "$1")"
    export NIX_LD_LIBRARY_PATH="$engineDir:/run/current-system/sw/share/nix-ld/lib''${NIX_LD_LIBRARY_PATH:+:$NIX_LD_LIBRARY_PATH}"
    export LD_PRELOAD="${pkgs.zlib}/lib/libz.so.1''${LD_PRELOAD:+:$LD_PRELOAD}"
    exec "$@"
  '';

  blenderWithAddons = pkgs.symlinkJoin {
    name = "blender-with-addons";
    paths = [ pkgs.blender ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/blender \
        --set BLENDER_USER_SCRIPTS ${blenderScripts} \
        --set QUADREMESHER_LAUNCHER ${quadRemesherLauncher}
    '';
  };
in
{
  home.packages = [ blenderWithAddons ];
}
