{
  config,
  pkgs,
  hostName,
  username,
  ...
}:
{
  imports = [
    ../../modules/darwin-system.nix
    ../../modules/comin-darwin.nix
    ../../modules/kimaki-darwin.nix
    ../../modules/tailnet-gateway-darwin.nix
    ../../modules/yomifin-ocr.nix
    ../../modules/yomifin-upscale.nix
  ];

  services.yomifin.ocr = {
    enable = true;
    user = username;
    # Reachable from the home server over the LAN (en0). Keep this in sync with
    # the Jellyfin YomiFin plugin's OcrSidecarUrl; use a DHCP reservation so it
    # does not drift.
    host = "192.168.4.45";
    authTokenFile = "/Users/dispe/.config/yomifin-ocr/token";
    engines = [
      "yomitoku"
      "paddleocr"
    ];
  };

  services.yomifin.upscale = {
    enable = true;
    user = username;
    # Same host/port convention as the OCR sidecar. Keep this in sync with the
    # Jellyfin YomiFin plugin's UpscaleSidecarUrl.
    host = "192.168.4.45";
    port = 8643;
    # Reuses the OCR sidecar's bearer token so there is nothing new to create;
    # point this at a separate file if you would rather rotate them apart.
    authTokenFile = "/Users/dispe/.config/yomifin-ocr/token";
    autoDownloadModels = true;
    # Lettering restoration: detect text via the local OCR sidecar (bound to the
    # LAN address, not loopback) and re-run the text model over those regions.
    textRestore = true;
    ocrUrl = "http://192.168.4.45:8642";
    ocrLanguage = "ja";
    ocrTokenFile = "/Users/dispe/.config/yomifin-ocr/token";
  };

  services.tailscale.enable = true;

  # Kimaki (the Discord bot for OpenCode 2) in gateway mode. It starts at
  # login and keeps running; the first start prints a one-time install URL in
  # ~/Library/Logs/kimaki.log that has to be authorized once in Discord.
  services.kimaki = {
    enable = true;
    user = username;
    machineName = hostName;
  };

  # Browser-trusted HTTPS gateway over the tailnet, the macOS equivalent of the
  # home-server's tailnetGateway: https://<hostname>/ lists the routes below.
  # Add a service with `routes.<name>.port` once it listens on loopback.
  services.tailnetGateway = {
    enable = true;
    hostname = "aarons-mac-mini.tail7c1ddb.ts.net";
    routes = { };
  };

  # Reach the Mac itself over the tailnet (also serves as the SSH host for the
  # comin deploy, and for remote diagnostics). Same hardening as the servers.
  services.openssh = {
    enable = true;
    extraConfig = ''
      PasswordAuthentication no
      KbdInteractiveAuthentication no
      PermitRootLogin no
    '';
  };

  users.knownUsers = [ "${username}" ];
  users.users.${username} = {
    home = "/Users/${username}";
    uid = 501;
    shell = pkgs.nushell;

    # Same identities that can log in to the other servers (home-server /
    # home-gpu-server). nix-darwin exposes these via
    # /etc/ssh/nix_authorized_keys.d/<user> and an sshd AuthorizedKeysCommand.
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDdHpd3gl8yy7jn4YPArVSj6bBNwaSMs8aewIF2/rmSqKy7yVfXdND3wESZHqH5FV69pQrEHk6ANe6nKmIqG+bKQ3UjLCJh9X+g7Ox8ZZBN7uakHYtetF9KtX3+h6hUBUsBDQvqdJucsUHZAz5P0tv+Zm+GsUuAscAu0wF7ZSOXtSX1MgJ4N86YnFCmYZEQ8Uvn7QJqmIm+1/SkIQLoSb8W1ZE8pygvjPwEK8Jc2hTl7WsmQt/xAeaOqY5Rk6dJM3Np9Rh6XY3LZOBck6ZwsSvIzK4imzhnUItscgu8lVmNX7s4bMlQz95270Hyby5ZcoM3xPlzhnA4dR5Z+ve55g+aHLhc/wdem+N2slVBhigvo0pHfKsoc+qNjcvqiUcrEurhlMV14kwLWaNGZz67qw9G2zt/SM+/RRVjvpHzvslXf85+dTJz9fP3XE3Cs6uGUW6tAhbIfsCbZ7V9tCnElGEyEd5ldpvYUPCsUby1nUvp3hI0ogioHQ20XFx6ufQrDas= dispe@desktop"
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDvZJllZzaxzzsigwwN4UdTfrb3xDkZuZY9n2H13XawBXi88bRrHLfFiSOoJjJAbm166lNoaFoewf4cw4xGZNj/1UCPQlHEzFZTe3TiNooOuB5qrPe6mhDVx97QyDVC1ZBmO+WgDnJXx6V6DfAsROzswu4410uIswk+5gommpG4aro00yrdoABtCdaUpwWLdO6iU8nzVFoa3J6+nIuOx4IFWNepM/2FqFbHtJ4SxpH9ZzeHl26d+RG2L0kD7YKSBxS1eP6ayLqCMKaCqqOPUN+kUxqA9GkJGXi57LYR+uY5Ftzh5WP+Fm8dAKz3yQfLaycvaOx6noor6Hhbh1I3234w3O3SJGNbRTPcAAjbRfeVNjFU8/xuHGnq1haLMUq1Zact5UYtwJ9JGIf7fNQ4/w7qho3xyhIRqdeq3uLdpe90zd0PA70oH3aQK46spB9pIXe2dYfd+HK3QtLcDrB/vlwTqfjQnjmEJijMlTnY5pVH4gzlBVWdztMn6i+0jAsTRD8= dispe@Aarons-Mac-Mini.local"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK3l1mK1GwXy63qvLCikygZSm+Sgvfv4MJcdIcmFPFR8 dispersias@gmail.com"
    ];
  };

  system.primaryUser = username;

  homebrew.enable = false;

  system.stateVersion = 6;

  power = {
    sleep = {
      computer = "never";
      harddisk = "never";
    };

    restartAfterPowerFailure = true;
    restartAfterFreeze = true;
  };

  system.activationScripts.disableSleep.text = ''
    echo "configuring always-on server power settings..." >&2
    /usr/bin/pmset -a sleep 0
    /usr/bin/pmset -a disablesleep 1
  '';
}
