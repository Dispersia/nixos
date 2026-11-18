# NixOS module for SeerrNG, a community fork of Seerr that also handles music,
# books, comics, ROMs and software requests.
#
# Modeled on the upstream `services.seerr` module (nixpkgs: seerr.nix) so the
# two services are configured and hardened the same way. The package is provided
# by this repo (see pkgs/seerrng.nix) because SeerrNG is not in nixpkgs.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.seerrng;
in
{
  options.services.seerrng = {
    enable = lib.mkEnableOption "SeerrNG, a requests manager for Jellyfin, Plex and Emby";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../pkgs/seerrng.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ../pkgs/seerrng.nix { }";
      description = "The SeerrNG package to use.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open the port in the firewall for the SeerrNG web interface.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 5055;
      description = "Port the SeerrNG web UI listens on.";
    };

    configDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/seerrng";
      description = "Directory holding SeerrNG's settings, database and logs.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.seerrng = {
      description = "SeerrNG, a requests manager for Jellyfin, Plex and Emby";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        PORT = toString cfg.port;
        CONFIG_DIRECTORY = cfg.configDir;
      };

      serviceConfig = {
        Type = "exec";
        # Keep this a parent of configDir; StateDirectory is made writable under
        # ProtectSystem = "strict".
        StateDirectory = "seerrng";
        DynamicUser = true;
        ExecStart = lib.getExe cfg.package;
        Restart = "on-failure";
        ProtectHome = true;
        ProtectSystem = "strict";
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectHostname = true;
        ProtectClock = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        NoNewPrivileges = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        RemoveIPC = true;
        PrivateMounts = true;
      };

      unitConfig.RequiresMountsFor = [ cfg.configDir ];
    };

    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [ cfg.port ];
    };
  };
}
