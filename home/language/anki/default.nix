{ pkgs, config, ... }:
let
  # Anki's prefs21.db is generated in the read-only Nix store, so the AnkiWeb
  # login can never be persisted by Anki itself. Instead, these files hold the
  # sync credentials and are applied on every profile open via
  # `programs.anki.profiles.<name>.sync`.
  secretsDir = "${config.home.homeDirectory}/.secrets";
  ankiSyncKeyFile = "${secretsDir}/anki-sync-key";
  ankiSyncUserFile = "${secretsDir}/anki-sync-username";

  onigiriSettings = userName: ''
    {
      "userName": "${userName}",
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
  '';

  onigiriUserFiles = pkgs.runCommand "onigiri-user-files" { } ''
    mkdir -p $out/{custom_deck_icons,fonts,icons,images,main_bg,profile,profile_bg,reviewer_bg,reviewer_bar_bg,sidebar_bg,toolbar_bg,user_themes}
    cat > "$out/settings_User 1.json" << 'EOF'
    ${onigiriSettings "Dispersia"}
    EOF
  '';

  onigiri = pkgs.anki-utils.buildAnkiAddon (finalAttrs: {
    pname = "onigiri";
    version = "unstable-2026-05-11";
    src = pkgs.fetchFromGitHub {
      owner = "thepeacemonk";
      repo = "Onigiri";
      rev = "9eeba041516eb489e25c1cceca27de3e7c7b8328";
      hash = "sha256-AI5olMxp6MrU0JEjr1QHcxLst9GsUc8jbyYwEikuBks=";
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

  # Whenever you log in to AnkiWeb interactively, write the credentials to the
  # files referenced by `profiles."User 1".sync`, so that from then on every
  # profile open (which reads those files) restores the login. Anki itself
  # can't persist this: the module keeps prefs21.db read-only in the store and
  # disables its settings saving.
  syncKeyCapture = pkgs.anki-utils.buildAnkiAddon {
    pname = "anki-sync-key-capture";
    version = "1.0";
    src = pkgs.writeTextDir "__init__.py" ''
      import os
      from pathlib import Path

      from aqt.profiles import ProfileManager

      PROFILE = "User 1"
      USER_FILE = Path("${ankiSyncUserFile}")
      KEY_FILE = Path("${ankiSyncKeyFile}")

      def _write(path, value):
          try:
              path.parent.mkdir(parents=True, exist_ok=True)
              path.write_text(value.strip() + "\n")
              os.chmod(path, 0o600)
          except OSError:
              pass

      def _capture(pm):
          if pm.name != PROFILE:
              return
          key = pm.profile.get("syncKey")
          if not key:
              return
          user = pm.profile.get("syncUser") or pm.meta.get("syncUser")
          _write(KEY_FILE, key)
          if user:
              _write(USER_FILE, str(user))

      _original_set_sync_key = ProfileManager.set_sync_key
      _original_set_sync_username = ProfileManager.set_sync_username

      def set_sync_key(self, val):
          _original_set_sync_key(self, val)
          try:
              _capture(self)
          except Exception:
              pass

      def set_sync_username(self, val):
          _original_set_sync_username(self, val)
          try:
              _capture(self)
          except Exception:
              pass

      ProfileManager.set_sync_key = set_sync_key
      ProfileManager.set_sync_username = set_sync_username
    '';
  };
in
{
  programs.anki = {
    enable = true;
    package = if pkgs.stdenv.hostPlatform.isDarwin then pkgs.anki-bin else pkgs.anki;
    addons = [
      (pkgs.ankiAddons.anki-connect.withConfig {
        config = {
          webCorsOriginList = [ "*" ];
        };
      })
      pkgs.ankiAddons.passfail2

      (onigiri.withConfig {
        userFiles = onigiriUserFiles;
      })

      syncKeyCapture
    ];

    profiles = {
      "User 1" = {
        default = true;
        sync = {
          usernameFile = ankiSyncUserFile;
          keyFile = ankiSyncKeyFile;
        };
      };
    };
  };
}
