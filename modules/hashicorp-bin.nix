{
  config,
  lib,
  pkgs,
  ...
}:

let
  mkHashicorpBin =
    final:
    {
      pname,
      version,
      sha256,
      dynamic ? false,
    }:
    final.stdenv.mkDerivation {
      inherit pname version;

      src = final.fetchurl {
        url = "https://releases.hashicorp.com/${pname}/${version}/${pname}_${version}_linux_amd64.zip";
        inherit sha256;
      };

      nativeBuildInputs = [
        final.unzip
      ]
      ++ lib.optionals dynamic [
        final.autoPatchelfHook
      ];

      buildInputs = lib.optionals dynamic [
        final.stdenv.cc.cc.lib
      ];

      sourceRoot = ".";

      installPhase = ''
        install -Dm755 ${pname} $out/bin/${pname}
      '';

      meta = {
        license = lib.licenses.bsl11;
        mainProgram = pname;
        platforms = [ "x86_64-linux" ];
      };
    };
in
{
  nixpkgs.overlays = [
    (final: prev: {
      consul = mkHashicorpBin final {
        pname = "consul";
        version = "2.0.3";
        sha256 = "3020eea3fdfd939eb021ecaca105a1513af52b22e76f2ee97ea85acc6ff2f832";
      };

      nomad = mkHashicorpBin final {
        pname = "nomad";
        version = "2.0.5";
        sha256 = "6425e43967bb0b2b4979b0d06da9b06772848b658dae372f1256d51ddcfe53c3";
        dynamic = true;
      };
    })
  ];
}
