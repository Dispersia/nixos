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
    "${mediaRoot}/audiobooks"
    "${mediaRoot}/movies"
    "${mediaRoot}/manga"
    "${mediaRoot}/manhua"
    "${mediaRoot}/manhwa"
    downloadsRoot
  ];
  libraryDirs = [
    "${mediaRoot}/shows"
    "${mediaRoot}/audiobooks"
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

  systemd.services.qbittorrent.serviceConfig.UMask = "0002";

  services.flaresolverr.enable = true;

  # The WebUI password already lives in /var/lib/qBittorrent/qBittorrent.conf;
  # the credential file that used to seed it is gone, so no LoadCredential here.
  services.qbittorrent = {
    enable = true;
    openFirewall = true;
    group = "media";
    webuiPort = 8080;
    torrentingPort = 6881;
    extraArgs = [ "--confirm-legal-notice" ];
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

  # Mediarium is the only media manager now. It must use `media` as its
  # primary group: Synology NFS only evaluates the primary group, so hardlinked
  # imports from downloads stay readable by Jellyfin.
  services.mediarium = {
    enable = true;
    openFirewall = true;
    group = "media";

    moviesDir = "${mediaRoot}/movies";
    tvDir = "${mediaRoot}/shows";
    downloadsDir = downloadsRoot;
    # Mediarium calls this option `ebooksDir`; the NAS share is `books`.
    ebooksDir = "${mediaRoot}/books";
    audiobooksDir = "${mediaRoot}/audiobooks";

    # musicDir keeps its default under /var/lib/mediarium/data.
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
      jellyfin = {
        port = 8096;
      };
      qbittorrent = {
        port = 8080;
      };
      # Mediarium is the library/request front end, so it answers as
      # request.home.arpa (port 8264).
      request = {
        port = 8264;
      };
      flaresolverr = {
        port = 8191;
      };
      # ComfyUI runs on the desktop (AMD GPU) and listens on its tailnet
      # address; Caddy proxies to it over the tailnet.
      comfy = {
        host = "desktop.tail7c1ddb.ts.net";
        port = 8188;
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
      "qbittorrent"
      "flaresolverr"
      "mediarium"
    ];
    ports = [
      8080
      8191
      8264
    ];
  };

  networking.firewall.allowedTCPPorts = [ ];
  networking.firewall.allowedUDPPorts = [ 6881 ];
}
