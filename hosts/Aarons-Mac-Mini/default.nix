{
  config,
  pkgs,
  inputs,
  hostName,
  username,
  ...
}:
let
  home = "/Users/${username}";
  # The virtualenv `services.yomifin.ocr` used to build and own. The checkout
  # daemon below reuses it (it already carries paddleocr, yomitoku and mlx), so
  # switching engines now means `uv pip install` into it by hand.
  ocrVenv = "${home}/Library/Application Support/YomiFin/ocr/venv";

  # The interpreter that venv was built against. Naming it here keeps it in the
  # system closure: the venv only reaches it through symlinks and `pyvenv.cfg`,
  # which nix-collect-garbage does not follow, so without this a GC could delete
  # the interpreter and leave every script in the venv with a dangling shebang.
  ocrVenvPython = "/nix/store/ydlh8id2c98nnlhiy87hwhalg501p1j5-python3-3.13.15";

  # The OCR sidecar Jellyfin actually talks to (the plugin's OcrSidecarUrl is
  # http://192.168.4.45:8646) runs the working checkout, not a copy in the Nix
  # store, so a code change only needs
  #   sudo launchctl kickstart -k system/org.nixos.yomifin-ocr-checkout
  # and no darwin-rebuild.
  #
  # It is deliberately a *system* daemon (launchd.daemons, not launchd.user
  # .agents): the hand-written LaunchAgent this replaces only loads at a console
  # login, so after the reboot on 2026-10-25 the sidecar never came back and
  # Jellyfin's OCR was silently down until someone looked. See "One OCR sidecar
  # instead of two" below.
  ocrCheckout = pkgs.writeShellScript "yomifin-ocr-checkout" ''
    set -eu

    # The sidecar reads its bearer token from the environment. Reading the file
    # here keeps the secret out of this (world-readable) store path; the file is
    # the same one the Jellyfin plugin's OcrSidecarApiKey holds.
    YOMIFIN_OCR_TOKEN="$(cat /Users/dispe/.config/yomifin-ocr/token)"
    export YOMIFIN_OCR_TOKEN

    YOMIFIN_OCR_VENV_PYTHON="${ocrVenvPython}"
    export YOMIFIN_OCR_VENV_PYTHON

    exec "${ocrVenv}/bin/python" -m uvicorn service.app:app \
      --app-dir /Users/dispe/development/yomifin/ocr \
      --host 192.168.4.45 \
      --port 8646
  '';
in
{
  imports = [
    ../../modules/darwin-system.nix
    ../../modules/comin-darwin.nix
    ../../modules/forge-neo-darwin.nix
    ../../modules/kimaki-darwin.nix
    ../../modules/tailnet-gateway-darwin.nix

    # The sidecar modules now come from the YomiFin repository's own flakes
    # (see the `yomifin-ocr` / `yomifin-upscale` inputs in flake.nix) instead of
    # the vendored copies this host used to carry.
    inputs.yomifin-ocr.darwinModules.default
    inputs.yomifin-upscale.darwinModules.default
  ];

  # Image generation WebUI. The first start installs torch and friends into
  # ~/ForgeNeo/venv (a few GB, takes a few minutes); after that, models go in
  # ~/ForgeNeo/models/<type>/ and extensions in ~/ForgeNeo/extensions/.
  services.forge-neo = {
    enable = true;
    user = username;
  };

  # One OCR sidecar instead of two. The module's store build on 8642 was the
  # same engines with the same models loaded, a second copy of the same
  # multi-gigabyte process, and it could not serve the plugin's settings anyway
  # (no `mlx` extra, so no PaddleOCR-VL). It is replaced by the checkout daemon
  # above, which Jellyfin and the upscale sidecar's lettering pass both talk to.
  #
  # The module needs no rebuild to be restored: delete this line and the
  # `launchd.daemons` block, and the store build comes back on 8642.
  services.yomifin.ocr.enable = false;

  launchd.daemons.yomifin-ocr-checkout = {
    serviceConfig = {
      ProgramArguments = [ "${ocrCheckout}" ];
      UserName = username;
      KeepAlive = true;
      RunAtLoad = true;
      WorkingDirectory = "/Users/dispe/development/yomifin/ocr";
      StandardOutPath = "${home}/Library/Application Support/YomiFin/ocr-repo/stdout.log";
      StandardErrorPath = "${home}/Library/Application Support/YomiFin/ocr-repo/stderr.log";

      EnvironmentVariables = {
        # launchd daemons get a bare environment: without HOME every model cache
        # (~/.paddlex, the Hugging Face cache) lands in the wrong place.
        HOME = home;
        PATH = "/usr/bin:/bin:/usr/sbin:/sbin";
        PYTHONUNBUFFERED = "1";
        # Release the loaded engines after ten quiet minutes instead of holding
        # ~2.5 GB forever; `0` keeps them loaded. See docs/api.md.
        YOMIFIN_OCR_IDLE_UNLOAD_SECONDS = "600";
      };
    };
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
    # It follows the checkout daemon, which is the only OCR sidecar now.
    textRestore = true;
    ocrUrl = "http://192.168.4.45:8646";
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
    routes.forge.port = config.services.forge-neo.port;
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

    # Same identities that can log in to the other servers (home-server).
    # nix-darwin exposes these via
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
