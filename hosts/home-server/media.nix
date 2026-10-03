{
  config,
  lib,
  pkgs,
  ...
}:

let
  mediaRoot = "/mnt/media";
  downloadsRoot = "${mediaRoot}/downloads";
  mediaDirs = [
    mediaRoot
    "${mediaRoot}/shows"
    "${mediaRoot}/movies"
    "${mediaRoot}/books"
    "${mediaRoot}/comics"
    "${mediaRoot}/manga"
    "${mediaRoot}/manhua"
    "${mediaRoot}/manhwa"
    downloadsRoot
  ];
  libraryDirs = [
    "${mediaRoot}/shows"
    "${mediaRoot}/movies"
    "${mediaRoot}/books"
    "${mediaRoot}/comics"
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
      ConditionPathExists = "!/var/lib/media-permissions-fixed-v4";
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
      ${pkgs.coreutils}/bin/touch /var/lib/media-permissions-fixed-v4
    '';
  };

  systemd.services.sonarr.serviceConfig.UMask = lib.mkForce "0002";
  systemd.services.radarr.serviceConfig.UMask = lib.mkForce "0002";
  systemd.services.bazarr.serviceConfig.UMask = "0002";
  systemd.services.qbittorrent.serviceConfig.UMask = "0002";

  systemd.services.qbittorrent.serviceConfig.LoadCredential = [
    "webui:/home/dispe/.secrets/qbittorrent-webui.conf"
  ];

  systemd.services.qbittorrent.preStart = lib.mkAfter ''
    conf=/var/lib/qBittorrent/qBittorrent/config/qBittorrent.conf
    ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$conf")"
    if [ -n "''${CREDENTIALS_DIRECTORY:-}" ] && [ -f "$CREDENTIALS_DIRECTORY/webui" ] && ! ${pkgs.gnugrep}/bin/grep -qF 'WebUI\Password_PBKDF2' "$conf" 2>/dev/null; then
      ${pkgs.coreutils}/bin/cat "$CREDENTIALS_DIRECTORY/webui" >> "$conf"
    fi
  '';
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
      host_whitelist = "sabnzbd.${config.services.tailnetGateway.domain}";
    };
  };

  # librarr: self-hosted book, audiobook and manga search/download manager
  # ("the missing *arr for books"). Runs the upstream image and points it at
  # the existing media share, qBittorrent and Prowlarr. Secrets live in
  # /home/dispe/.secrets/librarr.env and are injected with --env-file so they
  # never enter the world-readable Nix store.
  virtualisation.podman.enable = true;

  systemd.tmpfiles.rules = [
    # The image runs as uid 1000 (librarr), which maps 1:1 to host uid dispe.
    # The group is `media` (2000) so imports land on the share writable.
    "d /var/lib/librarr 0775 1000 2000 -"
  ];

  virtualisation.oci-containers.containers.librarr = {
    image = "ghcr.io/jeremiahm37/librarr:latest";

    environment = {
      TZ = "America/Phoenix";
      LIBRARR_PORT = "5050";

      AUTH_USERNAME = "admin";

      # Reach the native *arr services and qBittorrent on the host loopback.
      PROWLARR_URL = "http://127.0.0.1:9696";
      QB_URL = "http://127.0.0.1:8080";
      QB_USER = "dispe";

      # Paths as seen inside the container. The whole media share is mounted at
      # /media so downloads and the library share one filesystem (hardlink
      # imports stay on the same device).
      QB_SAVE_PATH = "/media/downloads";
      QB_CATEGORY = "librarr";
      QB_MANGA_SAVE_PATH = "/media/downloads";
      QB_MANGA_CATEGORY = "manga";
      INCOMING_DIR = "/media/downloads";
      EBOOK_DIR = "/media/books";
      MANGA_DIR = "/media/manga";
    };

    # Secrets: AUTH_PASSWORD, API_KEY, TORZNAB_API_KEY, PROWLARR_API_KEY,
    # QB_PASS.
    environmentFiles = [ "/home/dispe/.secrets/librarr.env" ];

    # Share the host network namespace so librarr can reach the other services
    # at 127.0.0.1 exactly like the native *arr services do.
    extraOptions = [ "--network=host" ];

    # uid 1000 = librarr in the image, gid 2000 = media on the host. Synology
    # NFS only honors the primary group, so librarr must be in `media` as its
    # primary group to write into the share.
    user = "1000:2000";

    volumes = [
      "/var/lib/librarr:/data"
      "${mediaRoot}:/media"
    ];
  };

  systemd.services."${config.virtualisation.oci-containers.backend}-librarr".unitConfig.RequiresMountsFor =
    [ mediaRoot ];

  # Remove the previous bookkeeprr install (container, image and data). The unit
  # only runs while the old data directory still exists, so it deactivates
  # itself after the first successful switch.
  systemd.services.bookkeeprr-cleanup = {
    description = "Remove leftover bookkeeprr data and image";

    wantedBy = [ "multi-user.target" ];

    unitConfig.ConditionPathExists = "/var/lib/bookkeeprr";

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      ${pkgs.podman}/bin/podman rm -f bookkeeprr 2>/dev/null || true
      ${pkgs.coreutils}/bin/rm -rf /var/lib/bookkeeprr
      ${pkgs.podman}/bin/podman rmi ghcr.io/paulcsiki/bookkeeprr:latest 2>/dev/null || true
    '';
  };

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

  services.tailnetGateway = {
    enable = true;
    address = "100.84.150.49";
    routes = {
      prowlarr = {
        port = 9696;
      };
      sonarr = {
        port = 8989;
      };
      radarr = {
        port = 7878;
      };
      bazarr = {
        port = 6767;
      };
      jellyfin = {
        port = 8096;
      };
      qbittorrent = {
        port = 8080;
      };
      sabnzbd = {
        port = 8085;
      };
      seerr = {
        port = 5055;
      };
      librarr = {
        port = 5050;
      };
      flaresolverr = {
        port = 8191;
      };
    };
  };

  services.nordvpnNetns = {
    enable = true;
    tokenFile = "/home/dispe/.secrets/nordvpn-token";
    country = "United States";
    services = [
      "prowlarr"
      "sonarr"
      "radarr"
      "qbittorrent"
      "sabnzbd"
      "flaresolverr"
    ];
    ports = [
      8080
      8085
      8191
      8989
      7878
      9696
    ];
  };

  networking.firewall.allowedTCPPorts = [ 5050 ];
  networking.firewall.allowedUDPPorts = [ 6881 ];
}
