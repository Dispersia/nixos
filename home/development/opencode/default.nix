{ pkgs, inputs, config, lib, ... }:
let
  # OpenDesign (`od` CLI + local daemon) is installed and supervised wherever
  # OpenCode is, except macOS: upstream retired its Nix packaging (Aug 2026)
  # and the daemon's better-sqlite3 native build needs Apple's cctools
  # `libtool`, which the retired derivation never wired up. Linux-only for now.
  openDesign = config.services.open-design;
  enableOpenDesign = pkgs.stdenv.hostPlatform.isLinux;
in
{
  imports = [ inputs.open-design.homeManagerModules.default ];

  # Daemon API on `port` (7457), static web UI on `webFrontend.port` (5174).
  services.open-design = lib.mkIf enableOpenDesign {
    enable = true;
    autoStart = true;
    webFrontend.enable = true;
  };

  home.packages = [
    inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.opencode2
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
