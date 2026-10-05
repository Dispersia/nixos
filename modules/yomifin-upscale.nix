{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.yomifin.upscale;
  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    optionalString
    ;

  home = config.users.users.${cfg.user}.home;
  stateDir = "${home}/Library/Application Support/YomiFin/upscale";
  venvDir = "${stateDir}/venv";
  modelsDir = "${stateDir}/models";
  extras = lib.concatStringsSep "," cfg.extras;

  service = pkgs.writeShellApplication {
    name = "yomifin-upscale";
    runtimeInputs = [
      pkgs.uv
      cfg.python
      pkgs.coreutils
    ];
    text = ''
      STATE_DIR=${lib.escapeShellArg stateDir}
      VENV_DIR=${lib.escapeShellArg venvDir}
      MODELS_DIR=${lib.escapeShellArg modelsDir}
      SOURCE=${lib.escapeShellArg "${cfg.source}"}
      SRC_DIR="$STATE_DIR/src"
      EXTRAS=${lib.escapeShellArg extras}
      STAMP="$STATE_DIR/.extras"
      STAMP_VALUE="$EXTRAS|$SOURCE"

      export UV_PYTHON_DOWNLOADS=never
      export UV_CACHE_DIR=${lib.escapeShellArg "${home}/Library/Caches/uv"}
      export YOMIFIN_UPSCALE_MODELS_DIR="$MODELS_DIR"

      mkdir -p "$STATE_DIR" "$MODELS_DIR"

      if [ ! -x "$VENV_DIR/bin/uvicorn" ] || [ "$(cat "$STAMP" 2>/dev/null || true)" != "$STAMP_VALUE" ]; then
        echo "yomifin-upscale: (re)building venv (extras: $EXTRAS)"
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
        YOMIFIN_UPSCALE_TOKEN="$(cat ${lib.escapeShellArg cfg.authTokenFile})"
        export YOMIFIN_UPSCALE_TOKEN
      ''}

      ${optionalString (cfg.ocrTokenFile != null) ''
        YOMIFIN_UPSCALE_OCR_TOKEN="$(cat ${lib.escapeShellArg cfg.ocrTokenFile})"
        export YOMIFIN_UPSCALE_OCR_TOKEN
      ''}

      exec "$VENV_DIR/bin/uvicorn" service.app:app \
        --app-dir "$SOURCE" \
        --host ${lib.escapeShellArg cfg.host} \
        --port ${toString cfg.port}
    '';
  };
