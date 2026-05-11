{ pkgs, config, ... }:
let
  onigiriUserFiles = pkgs.runCommand "onigiri-user-files" { } ''
    mkdir -p $out/{custom_deck_icons,fonts,icons,images,main_bg,profile,profile_bg,reviewer_bg,reviewer_bar_bg,sidebar_bg,toolbar_bg,user_themes}
    cat > "$out/settings_User 1.json" << 'EOF'
    {
      "userName": "Dispersia",
      "showWelcomePopup": false,
      "lastSeenWelcomeVersion": "1.0.9.1-beta",
      "onigiri_reviewer_bg_light_color": "#f5ede5",
      "onigiri_reviewer_bg_dark_color": "#292523",
      "onigiri_overview_bg_light_color": "#f5ede5",
      "onigiri_overview_bg_dark_color": "#292523",
      "onigiri_reviewer_bottom_bar_bg_light_color": "#f5ede5",
      "onigiri_reviewer_bottom_bar_bg_dark_color": "#292523",
      "colors": {
        "light": {
          "--accent-color": "#5d6efc",
          "--bg": "#f5ede5",
          "--fg": "#292523",
          "--fg-subtle": "#6a6360",
          "--border": "#e0d4ca",
          "--canvas-inset": "#ebe0d6",
          "--heatmap-color": "#5d6efc",
          "--heatmap-color-zero": "#ebe0d6",
          "--icon-color": "#6a6360",
          "--icon-color-filtered": "#5d6efc",
          "--highlight-bg": "#ebe0d6",
          "--star-color": "#5d6efc",
          "--empty-star-color": "#6a6360"
        },
        "dark": {
          "--accent-color": "#5d6efc",
          "--bg": "#292523",
          "--fg": "#f5ede5",
          "--fg-subtle": "#9a938f",
          "--border": "#413b38",
          "--canvas-inset": "#3a3533",
          "--heatmap-color": "#5d6efc",
          "--heatmap-color-zero": "#3a3533",
          "--icon-color": "#9a938f",
          "--icon-color-filtered": "#5d6efc",
          "--highlight-bg": "#3a3533",
          "--star-color": "#5d6efc",
          "--empty-star-color": "#9a938f"
        }
      }
    }
    EOF
  '';

  onigiri = pkgs.anki-utils.buildAnkiAddon (finalAttrs: {
    pname = "onigiri";
    version = "unstable-2026-05-11";
    src = pkgs.fetchFromGitHub {
      owner = "thepeacemonk";
      repo = "Onigiri";
      rev = "5213df267596ed98e271a4b1159b7e8a3d575267";
      hash = "sha256-wuALbVEpSsfb7cX0lLW3IdY4NQZ5OOjzZ+4G18Az3mw=";
    };
    postPatch = ''
      substituteInPlace patcher.py \
        --replace-fail 'from aqt.utils import tr' 'from .translations import tr'

      cat >> __init__.py << 'PATCH'

def _nix_sync_bg_colors():
    try:
        conf = config.get_config()
        colors = conf.get("colors", {})
        lt = colors.get("light", {})
        dk = colors.get("dark", {})
        mw.col.conf["modern_menu_bg_color_light"] = lt.get("--bg", "#F5F5F5")
        mw.col.conf["modern_menu_bg_color_dark"] = dk.get("--bg", "#2C2C2C")
        mw.col.conf["modern_menu_sidebar_bg_color_light"] = lt.get("--canvas-inset", "#EEEEEE")
        mw.col.conf["modern_menu_sidebar_bg_color_dark"] = dk.get("--canvas-inset", "#3C3C3C")
        mw.col.setMod()
    except Exception:
        pass

gui_hooks.profile_did_open.append(_nix_sync_bg_colors)
PATCH
    '';
  });
in
{
  programs.anki = {
    enable = true;
    addons = [
      pkgs.ankiAddons.anki-connect

      (onigiri.withConfig {
        userFiles = onigiriUserFiles;
      })
    ];
  };
}
