{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.forge-neo;

  inherit (lib)
    escapeShellArg
    escapeShellArgs
    mkEnableOption
    mkIf
    mkOption
    optionalString
    types
    ;

  home = config.users.users.${cfg.user}.home;

  # Pinned Forge Neo (`neo` branch of sd-webui-forge-classic). Bump `rev` and
  # `hash` together (hash: `nix-prefetch-url --unpack`); the service re-syncs
  # the app directory and rebuilds the Python environment when `rev` changes.
  rev = "d880e8b8c8852d808a90399a973be1783a939424";

  # Local patches on top of `rev`; the MPS attention fixes walk attention in
  # query blocks so 1024x1024 generations fit under the watermark cap instead
  # of materialising an ~8 GiB matrix in one allocation. Bump `patchTag` when
  # the patch set changes so the service re-syncs its writable copy; a patch
  # that stops applying after a rev bump fails the build loudly.
  patchTag = "mps-attention.1";
  source = pkgs.applyPatches {
    src = pkgs.fetchFromGitHub {
      owner = "Haoming02";
      repo = "sd-webui-forge-classic";
      inherit rev;
      hash = "sha256-tTMTGjJX0PBGbXLxRWeiuMM4GyH8N6V75EKCxMkByuE=";
    };
    patches = [
      ./forge-neo-mps-attention.patch
    ];
  };
  syncTag = "${rev}+${patchTag}";

  # Pre-installed with uv; PyPI wheels include MPS support on Apple Silicon.
  # Everything else (the pinned gradio, extension requirements) is left to
  # launch.py so upstream stays the source of truth for those versions.
  pipPackages = [
    "pip"
    "torch"
    "torchvision"
  ]
  ++ cfg.extraPipPackages;

  setupStamp = "${rev}|${cfg.python}|${lib.concatStringsSep " " pipPackages}";

  service = pkgs.writeShellApplication {
    name = "forge-neo";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.git
      pkgs.rsync
      pkgs.uv
      cfg.python
    ];
    text = ''
      ROOT=${escapeShellArg cfg.dataDir}
      VENV="$ROOT/venv"

      mkdir -p "$ROOT/tmp"

      # Sync the pinned app source into the writable root. rsync merges, so
      # models/, outputs/, saved configs and extensions survive updates; the
      # --chmod makes the otherwise read-only store copies writable.
      if [ "$(cat "$ROOT/.nix-source-rev" 2>/dev/null || true)" != ${escapeShellArg syncTag} ]; then
        echo "forge-neo: syncing app files (${syncTag})"
        rsync -a --chmod=Du+w,Fu+w ${escapeShellArg "${source}/"} "$ROOT"/
        printf '%s\n' ${escapeShellArg syncTag} > "$ROOT/.nix-source-rev"
      fi

      # (Re)build the venv when the pin, interpreter or package list changes.
      # The uv cache keeps re-installs fast; torch wheels are cached too.
      export UV_PYTHON_DOWNLOADS=never
      export UV_CACHE_DIR=${escapeShellArg "${home}/Library/Caches/uv"}

      if [ ! -x "$VENV/bin/python" ] || [ "$(cat "$ROOT/.nix-setup-stamp" 2>/dev/null || true)" != ${escapeShellArg setupStamp} ]; then
        echo "forge-neo: (re)building Python environment"
        rm -rf "$VENV"
        uv venv --python ${escapeShellArg "${cfg.python}/bin/python3"} "$VENV"
        uv pip install --python "$VENV/bin/python" -r "$ROOT/requirements.txt" ${escapeShellArgs pipPackages}
        printf '%s\n' ${escapeShellArg setupStamp} > "$ROOT/.nix-setup-stamp"
      fi

      # Fallback for launch.py's own torch installer (only runs when it thinks
      # torch/torchvision are missing).
      export TORCH_COMMAND="pip install torch torchvision"
      export PYTORCH_ENABLE_MPS_FALLBACK=1

      cd "$ROOT"
      args=(
        --port ${toString cfg.port}
        --subpath ${escapeShellArg cfg.subpath}
      )
      ${optionalString cfg.listen "args+=(--listen)"}
      args+=(${escapeShellArgs cfg.extraArgs})
      exec "$VENV/bin/python" launch.py "''${args[@]}"
    '';
  };
in
{
  options.services.forge-neo = {
    enable = mkEnableOption "Forge Neo (Stable Diffusion WebUI Forge) as a launchd daemon";

    user = mkOption {
      type = types.str;
      description = "User the WebUI runs as. Everything is installed under this user's home.";
    };

    dataDir = mkOption {
      type = types.str;
      default = "${home}/ForgeNeo";
      description = ''
        Writable directory holding the app, venv, models, outputs and
        extensions. Put checkpoints in `models/Stable-diffusion`, LoRAs in
        `models/Lora`, and custom extensions in `extensions`; all of it
        survives source updates. Never point this at a path inside the Nix
        store.
      '';
    };

    port = mkOption {
      type = types.port;
      default = 7860;
      description = "Port the WebUI listens on (loopback unless `listen` is set).";
    };

    subpath = mkOption {
      type = types.str;
      default = "forge";
      description = ''
        URL prefix the UI is served under, without a leading slash; must match
        the `services.tailnetGateway` route name, e.g.
        `https://<hostname>/forge/`.
      '';
    };

    listen = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Bind all interfaces (`--listen`) instead of loopback. Keep this off so
        the WebUI is only reachable through the tailnet gateway.
      '';
    };

    python = mkOption {
      type = types.package;
      default = pkgs.python313;
      description = "Python interpreter for the venv (Forge Neo requires 3.13+).";
    };

    extraPipPackages = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "torch==2.13.0" ];
      description = "Additional packages (or version pins) for the venv, installed before the first start.";
    };

    extraArgs = mkOption {
      type = types.listOf types.str;
      default = [ "--skip-torch-cuda-test" ];
      example = [
        "--api"
        "--gradio-auth"
        "user:pass"
      ];
      description = "Extra commandline arguments for `launch.py`.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.isDarwin;
        message = "services.forge-neo is implemented with launchd and only works on nix-darwin.";
      }
    ];

    launchd.daemons.forge-neo = {
      serviceConfig = {
        Label = "dev.forge-neo.webui";
        ProgramArguments = [ "${service}/bin/forge-neo" ];
        UserName = cfg.user;
        KeepAlive = true;
        RunAtLoad = true;
        WorkingDirectory = home;
        StandardOutPath = "${home}/Library/Logs/forge-neo.log";
        StandardErrorPath = "${home}/Library/Logs/forge-neo.err.log";
        EnvironmentVariables = {
          HOME = home;
          GIT_SSL_CAINFO = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
          SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
          # PyTorch's MPS allocator defaults assume a dedicated GPU: it may grow
          # its pool to 1.7x torch.mps.recommended_max_memory() (≈20 GB on the
          # 16 GB mini) and never returns cached blocks to macOS (low watermark
          # ratio 0.0). Under load that starves the other services (YomiFin's
          # OCR sidecar) and can wedge Metal in an uninterruptible wait, leaving
          # generations stuck at "In queue". Cap the ceiling near 6 GB and hand
          # idle memory back; a genuine overflow then surfaces as a normal
          # "MPS backend out of memory" error instead of freezing the machine.
          PYTORCH_MPS_HIGH_WATERMARK_RATIO = "0.5";
          PYTORCH_MPS_LOW_WATERMARK_RATIO = "0.4";
        };
      };
    };
  };
}
