{
  pkgs,
  lib,
  username,
  ...
}:
let
  nordvpn = pkgs.callPackage (
    {
      autoPatchelfHook,
      buildFHSEnv,
      dpkg,
      fetchurl,
      lib,
      stdenv,
      sysctl,
      iptables,
      nftables,
      iproute2,
      procps,
      cacert,
      libxml2,
      libidn2,
      zlib,
      sqlite,
      libnl,
      libcap_ng,
      wireguard-tools,
    }:
    let
      pname = "nordvpn";
      version = "5.1.0";

      nordvpnBase = stdenv.mkDerivation {
        inherit pname version;

        src = fetchurl {
          url = "https://repo.nordvpn.com/deb/nordvpn/debian/pool/main/n/nordvpn/nordvpn_${version}_amd64.deb";
          hash = "sha256-10Cfjjy5AQ88ZdFRLyjnR2aL6roGroa0/SuFu2nuD8k=";
        };

        buildInputs = [
          libxml2
          libidn2
          sqlite
          libnl
          libcap_ng
        ];
        nativeBuildInputs = [
          dpkg
          autoPatchelfHook
          stdenv.cc.cc.lib
        ];

        dontConfigure = true;
        dontBuild = true;

        unpackPhase = ''
          runHook preUnpack
          dpkg --extract $src .
          runHook postUnpack
        '';

        installPhase = ''
          runHook preInstall
          mkdir -p $out
          mv usr/* $out/
          mv var/ $out/
          mv etc/ $out/
          runHook postInstall
        '';
      };

      nordvpnFhs = buildFHSEnv {
        name = "nordvpnd";
        runScript = "nordvpnd";

        targetPkgs = pkgs: [
          nordvpnBase
          sysctl
          iptables
          nftables
          iproute2
          procps
          cacert
          libxml2
          libidn2
          zlib
          sqlite
          libnl
          libcap_ng
          wireguard-tools
        ];
      };
    in
    stdenv.mkDerivation {
      inherit pname version;

      dontUnpack = true;
      dontConfigure = true;
      dontBuild = true;

      installPhase = ''
        runHook preInstall
        mkdir -p $out/bin $out/share
        ln -s ${nordvpnBase}/bin/nordvpn $out/bin
        ln -s ${nordvpnFhs}/bin/nordvpnd $out/bin
        ln -s ${nordvpnBase}/share/* $out/share/
        ln -s ${nordvpnBase}/var $out/
        runHook postInstall
      '';

      meta = with lib; {
        description = "CLI client for NordVPN";
        homepage = "https://www.nordvpn.com";
        license = licenses.unfreeRedistributable;
        platforms = [ "x86_64-linux" ];
      };
    }
  ) { };
in
{
  networking.firewall = {
    checkReversePath = false;
    allowedUDPPorts = [ 1194 ];
    allowedTCPPorts = [ 443 ];
  };

  services.resolved.enable = true;

  environment.systemPackages = [ nordvpn ];

  users.groups.nordvpn.members = [ username ];

  systemd.services.nordvpn = {
    description = "NordVPN daemon.";
    serviceConfig = {
      ExecStart = "${nordvpn}/bin/nordvpnd";
      ExecStartPre = pkgs.writeShellScript "nordvpn-start" ''
        mkdir -m 700 -p /var/lib/nordvpn;
        if [ -z "$(ls -A /var/lib/nordvpn)" ]; then
          cp -r ${nordvpn}/var/lib/nordvpn/* /var/lib/nordvpn;
        fi
      '';
      NonBlocking = true;
      KillMode = "process";
      Restart = "on-failure";
      RestartSec = 5;
      RuntimeDirectory = "nordvpn";
      RuntimeDirectoryMode = "0750";
      Group = "nordvpn";
    };
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
  };
}
