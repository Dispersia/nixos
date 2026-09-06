{ pkgs, inputs, ... }:
let
  stable = inputs.nixpkgs-stable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
in
{
  home.packages = [
    (pkgs.lmms.override { carla = stable.carla; })
    stable.carla
  ];
}
