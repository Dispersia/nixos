{
  pkgs,
  inputs,
  config,
  lib,
  ...
}:
let
  # OpenDesign (`od` CLI + local daemon) is installed and supervised wherever
  # OpenCode is. The daemon's better-sqlite3 native build needs Apple's
  # cctools `libtool` on PATH on macOS; the upstream derivation does not add
  # it, so append cctools to nativeBuildInputs there. The web frontend is a
  # static Next.js build and needs no toolchain fix.
  openDesign = config.services.open-design;
  openDesignPackage =
    inputs.open-design.packages.${pkgs.stdenv.hostPlatform.system}.daemon.overrideAttrs
      (
        old:
        lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
          nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.cctools ];
        }
      );
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
  services.open-design = {
    enable = true;
    autoStart = true;
    webFrontend.enable = true;
    package = openDesignPackage;
  };

  home.packages = [
    inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.opencode2
  ];

  # Default every OpenCode 2 session to DeepSeek V4.1 Flash through OpenRouter.
  # Authenticate the provider first with `opencode auth login openrouter`
  # (or `/login` inside a Kimaki channel).
  #
  # The `mcp.servers.open-design` entry is the stdio bridge that `od mcp
  # install opencode` would normally write into this file; declaring it here
  # keeps the wiring reproducible instead of depending on a manual install
  # step. OpenCode 2 nests server definitions under `mcp.servers` — a bare
  # `mcp.<name>` key is V1 syntax and OpenCode 2 ignores it silently.
  home.file.".config/opencode/opencode.json".text = builtins.toJSON {
    "$schema" = "https://opencode.ai/config.json";
    model = "openrouter/deepseek/deepseek-v4.1-flash";

    mcp.servers.open-design = {
      type = "local";
      command = [
        (lib.getExe openDesign.package)
        "mcp"
        "--daemon-url"
        "http://127.0.0.1:${toString openDesign.port}"
      ];
      environment.OD_DATA_DIR = "${config.home.homeDirectory}/.od";
    };
  };
}
