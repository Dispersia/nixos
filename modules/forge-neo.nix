{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.forge-neo;

  inherit (lib)
    concatStringsSep
    escapeShellArg
    escapeShellArgs
    makeLibraryPath
    mkEnableOption
    mkIf
    mkOption
    optionalString
    types
    ;

  home = config.users.users.${cfg.user}.home;

  # Pinned Forge Neo (`neo` branch of sd-webui-forge-classic), same revision as
  # the macOS module. Bump `rev` and `hash` together (hash:
  # `nix-prefetch-url --unpack`); the service re-syncs the app directory and
  # rebuilds the Python environment when `rev` changes.
  rev = "d880e8b8c8852d808a90399a973be1783a939424";
  source = pkgs.fetchFromGitHub {
    owner = "Haoming02";
    repo = "sd-webui-forge-classic";
    inherit rev;
    hash = "sha256-tTMTGjJX0PBGbXLxRWeiuMM4GyH8N6V75EKCxMkByuE=";
  };

  setupStamp =
    "${rev}|${cfg.python}|${cfg.torchIndex}|"
    + "${concatStringsSep " " cfg.torchPackages}|${concatStringsSep " " cfg.extraPipPackages}";

  # Optional: reuse another installation's model folders (ComfyUI's layout) by
  # symlinking Forge's directories at them. Existing files are merged into the
  # shared folder first and placeholders are dropped; nothing is clobbered.
  shareBlock = optionalString (cfg.sharedModelsDir != null) ''
    share_dir() {
      local src="$1" dst="$2"
      mkdir -p "$src"
      if [ -L "$dst" ]; then return 0; fi
      if [ -d "$dst" ]; then
        find "$dst" -mindepth 1 -maxdepth 1 -name 'put_*_here' -delete
        find "$dst" -mindepth 1 -maxdepth 1 -exec mv -n -t "$src" {} +
        rmdir "$dst" 2>/dev/null || {
          echo "forge-neo: $dst still has files after merging, leaving it as a real directory"
          return 0
        }
      fi
      ln -s "$src" "$dst"
    }

    SHARE=${escapeShellArg cfg.sharedModelsDir}
    share_dir "$SHARE/checkpoints" "$ROOT/models/Stable-diffusion"
    share_dir "$SHARE/loras" "$ROOT/models/Lora"
    share_dir "$SHARE/embeddings" "$ROOT/models/embeddings"
    share_dir "$SHARE/vae" "$ROOT/models/VAE"
    share_dir "$SHARE/upscale_models" "$ROOT/models/ESRGAN"
  '';

  service = pkgs.writeShellApplication {
    name = "forge-neo";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
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
      # -K keeps the shared-model symlinks (see `sharedModelsDir` below) in
      # place instead of replacing them with real directories.
      if [ "$(cat "$ROOT/.nix-source-rev" 2>/dev/null || true)" != ${escapeShellArg rev} ]; then
        echo "forge-neo: syncing app files (${rev})"
        rsync -a -K --chmod=Du+w,Fu+w ${escapeShellArg "${source}/"} "$ROOT"/
        printf '%s\n' ${escapeShellArg rev} > "$ROOT/.nix-source-rev"
      fi

      ${shareBlock}

      # NixOS has no /usr/lib where the wheels expect to find their C++
      # runtime, the compression libraries the bundled ROCm libs link
      # against, and the X/GL stack OpenCV wants; point the loader at
      # nixpkgs' copies.
      export LD_LIBRARY_PATH=${
        escapeShellArg (makeLibraryPath [
          pkgs.stdenv.cc.cc.lib
          pkgs.zstd
          pkgs.zlib
          pkgs.xz
          pkgs.bzip2
          pkgs.glib
          pkgs.libglvnd
          pkgs.libxcb
        ])
      }''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}

      # (Re)build the venv when the pin or package lists change. The uv cache
      # keeps re-installs fast; the multi-GB torch wheels are cached too.
      export UV_PYTHON_DOWNLOADS=never
      export UV_CACHE_DIR=${escapeShellArg "${home}/.cache/uv"}

      if [ ! -x "$VENV/bin/python" ] || [ "$(cat "$ROOT/.nix-setup-stamp" 2>/dev/null || true)" != ${escapeShellArg setupStamp} ]; then
        echo "forge-neo: (re)building Python environment"
        rm -rf "$VENV"
        uv venv --python ${escapeShellArg "${cfg.python}/bin/python3"} "$VENV"

        # torch comes from the configured index (PyTorch's ROCm wheel index by
        # default); everything else falls through to PyPI.
        uv pip install --python "$VENV/bin/python" \
          --index ${escapeShellArg cfg.torchIndex} \
          --index https://pypi.org/simple \
          ${escapeShellArgs cfg.torchPackages}

        # Everything else, exactly as upstream's installer would.
        uv pip install --python "$VENV/bin/python" -r "$ROOT/requirements.txt" pip ${escapeShellArgs cfg.extraPipPackages}
        printf '%s\n' ${escapeShellArg setupStamp} > "$ROOT/.nix-setup-stamp"
      fi

      # Fallback for launch.py's own torch installer (only runs when it thinks
      # torch/torchvision are missing).
      export TORCH_COMMAND="pip install --index-url ${cfg.torchIndex} torch torchvision"

      cd "$ROOT"
      args=(
        --port ${toString cfg.port}
      )
      ${optionalString cfg.listen "args+=(--listen)"}
      ${optionalString (cfg.subpath != null) ''
        args+=(--subpath ${escapeShellArg cfg.subpath})
      ''}
      args+=(${escapeShellArgs cfg.extraArgs})
      exec "$VENV/bin/python" launch.py "''${args[@]}"
    '';
  };
