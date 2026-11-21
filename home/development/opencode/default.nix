{ pkgs, inputs, config, lib, ... }:
let
  # OpenDesign (`od` CLI + local daemon) is installed and supervised wherever
  # OpenCode is, except macOS: upstream retired its Nix packaging (Aug 2026)
  # and the daemon's better-sqlite3 native build needs Apple's cctools
  # `libtool`, which the retired derivation never wired up. Linux-only for now.
  openDesign = config.services.open-design;
  enableOpenDesign = pkgs.stdenv.hostPlatform.isLinux;

  opencode2 = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.opencode2;

  # OpenDesign agent wiring for OpenCode 2.
  #
  # The pinned OpenDesign (db9ebb7: the last commit that still ships Nix
  # packaging) only carries an adapter for the OpenCode *v1* CLI — `bin`
  # `opencode-cli`/`opencode`, `run --dir <cwd>`,
  # `--dangerously-skip-permissions`, `models --verbose`. This machine runs
  # v2, whose binary is `opencode2`, so the daemon reports "OpenCode 2" as not
  # installed and any run dies with `unknown agent: opencode2` (the web UI's
  # saved selection) or, for the v1 adapter, an unknown `--dir` flag.
  #
  # v2 kept the `run --format json` event stream, so a small argv shim bridges
  # the gap:
  #
  #   * `--dir <cwd>` → run from that directory (v2 resolves the project from
  #     cwd and rejects the flag)
  #   * `--dangerously-skip-permissions` → v2's `--auto`
  #   * `models --verbose` → v2 rejects `--verbose`; plain `models` still
  #     prints one `provider/model` per line, which the daemon parses
  #   * `--archived` keeps OpenDesign's runs out of the user's own OpenCode
  #     session list (they stay resumable via `-s <id>`)
  #
  # The shim is published as `opencode2-od` — a name nothing else uses, so the
  # real `opencode2` stays exactly what the user runs — and `agents.local.json`
  # (OpenDesign's own local-agent-profile extension point) declares an
  # `opencode2` agent that inherits the `opencode` adapter and points `bin` at
  # it. Agent ids must be new, and the inherited adapter is close enough once
  # the argv is translated.
  opencode2ForOpenDesign = pkgs.writeShellScriptBin "opencode2-od" ''
    set -euo pipefail
    real=${lib.getExe opencode2}

    subcommand=''${1-}
    shift || true

    case "$subcommand" in
      run)
        dir=""
        args=()
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --dir)
              dir=''${2-}
              shift
              if [ "$#" -gt 0 ]; then shift; fi
              ;;
            --dir=*) dir=''${1#--dir=}; shift ;;
            --dangerously-skip-permissions) shift ;;
            --variant)
              shift
              if [ "$#" -gt 0 ]; then shift; fi
              ;;
            --variant=*) shift ;;
            *)
              args+=("$1")
              shift
              ;;
          esac
        done
        if [ -n "$dir" ]; then cd "$dir"; fi
        exec "$real" run --auto --archived "''${args[@]}"
        ;;
      models)
        args=()
        for arg in "$@"; do
          if [ "$arg" != "--verbose" ]; then args+=("$arg"); fi
        done
        exec "$real" models "''${args[@]}"
        ;;
      *)
        exec "$real" "$subcommand" "$@"
        ;;
    esac
  '';
in
{
  # Vendored (and de-deprecated) copy of the module upstream retired in
  # nexu-io/open-design#7644; see open-design/home-manager.nix.
  imports = [
    (import ./open-design/home-manager.nix {
      moduleCommon = import ./open-design/module-common.nix;
      flake = inputs.open-design;
    })
  ];

  # Daemon API on `port` (7457), static web UI on `webFrontend.port` (5174).
  services.open-design = lib.mkIf enableOpenDesign {
    enable = true;
    autoStart = true;
    webFrontend.enable = true;
    # Resolve the `opencode2-od` shim by name (local agent profiles only carry a
    # binary *name*, resolved against the daemon's PATH).
    extraBinPaths = [ "${opencode2ForOpenDesign}/bin" ];
  };

  # OpenDesign's local agent profiles: declare "OpenCode 2" on top of the
  # shipped `opencode` adapter, backed by the argv shim above.
  home.file.".open-design/agents.local.json".text = builtins.toJSON {
    agents = [
      {
        id = "opencode2";
        name = "OpenCode 2";
        baseAgent = "opencode";
        bin = "opencode2-od";
      }
    ];
  };

  home.packages = [
    opencode2
  ];

  # Default every OpenCode 2 session to DeepSeek V4.1 Flash through OpenRouter.
  # Authenticate the provider first with `opencode auth login openrouter`
  # (or `/login` inside a Kimaki channel).
  #
  # The `mcp.open-design` server is the stdio bridge that `od mcp install
  # opencode` would normally write into this file; declaring it here keeps the
  # wiring reproducible instead of depending on a manual install step.
  home.file.".config/opencode/opencode.json".text = builtins.toJSON (
    {
      "$schema" = "https://opencode.ai/config.json";
      model = "openrouter/deepseek/deepseek-v4.1-flash";
    }
    // lib.optionalAttrs enableOpenDesign {
      mcp.open-design = {
        type = "local";
        command = [
          (lib.getExe openDesign.package)
          "mcp"
          "--daemon-url"
          "http://127.0.0.1:${toString openDesign.port}"
        ];
        enabled = true;
        environment.OD_DATA_DIR = "${config.home.homeDirectory}/.od";
      };
    }
  );
}
