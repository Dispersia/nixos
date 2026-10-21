{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.tailnetGateway;
  inherit (lib)
    concatStringsSep
    mapAttrsToList
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  # Use the same daemon nix-darwin's Tailscale module starts.
  tailscale = "${config.services.tailscale.package}/bin/tailscale";

  landing = pkgs.writeTextDir "index.html" ''
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>${cfg.hostname}</title>
        <style>
          :root { color-scheme: light dark; }
          body { font: 16px/1.6 system-ui, sans-serif; max-width: 42rem; margin: 4rem auto; padding: 0 1.25rem; }
          h1 { font-size: 1.35rem; }
          ul { list-style: none; padding: 0; }
          li { margin: 0.35rem 0; }
          code { font-size: 0.9em; }
          a { text-decoration: none; }
          a:hover { text-decoration: underline; }
        </style>
      </head>
      <body>
        <h1>${cfg.hostname}</h1>
        <p>Served over your tailnet with a Tailscale (Let's Encrypt) certificate.</p>
        <ul>
          ${concatStringsSep "\n          " (
            mapAttrsToList (
              name: _: ''<li><a href="https://${cfg.hostname}/${name}/">${name}</a></li>''
            ) cfg.routes
          )}
        </ul>
        <p>SSH is available at <code>${cfg.hostname}</code> when Remote Login is on.</p>
      </body>
    </html>
  '';

  routeCommands = mapAttrsToList (
    name: route:
    "${tailscale} serve --yes --bg --https=${toString cfg.httpsPort} "
    + "--set-path=/${name} http://127.0.0.1:${toString route.port}"
  ) cfg.routes;

  apply = pkgs.writeShellApplication {
    name = "tailnet-gateway-apply";
    runtimeInputs = [
      pkgs.coreutils
    ];
    text = ''
      # Wait for tailscaled to answer (up to ~3 minutes) so this can run at boot
      # before the network is up.
      for _ in $(seq 1 90); do
        if ${tailscale} status >/dev/null 2>&1; then break; fi
        sleep 2
      done

      # Rebuild the serve configuration from scratch so removed routes disappear.
      ${tailscale} serve reset || true

      # Landing page at the tailnet root. On macOS this file/directory mode
      # only works with the open-source Tailscale variant that nix-darwin uses.
      ${tailscale} serve --yes --bg --https=${toString cfg.httpsPort} ${landing}

      ${concatStringsSep "\n" routeCommands}
    '';
  };
in
{
  options.services.tailnetGateway = {
    enable = mkEnableOption "a tailnet HTTPS gateway (Tailscale Serve) for macOS";

    hostname = mkOption {
      type = types.str;
      example = "aarons-mac-mini.tail7c1ddb.ts.net";
      description = ''
        Browser-trusted *.ts.net name clients use. Tailscale issues and renews
        the TLS certificate from the local daemon, so no CA needs installing.
        HTTPS must be enabled for the tailnet in the admin console.
      '';
    };

    httpsPort = mkOption {
      type = types.port;
      default = 443;
      description = "Port Serve listens on for HTTPS.";
    };

    routes = mkOption {
      type = types.attrsOf (
        types.submodule {
          options.port = mkOption {
            type = types.port;
            description = "Local loopback port to reverse proxy.";
          };
        }
      );
      default = { };
      example = lib.literalExpression ''
        {
          opencode = { port = 4096; };
        }
      '';
      description = ''
        HTTP services exposed at https://<hostname>/<name>. Tailscale Serve can
        only proxy to 127.0.0.1, so each backend must listen on loopback.
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = config.services.tailscale.enable;
        message = "services.tailnetGateway (darwin) requires services.tailscale.enable = true.";
      }
    ];

    # The gateway script is a small, idempotent oneshot: tailscaled persists
    # Serve state itself, and this re-applies it at every boot.
    launchd.daemons.tailnet-gateway = {
      command = "${apply}/bin/tailnet-gateway-apply";
      serviceConfig = {
        Label = "dev.tailnet-gateway.serve";
        RunAtLoad = true;
        StandardOutPath = "/var/log/tailnet-gateway.log";
        StandardErrorPath = "/var/log/tailnet-gateway.err.log";
      };
    };
  };
}
