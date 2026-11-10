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

  # Unlike the Mac Mini, a systemd service on NixOS starts with no /bin on
  # PATH, and npm spawns its install scripts through `sh`. bash supplies that
  # `sh`, and the rest is what the install scripts and the bun bootstrap need.
  servicePath = lib.makeBinPath [
    cfg.opencodePackage
    pkgs.nodejs
    pkgs.git
    pkgs.bash
    pkgs.coreutils
    pkgs.curl
    pkgs.unzip
  ];
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
        in the journal; open it once in a Discord-logged-in browser and
        authorize.
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
      example = "wsl";
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

    # A system service (not a user unit) so it starts at boot without a
    # logged-in session, matching the launchd daemon on the Mac Mini. npx
    # output, including the one-time install URL, is in the journal:
    # journalctl -u kimaki -f
    systemd.services.kimaki = {
      description = "Kimaki Discord bot for OpenCode 2";

      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [
        "network.target"
        "network-online.target"
      ];

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = config.users.users.${cfg.user}.group;
        WorkingDirectory = home;
        Restart = "always";
        RestartSec = 5;
        ExecStart = "${kimaki}/bin/kimaki ${lib.escapeShellArgs args}";

        Environment = [
          "HOME=${home}"
          "PATH=${servicePath}"
          "OPENCODE_PATH=${cfg.opencodePackage}/bin/opencode2"
        ];
      };
    };
  };
}