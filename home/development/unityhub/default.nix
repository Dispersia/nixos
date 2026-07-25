{ pkgs, ... }:
let
  unityhub =
    (pkgs.unityhub.override {
      extraPkgs = pkgs: with pkgs; [ ncurses ];
    }).overrideAttrs
      (old: {
        postInstall = (old.postInstall or "") + ''
          wrapProgram $out/opt/unityhub/unityhub \
            --set LD_LIBRARY_PATH /usr/lib64
        '';
      });
in
{
  home.packages = [ unityhub ];
}