in
{
  options.services.yomifin.upscale = {
    enable = mkEnableOption "the yomifin-upscale MangaJaNai sidecar (manga upscaling over HTTP)";

    user = mkOption {
      type = types.str;
      description = "User the sidecar runs as. Must own a writable home for the venv, models and uv cache.";
    };

    host = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Bind address. Keep the loopback default unless Jellyfin runs on another host.";
    };

    port = mkOption {
      type = types.port;
      default = 8643;
      description = "TCP port for the sidecar (matches the plugin's default UpscaleSidecarUrl).";
    };

    source = mkOption {
      type = types.path;
      default = ../pkgs/yomifin-upscale;
      description = ''
        Vendored yomifin-upscale service source (pyproject.toml, providers/, service/).
        Copied into the Nix store; no local repo checkout is required.
      '';
    };

    python = mkOption {
      type = types.package;
      default = pkgs.python313;
      description = ''
        Python interpreter for the venv. Pinned to 3.13 to match the OCR sidecar
        and because PyTorch wheels lag the newest nixpkgs Python.
      '';
    };

    extras = mkOption {
      type = types.listOf (types.enum [ "pytorch" ]);
      default = [ "pytorch" ];
      description = ''
        Optional dependency groups to install. "pytorch" pulls torch + spandrel +
        numpy, which the MangaJaNai/IllustrationJaNai models require. On Apple
        Silicon the PyPI torch wheel uses the Metal (MPS) backend.
      '';
    };

    autoDownloadModels = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Download missing MangaJaNai/IllustrationJaNai models on first use. When
        disabled, place the .pth files in the models directory yourself.
      '';
    };

    fp16 = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Run the models in half precision. Much faster on Apple Silicon
        (Metal/MPS); the sidecar automatically falls back to fp32 if an operator
        does not support half.
      '';
    };

    maxInputHeight = mkOption {
      type = types.ints.unsigned;
      default = 1600;
      description = ''
        Downscale pages taller than this to this height before upscaling
        (0 = off). 1600 matches MangaJaNaiConverterGui and substantially cuts
        the per-page work on MPS.
      '';
    };

    authTokenFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "/run/secrets/yomifin-upscale-token";
      description = ''
        Path (as a string) to a file containing a bearer token, exported as
        YOMIFIN_UPSCALE_TOKEN. Set this whenever `host` is not loopback. The
        sidecar performs arbitrary expensive compute on uploaded bytes and has no
        auth when the token is unset.

        Use a string, not a path literal: a `path` value is copied into the
        world-readable Nix store, which would leak the secret.
      '';
    };

    textRestore = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Re-run a text super-resolution model over OCR-detected lettering so
        speech bubbles stay crisp after upscaling. Detection uses the
        yomifin-ocr sidecar; the upscale host must be able to reach `ocrUrl`.
      '';
    };

    ocrUrl = mkOption {
      type = types.str;
      default = "http://127.0.0.1:8642";
      description = ''
        Base URL of the yomifin-ocr sidecar as seen from this host, used to
        detect text regions for lettering restoration.
      '';
    };

    ocrLanguage = mkOption {
      type = types.str;
      default = "ja";
      description = ''
        Default OCR language for text detection when the job does not specify
        one (e.g. ja, zh-Hans, en).
      '';
    };

    ocrTokenFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "/run/secrets/yomifin-ocr-token";
      description = ''
        Path (as a string) to a file containing the OCR sidecar bearer token,
        exported as YOMIFIN_UPSCALE_OCR_TOKEN. Required when the OCR sidecar
        enforces auth. Use a string, not a path literal.
      '';
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.uv
      pkgs.python3
    ];

    # launchd needs the working directory and log paths to exist before the job
    # starts. Create them (owned by the service user) on activation.
    system.activationScripts.yomifin-upscale = {
      text = ''
        /bin/mkdir -p ${lib.escapeShellArg stateDir} ${lib.escapeShellArg modelsDir}
        /usr/sbin/chown ${cfg.user} ${lib.escapeShellArg stateDir} ${lib.escapeShellArg modelsDir} 2>/dev/null || true
      '';
    };

    launchd.daemons.yomifin-upscale = {
      serviceConfig = {
        ProgramArguments = [ "${service}/bin/yomifin-upscale" ];
        UserName = cfg.user;
        KeepAlive = true;
        RunAtLoad = true;
        WorkingDirectory = stateDir;
        StandardOutPath = "${stateDir}/stdout.log";
        StandardErrorPath = "${stateDir}/stderr.log";
        EnvironmentVariables = {
          HOME = home;
          YOMIFIN_UPSCALE_MODELS_DIR = modelsDir;
          YOMIFIN_UPSCALE_AUTO_DOWNLOAD = if cfg.autoDownloadModels then "1" else "0";
          YOMIFIN_UPSCALE_FP16 = if cfg.fp16 then "1" else "0";
          YOMIFIN_UPSCALE_MAX_INPUT_HEIGHT = toString cfg.maxInputHeight;
          YOMIFIN_UPSCALE_MAX_OUTPUT_SIZE = "4096";
          YOMIFIN_UPSCALE_SHARPEN = "150";
          YOMIFIN_UPSCALE_TEXT_RESTORE = if cfg.textRestore then "1" else "0";
          YOMIFIN_UPSCALE_OCR_URL = cfg.ocrUrl;
          YOMIFIN_UPSCALE_OCR_LANGUAGE = cfg.ocrLanguage;
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
