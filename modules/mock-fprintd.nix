{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.mock-fprintd;

  inherit (lib)
    genAttrs
    mkDefault
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  package = pkgs.callPackage ../pkgs/mock-fprintd { };
in
{
  options.services.mock-fprintd = {
    enable = mkEnableOption ''
      a mock fprintd D-Bus service that always reports a successful
      fingerprint verification.

      This is a testing aid: any biometric authentication routed through
      `net.reactivated.Fprint` (including `pam_fprintd`) succeeds
      unconditionally. Do not enable it on a security-sensitive host.
    '';

    package = mkOption {
      type = types.package;
      default = package;
      defaultText = lib.literalExpression "pkgs.callPackage ../pkgs/mock-fprintd { }";
      description = "The mock fprintd package to use.";
    };

    pam = {
      enable = mkEnableOption ''
        `pam_fprintd` for the services listed in
        {option}`services.mock-fprintd.pam.services`, backed by the mock
        daemon. Those services will then accept any "fingerprint".
      '';

      services = mkOption {
        type = types.listOf types.str;
        default = [ "login" ];
        example = [
          "login"
          "sudo"
          "polkit-1"
        ];
        description = ''
          Names of PAM services that should use `pam_fprintd`, backed by the
          mock daemon.

          Services whose stack sub-stacks `login` (for example `sddm`) are
          covered automatically; services with their own stack (such as `sudo`
          or `polkit-1`) must be listed explicitly.
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = !config.services.fprintd.enable;
        message = ''
          `services.fprintd` and `services.mock-fprintd` both provide the
          `net.reactivated.Fprint` D-Bus name and cannot be enabled at the
          same time.
        '';
      }
    ];

    warnings = [
      ''
        services.mock-fprintd is enabled: biometric authentication always
        succeeds on this host. This is a testing configuration and should not
        be used on a security-sensitive system.
      ''
    ];

    # Provides the D-Bus policy and the on-demand activation file
    # (share/dbus-1/system.d + share/dbus-1/system-services).
    services.dbus.packages = [ cfg.package ];

    # Run the mock early and keep the bus name owned for the whole session,
    # rather than relying on D-Bus activation.
    systemd.services.mock-fprintd = {
      description = "Mock fprintd (always-match biometric provider)";
      wantedBy = [ "multi-user.target" ];
      after = [ "dbus.service" ];
      requires = [ "dbus.service" ];
      serviceConfig = {
        Type = "dbus";
        BusName = "net.reactivated.Fprint";
        ExecStart = "${cfg.package}/bin/mock-fprintd";
        Restart = "on-failure";
        RestartSec = 2;
      };
    };

    # `pam_fprintd.so` is taken from the real fprintd package; only the PAM
    # module is used. The real daemon stays disabled (asserted above).
    services.fprintd.package = mkDefault pkgs.fprintd;

    security.pam.services = mkIf cfg.pam.enable (
      genAttrs cfg.pam.services (_: {
        fprintAuth = true;
      })
    );
  };
}
