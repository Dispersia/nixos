{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.comfyuiUv;

  inherit (lib)
    concatStringsSep
    escapeShellArg
    escapeShellArgs
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  home = config.users.users.${cfg.user}.home;

  # Pinned ComfyUI release (v0.42.1). Bump `rev` and `hash` together (hash:
  # `nix-prefetch-url --unpack`); the service re-syncs the app directory and
  # rebuilds the Python environment when `rev` changes.
  rev = "63be2f9b82ad0dac88a7ceaa28a9cf3154125a18";
  source = pkgs.fetchFromGitHub {
    owner = "Comfy-Org";
    repo = "ComfyUI";
    inherit rev;
    hash = "sha256-/thkdznvXdpT2rgsyZ1NoH5jG1ox+pAjJCrj4glurSI=";
  };

  setupStamp =
    "${rev}|${cfg.python}|${cfg.torchIndex}|"
    + "${concatStringsSep " " cfg.torchPackages}|${concatStringsSep " " cfg.extraPipPackages}";

  service = pkgs.writeShellApplication {
    name = "comfyui";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.rsync
      pkgs.uv
      cfg.python
    ];
    text = ''
      ROOT=${escapeShellArg cfg.dataDir}
      VENV="$ROOT/venv"

      mkdir -p "$ROOT/tmp"

      # Sync the pinned app source into the writable root. rsync merges, so
      # models/, output/, input/, user/ and custom_nodes/ survive updates; the
      # --chmod makes the otherwise read-only store copies writable.
      if [ "$(cat "$ROOT/.nix-source-rev" 2>/dev/null || true)" != ${escapeShellArg rev} ]; then
        echo "comfyui: syncing app files (${rev})"
        rsync -a --chmod=Du+w,Fu+w ${escapeShellArg "${source}/"} "$ROOT"/
        printf '%s\n' ${escapeShellArg rev} > "$ROOT/.nix-source-rev"
      fi

      # NixOS has no /usr/lib where the wheels expect to find their C++
      # runtime and the compression libraries the bundled ROCm libs (comgr,
      # hip, aotriton) link against; point the loader at nixpkgs' copies.
      export LD_LIBRARY_PATH=${
        escapeShellArg (
          lib.makeLibraryPath [
            pkgs.stdenv.cc.cc.lib
            pkgs.zstd
            pkgs.zlib
            pkgs.xz
            pkgs.bzip2
          ]
        )
      }''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}

      # (Re)build the venv when the pin or package lists change. The uv cache
      # keeps re-installs fast; the multi-GB torch wheels are cached too.
      export UV_PYTHON_DOWNLOADS=never
      export UV_CACHE_DIR=${escapeShellArg "${home}/.cache/uv"}

      if [ ! -x "$VENV/bin/python" ] || [ "$(cat "$ROOT/.nix-setup-stamp" 2>/dev/null || true)" != ${escapeShellArg setupStamp} ]; then
        echo "comfyui: (re)building Python environment"
        rm -rf "$VENV"
        uv venv --python ${escapeShellArg "${cfg.python}/bin/python3"} "$VENV"

        # torch comes from the configured index: on AMD that is PyTorch's ROCm
        # wheel index (PyPI's Linux torch wheels are CUDA builds). Indexes are
        # searched in order and the first index with a match wins, so the torch
        # index must stay first; anything it lacks (sympy, filelock, ...) falls
        # through to PyPI.
        uv pip install --python "$VENV/bin/python" \
          --index ${escapeShellArg cfg.torchIndex} \
          --index https://pypi.org/simple \
          ${escapeShellArgs cfg.torchPackages}

        # Everything else, exactly as upstream's installer would. requirements.txt
        # leaves torch unpinned, so the ROCm build installed above is kept.
        uv pip install --python "$VENV/bin/python" -r "$ROOT/requirements.txt" pip ${escapeShellArgs cfg.extraPipPackages}
        printf '%s\n' ${escapeShellArg setupStamp} > "$ROOT/.nix-setup-stamp"
      fi

      cd "$ROOT"
      exec "$VENV/bin/python" main.py \
        --port ${toString cfg.port} \
        --listen ${escapeShellArg cfg.listenAddress} \
        ${escapeShellArgs cfg.extraArgs}
    '';
  };
in
{
  # Distinct from nixpkgs' `services.comfyui`, which builds torch from source
  # (hours of local compilation with `nixpkgs.config.rocmSupport` on AMD).
  # This module pins an upstream release and uses prebuilt ROCm wheels via uv.
  options.services.comfyuiUv = {
    enable = mkEnableOption "ComfyUI (upstream release with a uv-built venv) as a systemd service";

    user = mkOption {
      type = types.str;
      description = "User ComfyUI runs as. Everything is installed under this user's home.";
    };

    dataDir = mkOption {
      type = types.str;
      default = "${home}/ComfyUI";
      description = ''
        Writable directory holding the app, venv, models, outputs and custom
        nodes. Put checkpoints in `models/checkpoints`, LoRAs in `models/loras`,
        and custom nodes in `custom_nodes`; all of it survives source updates.
        Never point this at a path inside the Nix store.
      '';
    };

    port = mkOption {
      type = types.port;
      default = 8188;
      description = "Port the server listens on.";
    };

    listenAddress = mkOption {
      type = types.str;
      default = "127.0.0.1";
      example = "100.64.0.1";
      description = ''
        Address to bind (`--listen`). Keep the default loopback when a reverse
        proxy runs on the same host; bind this host's tailnet address to let a
        gateway on another machine (e.g. `services.tailnetGateway` on the home
        server) reach the server over the tailnet.
      '';
    };

    python = mkOption {
      type = types.package;
      default = pkgs.python313;
      description = "Python interpreter for the venv.";
    };

    torchIndex = mkOption {
      type = types.str;
      default = "https://download.pytorch.org/whl/rocm7.2";
      example = "https://download.pytorch.org/whl/cu128";
      description = ''
        Index the torch packages are installed from. The default is PyTorch's
        ROCm wheel index for AMD GPUs; PyPI's Linux torch wheels are CUDA
        builds, so do not point this at PyPI. Indexes are searched in order
        (this one first), then PyPI is used for everything else.
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
        "torchvision==0.24.1+rocm7.2"
      ];
      description = "torch packages (optionally version-pinned) installed from `torchIndex` before the requirements.";
    };

    extraPipPackages = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "sageattention" ];
      description = "Additional PyPI packages installed alongside the requirements.";
    };

    extraArgs = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "--fast" ];
      description = "Extra commandline arguments for `main.py`.";
    };

    extraEnvironment = mkOption {
      type = types.attrsOf types.str;
      default = { };
      example = {
        HSA_OVERRIDE_GFX_VERSION = "10.3.0";
      };
      description = "Extra environment variables for the service (e.g. ROCm overrides).";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.isLinux;
        message = "services.comfyuiUv is implemented with systemd and only works on NixOS.";
      }
    ];

    systemd.services.comfyui = {
      description = "ComfyUI (diffusion model UI and backend)";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        User = cfg.user;
        WorkingDirectory = home;
        ExecStart = "${service}/bin/comfyui";
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
