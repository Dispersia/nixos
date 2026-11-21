{
  config,
  inputs,
  hostName,
  pkgs,
  lib,
  ...
}:
let
  # comin's own darwin module generates this YAML internally and hands the
  # resulting store path to `comin run --config …`. We generate the very same
  # file here so the daemon can read it from the stable /etc/comin.yaml path
  # instead of a store path (see the plist comment below).
  cominConfigLib = import (inputs.comin + "/nix/comin-config.nix") {
    inherit config pkgs lib;
  };

  # PATH entry that never changes: the system profile plus the base system.
  # comin itself, `nix`, `git` and `openssh` all live in /run/current-system/sw
  # (comin's own module puts its package there, the other three are added to
  # environment.systemPackages below), so the daemon still finds every binary it
  # shells out to. /usr/bin also gives the activation the usual system tools
  # (grep, diff, …) that comin's otherwise minimal launchd PATH was missing.
  cominPath = "/run/current-system/sw/bin:/usr/bin:/bin:/usr/sbin:/sbin";
in
{
  imports = [ inputs.comin.darwinModules.comin ];

  services.comin = {
    enable = true;

    hostname = hostName;

    # comin defaults the gRPC socket group to the Linux group `users`, which
    # macOS does not have, so the lookup fails and the whole gRPC server
    # refuses to start ("failed to lookup group users: group: unknown group
    # users"). `staff` is the group every regular macOS account belongs to, so
    # the socket (mode 0770) stays reachable without sudo; an empty value skips
    # the chown and leaves it in the daemon group, i.e. root-only.
    grpc.unix_socket_group = "staff";

    remotes = [
      {
        name = "origin";
        url = "https://github.com/Dispersia/nixos";

        branches.main.name = "master";
      }
    ];
  };

  # comin runs the nix-darwin activation as its own child, so anything that
  # makes nix-darwin reload the comin service kills comin — and takes the
  # activation down with it. `system.activationScripts.launchd` reloads a
  # daemon whenever its generated plist differs from the installed one, and the
  # plist comin's module generates embeds store paths: PATH via `makeBinPath [
  # nix git openssh ]`, the comin binary, and the comin.yaml path. Every
  # nixpkgs bump moved PATH, so the reload fired and killed the activation
  # half-way (2026-11-10, and on 2026-11-20 launchd never brought comin back at
  # all). Keep every path in the plist stable so it is byte-identical every
  # generation and the reload never fires.
  environment.systemPackages = [
    config.nix.package
    pkgs.git
    pkgs.openssh
  ];

  environment.etc."comin.yaml".source = cominConfigLib.cominConfigYaml;

  launchd.daemons.comin = {
    # Both the binary and the config are addressed through stable paths; any
    # store path here would come back the moment nixpkgs bumps comin, nix, git
    # or openssh.
    command = lib.mkForce "/run/current-system/sw/bin/comin run --config /etc/comin.yaml";
    serviceConfig.EnvironmentVariables.PATH = lib.mkForce cominPath;
  };

  # Belt and braces: if some future change to the comin plist (a comin bump, a
  # label change) does make nix-darwin unload the service mid-activation, put
  # it back. The watchdog is a separate process, so its own reload cannot hurt.
  launchd.daemons.comin-watchdog = {
    script = ''
      plist=/Library/LaunchDaemons/com.github.nlewo.comin.plist

      if /bin/launchctl print system/com.github.nlewo.comin > /dev/null 2>&1; then
        exit 0
      fi

      if [ -f "$plist" ]; then
        echo "comin is not loaded, bootstrapping it" >&2
        /bin/launchctl bootstrap system "$plist"
      fi
    '';

    serviceConfig = {
      RunAtLoad = true;
      StartInterval = 60;
      StandardOutPath = "/var/log/comin-watchdog.log";
      StandardErrorPath = "/var/log/comin-watchdog.log";
    };
  };
}
