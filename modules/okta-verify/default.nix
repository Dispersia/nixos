# Okta Verify for Linux, packaged from the vendor .deb.
#
# The payload (self-contained .NET apps, ~340 MB) lives unpatched in /opt/okta,
# installed by ./install-payload.sh. It is not patchelf'd because Okta verifies
# caller binaries/signatures; nix-ld supplies the dynamic loader and libraries.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  nixLdEnv = {
    NIX_LD = "/run/current-system/sw/share/nix-ld/lib/ld.so";
    NIX_LD_LIBRARY_PATH = "/run/current-system/sw/share/nix-ld/lib";
  };

  # The authenticator service rejects callers whose environment carries
  # LD_LIBRARY_PATH (treated as code injection), so launch the app without it.
  launcher = pkgs.writeShellScriptBin "okta-verify" ''
    unset LD_LIBRARY_PATH LD_PRELOAD
    exec /opt/okta/verify/oktaverify "$@"
  '';

  desktopIntegration = pkgs.runCommand "okta-verify-desktop" { } ''
    mkdir -p $out/share
    cp -r --no-preserve=mode ${./share}/applications ${./share}/icons $out/share/
    substituteInPlace $out/share/applications/*.desktop \
      --replace-fail /opt/okta/verify/oktaverify ${launcher}/bin/okta-verify
  '';
in
{
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    icu
    openssl
    krb5
    lttng-ust
    zlib
    stdenv.cc.cc.lib
    fontconfig.lib
    freetype
    libX11
    libXcursor
    libXrandr
    libXi
    libICE
    libSM
    libxcb
    libxkbcommon
    libglvnd
    glib
    dbus.lib
    tpm2-tss
    # Okta Verify bundles PCSC-Sharp, which loads libpcsclite for smart cards.
    pcsclite.lib
  ];

  users.users.okta-ff = {
    isSystemUser = true;
    group = "okta-ff";
  };
  users.groups.okta-ff = { };

  # YubiKey smart-card (CCID) access for Okta Verify.
  services.pcscd.enable = true;
  services.udev.packages = [ pkgs.yubikey-personalization ];

  environment.systemPackages = [
    launcher
    desktopIntegration
    pkgs.yubikey-manager
  ];

  systemd.tmpfiles.rules = [
    "d /etc/okta 1775 root okta-ff -"
    "d /etc/okta/authenticator 0755 root root -"
    "d /etc/okta/authenticator/Plugins 0755 root root -"
    "C+ /etc/okta/azureconfig.json 0440 root okta-ff - ${./azureconfig.json}"
    "C+ /etc/okta/oktaverify.json 0444 root root - ${./oktaverify.json}"
    "d /var/log/okta 0775 root okta-ff -"
  ];

  systemd.services.okta-feature-flag = {
    description = "Okta Feature Flag Service";
    documentation = [ "https://help.okta.com" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    unitConfig = {
      StartLimitIntervalSec = 30;
      StartLimitBurst = 5;
      ConditionPathExists = "/opt/okta/feature-flag-service/Okta.LinuxFeatureFlagService";
    };
    environment = nixLdEnv;
    serviceConfig = {
      Type = "notify";
      ExecStart = "/opt/okta/feature-flag-service/Okta.LinuxFeatureFlagService";
      WorkingDirectory = "/opt/okta/feature-flag-service";
      Restart = "on-failure";
      RestartSec = 5;
      User = "okta-ff";
      SyslogIdentifier = "okta-feature-flag";
      NoNewPrivileges = true;
      CapabilityBoundingSet = "";
    };
  };

  systemd.services.okta-authenticator = {
    description = "Okta Linux Authenticator Service";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    unitConfig = {
      StartLimitIntervalSec = 30;
      StartLimitBurst = 5;
      ConditionPathExists = "/opt/okta/okta-authenticator/Okta.OktaAuthenticatorService";
    };
    environment = nixLdEnv;
    serviceConfig = {
      Type = "notify";
      ExecStart = "/opt/okta/okta-authenticator/Okta.OktaAuthenticatorService";
      WorkingDirectory = "/opt/okta/okta-authenticator";
      Restart = "on-failure";
      RestartSec = 3;
      # Must match SocketPath's parent dir + DirectoryMode in UnixDomainSocketConstants.
      RuntimeDirectory = "okta-authenticator";
      RuntimeDirectoryMode = "0755";
      RuntimeDirectoryPreserve = "restart";
      SyslogIdentifier = "okta-authenticator";
      ReadWritePaths = "-/var/log/okta";
      LimitCORE = 0;
      User = "root";
      Group = "root";
      # DAC_OVERRIDE for /dev/tpmrm0, SYS_PTRACE for caller /proc/<pid>/exe resolution.
      CapabilityBoundingSet = [
        "CAP_DAC_OVERRIDE"
        "CAP_SYS_PTRACE"
      ];
      AmbientCapabilities = "";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      ProtectControlGroups = true;
      RestrictSUIDSGID = true;
      RestrictNamespaces = true;
      LockPersonality = true;
      RestrictAddressFamilies = [
        "AF_UNIX"
        "AF_INET"
        "AF_INET6"
      ];
      RestrictRealtime = true;
      ProtectHostname = true;
      ProtectClock = true;
      SystemCallArchitectures = "native";
      SystemCallFilter = [
        "@system-service"
        "~@privileged @resources"
        "sched_setaffinity sched_getaffinity"
      ];
      SystemCallErrorNumber = "EPERM";
    };
  };
}
