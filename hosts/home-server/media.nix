{ config, lib, pkgs, ... }:

let
  mediaRoot = "/mnt/media";
  downloadsRoot = "${mediaRoot}/downloads";
  mediaDirs = [
    mediaRoot
    "${mediaRoot}/shows"
    "${mediaRoot}/movies"
    "${mediaRoot}/manga"
    "${mediaRoot}/manhua"
    "${mediaRoot}/manhwa"
    downloadsRoot
  ];
  libraryDirs = [
    "${mediaRoot}/shows"
    "${mediaRoot}/movies"
    "${mediaRoot}/manga"
  ];
  permissionDirs = libraryDirs ++ [ downloadsRoot ];
in
{
  users.groups.media.gid = 2000;

  users.users.jellyfin.extraGroups = [ "media" ];

  # The Synology NFS server only evaluates a request's primary group, not its
  # supplementary groups. Every media-stack service therefore uses `media` as
  # its primary group. Jellyfin must too, otherwise it cannot read the files
  # SABnzbd/Sonarr create with mode 0660 (group `media`) and playback fails
  # with "Permission denied".
  services.jellyfin.group = "media";

  systemd.services.media-directories = {
    description = "Create media library directories";

    wantedBy = [ "multi-user.target" ];

    after = [ "mnt-media.automount" ];
    requires = [ "mnt-media.automount" ];

    unitConfig.RequiresMountsFor = [ mediaRoot ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.coreutils}/bin/install -d -o root -g media -m 2775 ${lib.escapeShellArgs mediaDirs}";
    };
  };

  systemd.services.media-permissions = {
    description = "Fix media library permissions";

    wantedBy = [ "multi-user.target" ];

    after = [
      "mnt-media.automount"
      "media-directories.service"
    ];
    requires = [ "media-directories.service" ];

    unitConfig = {
      RequiresMountsFor = [ mediaRoot ];
      ConditionPathExists = "!/var/lib/media-permissions-fixed-v3";
    };

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      ${pkgs.coreutils}/bin/chgrp -R media ${lib.escapeShellArgs permissionDirs}
      ${pkgs.coreutils}/bin/chmod -R g+rwX ${lib.escapeShellArgs permissionDirs}
      ${pkgs.coreutils}/bin/chmod -R o+rX ${lib.escapeShellArgs permissionDirs}
      ${pkgs.findutils}/bin/find ${lib.escapeShellArgs permissionDirs} -type d -exec ${pkgs.coreutils}/bin/chmod g+s {} +
      ${pkgs.coreutils}/bin/touch /var/lib/media-permissions-fixed-v3
    '';
  };

  systemd.services.sonarr.serviceConfig.UMask = lib.mkForce "0002";
  systemd.services.radarr.serviceConfig.UMask = lib.mkForce "0002";
  systemd.services.bazarr.serviceConfig.UMask = "0002";
  systemd.services.qbittorrent.serviceConfig.UMask = "0002";
  systemd.services.sabnzbd.serviceConfig.UMask = "0002";

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

  services.flaresolverr.enable = true;

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

  services.sabnzbd = {
    enable = true;
    openFirewall = true;
    group = "media";
    allowConfigWrite = true;
    settings.misc = {
      host = "0.0.0.0";
      port = 8085;
      inet_exposure = "api+web (locally no auth)";
      download_dir = "/var/lib/sabnzbd/downloads";
      complete_dir = "/mnt/media/downloads";
      permissions = "775";
    };
  };

  # bookkeeprr: self-hosted manager for manga, comics, light novels, ebooks and
  # audiobooks. Runs the official upstream image (which is far newer than
  # anything packaged) and points it at the existing media share, qBittorrent
  # and Prowlarr.
  virtualisation.podman.enable = true;

  systemd.tmpfiles.rules = [
    "d /var/lib/bookkeeprr 0755 root root -"
  ];

  virtualisation.oci-containers.containers.bookkeeprr = {
    image = "ghcr.io/paulcsiki/bookkeeprr:latest";

    environment = {
      TZ = "America/Phoenix";
      BOOKKEEPRR_LOG_LEVEL = "info";
    };

    # Share the host network namespace so bookkeeprr can reach the other
    # services at 127.0.0.1 (qBittorrent, Prowlarr, ...) exactly like the
    # native *arr services do.
    extraOptions = [ "--network=host" ];

    volumes = [
      "/var/lib/bookkeeprr:/config"
      "${mediaRoot}:/media"
    ];
  };

  systemd.services."${config.virtualisation.oci-containers.backend}-bookkeeprr".unitConfig.RequiresMountsFor = [ mediaRoot ];

  # Remove the previous Suwayomi install completely. The unit only runs while
  # the old data directory still exists, so it deactivates itself after the
  # first successful switch.
  systemd.services.suwayomi-cleanup = {
    description = "Remove leftover Suwayomi data";

    wantedBy = [ "multi-user.target" ];

    unitConfig.ConditionPathExists = "/var/lib/suwayomi-server";

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      ${pkgs.coreutils}/bin/rm -rf /var/lib/suwayomi-server
      ${pkgs.podman}/bin/podman rmi ghcr.io/suwayomi/suwayomi-server:stable 2>/dev/null || true
    '';
  };

  services.seerr = {
    enable = true;
    openFirewall = true;
  };

  networking.firewall.allowedTCPPorts = [ 3000 ];
  networking.firewall.allowedUDPPorts = [ 6881 ];
}
