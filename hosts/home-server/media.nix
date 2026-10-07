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

  # Podman stays enabled for development tooling; no media containers are
  # defined here right now.
  virtualisation.podman.enable = true;

  # Remove the previous librarr install (container, image and data). The unit
  # only runs while the data directory still exists, so it deactivates itself
  # after the first successful switch.
  systemd.services.librarr-cleanup = {
    description = "Remove leftover librarr data and image";

    wantedBy = [ "multi-user.target" ];

    unitConfig.ConditionPathExists = "/var/lib/librarr";

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      ${pkgs.podman}/bin/podman rm -f librarr 2>/dev/null || true
      ${pkgs.coreutils}/bin/rm -rf /var/lib/librarr
      ${pkgs.podman}/bin/podman rmi ghcr.io/jeremiahm37/librarr:latest 2>/dev/null || true
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

    # Browser-trusted HTTPS name for Jellyfin, with a Tailscale (Let's Encrypt)
    # certificate fetched and renewed by Caddy. Use this on devices that can't
    # install the internal Caddy CA (e.g. Android/Brave), so the YomiFin reader
    # can be installed as a PWA: https://home-server.tail7c1ddb.ts.net/
    tailscaleHost = "home-server.tail7c1ddb.ts.net";

    # Resolve *.home.arpa to the LAN address so on-LAN clients connect
    # directly instead of through Tailscale (a relayed/DERP path makes Jellyfin
    # page downloads crawl). Off-LAN clients reach the same address through the
    # 192.168.4.50/32 subnet route advertised in default.nix.
    dnsAddress = "192.168.4.50";

    # Caddy also serves the LAN interface; binding all interfaces keeps the
    # tailnet address working for clients that cached the old DNS answer.
    listenAddress = "0.0.0.0";

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
      flaresolverr = {
        port = 8191;
      };
    };
  };

  # The tailnet gateway is now reachable from the LAN as well, not just the
  # tailscale0 interface (which is already trusted).
  services.caddy.openFirewall = true;

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

  networking.firewall.allowedTCPPorts = [ ];
  networking.firewall.allowedUDPPorts = [ 6881 ];
}
