{ pkgs, config, lib, ... }:
let
  kicadVersion = "10.0";

  arcana = pkgs.fetchFromGitHub {
    owner = "lethalbit";
    repo = "arcana-kicad";
    rev = "2024.02.25";
    hash = "sha256-ARjMrFrlZ79msuMX821SBJutuGqZY36z6Qo/yRI90gU=";
  };
in
{
  home.packages = with pkgs; [ kicad ];

  xdg.configFile."kicad/${kicadVersion}/colors/Arcana.json".source =
    "${arcana}/colors/Arcana.json";

  home.activation.kicadArcanaDefault =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      cfg="${config.xdg.configHome}/kicad/${kicadVersion}"
      run mkdir -p "$cfg"
      for app in eeschema pcbnew; do
        f="$cfg/$app.json"
        if [ -f "$f" ]; then
          ${pkgs.jq}/bin/jq \
            '.appearance.color_theme = "Arcana" | .color_theme = "Arcana"' \
            "$f" > "$f.tmp" && run mv "$f.tmp" "$f"
        else
          echo '{"appearance":{"color_theme":"Arcana"},"color_theme":"Arcana"}' > "$f"
        fi
      done
    '';
}
