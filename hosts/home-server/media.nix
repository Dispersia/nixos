{ lib, pkgs, ... }:

let
  mediaRoot = "/mnt/media";
  downloadsRoot = "${mediaRoot}/downloads";
in
{
  users.groups.media.gid = 2000;

  systemd.services.media-directories = {
    description = "Create media library directories";

    wantedBy = [ "multi-user.target" ];

    after = [ "mnt-media.automount" ];
    requires = [ "mnt-media.automount" ];

    unitConfig.RequiresMountsFor = [ mediaRoot ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.coreutils}/bin/install -d -o root -g media -m 0775 ${mediaRoot}/manhua ${mediaRoot}/manhwa ${downloadsRoot}";
    };
  };

  systemd.services.sonarr.serviceConfig.UMask = lib.mkForce "0002";
  systemd.services.radarr.serviceConfig.UMask = lib.mkForce "0002";
  systemd.services.bazarr.serviceConfig.UMask = "0002";
  systemd.services.qbittorrent.serviceConfig.UMask = "0002";
  systemd.services.suwayomi-server.serviceConfig.UMask = "0002";

  services.sonarr = {
    enable = true;
    openFirewall = true;
    group = "media";
  };

  services.radarr = {
    enable = true;
    openFirewall = true;
    group = "media";
  };

  services.prowlarr = {
    enable = true;
    openFirewall = true;
  };

  services.bazarr = {
    enable = true;
    openFirewall = true;
    group = "media";
  };

  services.qbittorrent = {
    enable = true;
    openFirewall = true;
    group = "media";
    webuiPort = 8080;
    torrentingPort = 6881;
    extraArgs = [ "--confirm-legal-notice" ];
    serverConfig.LegalNotice.Accepted = true;
  };

  services.suwayomi-server = {
    enable = true;
    openFirewall = true;
    group = "media";
    settings.server.port = 4567;
  };

  services.seerr = {
    enable = true;
    openFirewall = true;
  };

  networking.firewall.allowedUDPPorts = [ 6881 ];
}
