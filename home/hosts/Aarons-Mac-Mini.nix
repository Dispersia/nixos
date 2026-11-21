{ ... }:
{
  imports = [
    ../cli

    ../development/git
    ../development/neovim
    ../development/node
    ../development/opencode

    ../environment/alacritty
    ../environment/brave
    ../environment/discord
    ../environment/gpg
    ../environment/yazi
    ../environment/zellij

    ../shell/carapace
    ../shell/direnv
    ../shell/nushell
    ../shell/starship
  ];

  # OpenDesign's bundled web frontend defaults to a loopback bind, and Caddy
  # only answers a request when its Host matches the site address
  # (`127.0.0.1:5174`) — anything else gets an empty 200. Setting the host to
  # the empty wildcard emits `http://:5174`, a catch-all listener, so the
  # home-server gateway can reverse-proxy https://design.home.arpa to it with
  # the original Host header preserved. `allowedOrigins` admits that origin at
  # the daemon's fail-closed same-origin gate; every other Host (the LAN IP,
  # the tailnet name) is still refused by the API, so the SPA only works
  # through the gateway. The route itself lives on home-server (media.nix).
  services.open-design.webFrontend = {
    host = "";
    allowedOrigins = [ "https://design.home.arpa" ];
  };

  # macOS "App Management" (TCC) cannot be granted to the comin deploy daemon,
  # so Home Manager's copyApps mode fails every activation and runs
  # `tccutil reset SystemPolicyAppBundles`, which wipes the permission you gave
  # Alacritty (and aborts the switch before Discord etc. get installed).
  # Symlinking the apps needs no TCC permission and works under comin.
  targets.darwin = {
    copyApps.enable = false;
    linkApps.enable = true;
  };
}