in
{
  options.services.forge-neo = {
    enable = mkEnableOption "Forge Neo (Stable Diffusion WebUI Forge) as a systemd service";

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

    listen = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Bind all interfaces (`--listen`) instead of loopback. On a host whose
        firewall only trusts the tailnet interface, this keeps the WebUI
        reachable over the tailnet and from localhost while the LAN stays
        blocked.
      '';
    };

    subpath = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "forge";
      description = ''
        Optional URL prefix the UI is served under (`--subpath`), without a
        leading slash. Must match the `services.tailnetGateway` route name,
        e.g. `https://<hostname>/forge/`. Left unset, the UI is served at the
        root.
      '';
    };

    python = mkOption {
      type = types.package;
      default = pkgs.python313;
      description = "Python interpreter for the venv (Forge Neo requires 3.13+).";
    };

    torchIndex = mkOption {
      type = types.str;
      default = "https://download.pytorch.org/whl/rocm7.2";
      example = "https://download.pytorch.org/whl/cu128";
      description = ''
        Index the torch packages are installed from. The default is PyTorch's
        ROCm wheel index for AMD GPUs; PyPI's Linux torch wheels are CUDA
        builds, so do not point this at PyPI.
      '';
    };

    torchPackages = mkOption {
      type = types.listOf types.str;
      default = [
        "torch"
        "torchvision"
      ];
      example = [
        "torch==2.14.1+rocm7.2"
        "torchvision==0.29.1+rocm7.2"
      ];
      description = "torch packages (optionally version-pinned) installed from `torchIndex` before the requirements.";
    };

    extraPipPackages = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "onnxruntime" ];
      description = "Additional PyPI packages installed alongside the requirements.";
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

    extraEnvironment = mkOption {
      type = types.attrsOf types.str;
      default = { };
      example = {
        HSA_OVERRIDE_GFX_VERSION = "10.3.0";
      };
      description = "Extra environment variables for the service (e.g. ROCm overrides).";
    };

    sharedModelsDir = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "${home}/ComfyUI/models";
      description = ''
        Optional model directory of another installation (e.g. ComfyUI's
        `models` folder) to reuse: `checkpoints`, `loras`, `embeddings`, `vae`
        and `upscale_models` are symlinked into Forge's model folders so both
        UIs see the same files. Existing files on either side are merged, never
        overwritten.
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.isLinux;
        message = "services.forge-neo is implemented with systemd and only works on NixOS.";
      }
    ];

    systemd.services.forge-neo = {
      description = "Forge Neo (Stable Diffusion WebUI Forge)";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        User = cfg.user;
        WorkingDirectory = home;
        ExecStart = "${service}/bin/forge-neo";
        Restart = "always";
        RestartSec = 5;
      };
      environment = {
        HOME = home;
      }
      // cfg.extraEnvironment;
    };
  };
}
