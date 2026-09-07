{ pkgs, inputs, ... }:
let
  stable = inputs.nixpkgs-stable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
in
{
  home.packages = [
    ((pkgs.lmms.override { carla = stable.carla; }).overrideAttrs (old: {
      nativeBuildInputs = old.nativeBuildInputs ++ [
        pkgs.fltk
        pkgs.perl
        pkgs.perlPackages.ListMoreUtils
        pkgs.perlPackages.XMLParser
      ];
    }))
    stable.carla
  ];
}
