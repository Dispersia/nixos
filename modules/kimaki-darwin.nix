{
  config,
  lib,
  inputs,
  pkgs,
  ...
}:

let
  cfg = config.services.kimaki;
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    optional
    types
    ;

  home = config.users.users.${cfg.user}.home;

  # Kimaki ships on npm only, so run the published CLI through npx. It needs
  # Node 20+ and git on PATH; both are pinned into the wrapper below.
  kimaki = pkgs.writeShellApplication {
    name = "kimaki";
    runtimeInputs = [
      pkgs.nodejs
      pkgs.git
    ];
    text = ''
      exec ${pkgs.nodejs}/bin/npx --yes ${lib.escapeShellArg "kimaki@${cfg.version}"} "$@"
    '';
  };

  args =
    optional cfg.gateway "--gateway"
    ++ optional (cfg.machineName != "") "--machine-name"
    ++ optional (cfg.machineName != "") cfg.machineName;
in
{
  options.services.kimaki = {
    enable = mkEnableOption "the Kimaki Discord bot (an OpenCode 2 orchestrator)";

    user = mkOption {
      type = types.str;
      description = ''
        User the bot runs as. It needs that user's home for the OpenCode
        background service, ~/.kimaki and the logs.
      '';
    };

    gateway = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Use gateway mode: Kimaki's shared Discord bot, so there is no Discord
        application to create by hand. The first start prints an install URL
        in the log; open it once in a Discord-logged-in browser and authorize.
      '';
    };

    version = mkOption {
      type = types.str;
      default = "latest";
      example = "1.3.0";
      description = ''
        Kimaki version to run with npx. `latest` checks npm on every start;
        pin a version to freeze updates.
      '';
    };

    machineName = mkOption {
      type = types.str;
      default = "";
      example = "Aarons-Mac-Mini";
      description = ''
        Name shown in this machine's Discord category, `Kimaki <name>`.
        Defaults to the hostname when empty.
      '';
    };

    opencodePackage = mkOption {
      type = types.package;
      default = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.opencode2;
      defaultText = lib.literalExpression "inputs.llm-agents.packages.\${pkgs.stdenv.hostPlatform.system}.opencode2";
      description = ''
        OpenCode 2 package Kimaki drives. Its binary is exported to Kimaki as
        OPENCODE_PATH so Kimaki never falls back to an OpenCode 1 install.
      '';
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ kimaki ];

    launchd.user.agents.kimaki = {
      command = "${kimaki}/bin/kimaki ${lib.escapeShellArgs args}";

      # Kimaki looks for the OpenCode binary on PATH (and at OPENCODE_PATH);
      # the opencode2 package's binary is namespaced to opencode2.
      path = [
        cfg.opencodePackage
        pkgs.nodejs
        pkgs.git
      ];

      environment = {
        HOME = home;
        OPENCODE_PATH = "${cfg.opencodePackage}/bin/opencode2";
      };

      serviceConfig = {
        Label = "dev.kimaki.bot";
        RunAtLoad = true;
        KeepAlive = true;
        WorkingDirectory = home;
        # Kimaki keeps its own log at ~/.kimaki/kimaki.log; these capture the
        # npx/onboarding output (including the one-time install URL).
        StandardOutPath = "${home}/Library/Logs/kimaki.log";
        StandardErrorPath = "${home}/Library/Logs/kimaki.err.log";
      };
    };
  };
}
