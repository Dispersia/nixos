{ pkgs, inputs, ... }:
let
  stable = inputs.nixpkgs-stable.legacyPackages.${pkgs.stdenv.hostPlatform.system};

  # PipeWire's JACK emulation used to be wired in globally through the deprecated
  # `services.pipewire.jack.enable`, which set a session-wide LD_LIBRARY_PATH.
  # Wrap the JACK-capable apps instead so they still resolve libjack from
  # `pipewire.jack` without the global impurity.
  withJack = pkg:
    pkgs.symlinkJoin {
      name = "${pkg.name}-pwjack";
      paths = [ pkg ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        for f in $out/bin/*; do
          if [ -f "$f" ] && [ -x "$f" ]; then
            wrapProgram "$f" --prefix LD_LIBRARY_PATH : ${pkgs.pipewire.jack}/lib
          fi
        done
      '';
    };
in
{
  home.packages = [
    (withJack ((pkgs.lmms.override { carla = stable.carla; }).overrideAttrs (old: {
      nativeBuildInputs = old.nativeBuildInputs ++ [
        pkgs.fltk
        pkgs.perl
        pkgs.perlPackages.ListMoreUtils
        pkgs.perlPackages.XMLParser
      ];
    })))
    (withJack stable.carla)
    pkgs.soundfont-fluid
  ];
}
