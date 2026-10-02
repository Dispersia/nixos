{ config, lib, pkgs, ... }:

let
  cfg = config.services.yomifin.ocr;
  inherit (lib) mkIf mkEnableOption mkOption types optionalString;

  home = config.users.users.${cfg.user}.home;
  stateDir = "${home}/Library/Application Support/YomiFin/ocr";
  venvDir = "${stateDir}/venv";
  extras = lib.concatStringsSep "," cfg.engines;

  service = pkgs.writeShellApplication {
    name = "yomifin-ocr";
    runtimeInputs = [
      pkgs.uv
      cfg.python
      pkgs.coreutils
    ];
    text = ''
      STATE_DIR=${lib.escapeShellArg stateDir}
      VENV_DIR=${lib.escapeShellArg venvDir}
      SOURCE=${lib.escapeShellArg "${cfg.source}"}
      SRC_DIR="$STATE_DIR/src"
      EXTRAS=${lib.escapeShellArg extras}
      STAMP="$STATE_DIR/.extras"
      STAMP_VALUE="$EXTRAS|$SOURCE"

      export UV_PYTHON_DOWNLOADS=never
      export UV_CACHE_DIR=${lib.escapeShellArg "${home}/Library/Caches/uv"}

      mkdir -p "$STATE_DIR"

      if [ ! -x "$VENV_DIR/bin/uvicorn" ] || [ "$(cat "$STAMP" 2>/dev/null || true)" != "$STAMP_VALUE" ]; then
        echo "yomifin-ocr: (re)building venv (extras: $EXTRAS)"
        rm -rf "$VENV_DIR"
        # The source lives in the read-only Nix store, but setuptools writes
        # ``*.egg-info`` next to it while building the local package. Install
        # from a writable copy so that build step can succeed.
        rm -rf "$SRC_DIR"
        mkdir -p "$SRC_DIR"
        cp -R "$SOURCE"/. "$SRC_DIR"/
        chmod -R u+w "$SRC_DIR"
        uv venv --python ${lib.escapeShellArg "${cfg.python}/bin/python3"} "$VENV_DIR"
        if [ -n "$EXTRAS" ]; then
          uv pip install --python "$VENV_DIR/bin/python" "''${SRC_DIR}[$EXTRAS]"
        else
          uv pip install --python "$VENV_DIR/bin/python" "$SRC_DIR"
        fi
        printf '%s' "$STAMP_VALUE" > "$STAMP"
      fi

      ${optionalString (cfg.authTokenFile != null) ''
        export YOMIFIN_OCR_TOKEN="$(cat ${lib.escapeShellArg (toString cfg.authTokenFile)})"
      ''}

      exec "$VENV_DIR/bin/uvicorn" service.app:app \
        --app-dir "$SOURCE" \
        --host ${lib.escapeShellArg cfg.host} \
        --port ${toString cfg.port}
    '';
  };
in
{
  options.services.yomifin.ocr = {
    enable = mkEnableOption "the yomifin-ocr OCR sidecar (OCR models over HTTP)";

    user = mkOption {
      type = types.str;
      description = "User the sidecar runs as. Must own a writable home for the venv and uv cache.";
    };

    host = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Bind address. Keep the loopback default unless Jellyfin runs on another host.";
    };

    port = mkOption {
      type = types.port;
      default = 8642;
      description = "TCP port for the sidecar (matches the plugin's default OcrSidecarUrl).";
    };

    source = mkOption {
      type = types.path;
      default = ../pkgs/yomifin-ocr;
      description = ''
        Vendored yomifin-ocr service source (pyproject.toml, providers/, service/).
        Copied into the Nix store; no local repo checkout is required.
      '';
    };

    python = mkOption {
      type = types.package;
      default = pkgs.python313;
      description = ''
        Python interpreter for the venv. Pinned to 3.13 because the PaddlePaddle
        Apple Silicon wheels (and sometimes torch) lag the newest nixpkgs Python.
      '';
    };

    engines = mkOption {
      type = types.listOf (types.enum [ "yomitoku" "paddleocr" "mangaocr" ]);
      default = [ "yomitoku" ];
      description = ''
        OCR engine extras to install. YomiToku is the preferred Japanese engine;
        PaddleOCR is the multilingual default/fallback (PyPI ships arm64 wheels).
        manga-ocr is an optional compatibility engine.
      '';
    };

    authTokenFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "/run/secrets/yomifin-ocr-token";
      description = ''
        Path (as a string) to a file containing a bearer token, exported as
        YOMIFIN_OCR_TOKEN. Set this whenever `host` is not loopback. The sidecar
        performs arbitrary expensive compute on uploaded bytes and has no auth
        when the token is unset.

        Use a string, not a path literal: a `path` value is copied into the
        world-readable Nix store, which would leak the secret.
      '';
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.uv
      pkgs.python3
    ];

    launchd.daemons.yomifin-ocr = {
      serviceConfig = {
        ProgramArguments = [ "${service}/bin/yomifin-ocr" ];
        UserName = cfg.user;
        KeepAlive = true;
        RunAtLoad = true;
        WorkingDirectory = stateDir;
        StandardOutPath = "${stateDir}/stdout.log";
        StandardErrorPath = "${stateDir}/stderr.log";
        EnvironmentVariables = {
          HOME = home;
          PATH = lib.makeBinPath [
            pkgs.uv
            pkgs.python3
            pkgs.coreutils
          ];
        };
      };
    };
  };
}
