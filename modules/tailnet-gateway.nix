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
    mkEnableOption
    mkIf
    mkOption
    mapAttrsToList
    types
    ;

  fqdn = name: "${name}.${cfg.domain}";

  landing = pkgs.writeTextDir "index.html" ''
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>${cfg.domain}</title>
        <style>
          :root { color-scheme: light dark; }
          body { font: 16px/1.6 system-ui, sans-serif; max-width: 42rem; margin: 4rem auto; padding: 0 1.25rem; }
          h1 { font-size: 1.35rem; }
          ul { list-style: none; padding: 0; }
          li { margin: 0.35rem 0; }
          a { text-decoration: none; }
          a:hover { text-decoration: underline; }
        </style>
      </head>
      <body>
        <h1>${cfg.domain}</h1>
        <ul>
          ${concatStringsSep "\n          " (
            mapAttrsToList (name: _: ''<li><a href="http://${fqdn name}/">${fqdn name}</a></li>'') cfg.routes
          )}
        </ul>
      </body>
    </html>
  '';

  siteBlock = name: route: ''
    http://${fqdn name} {
      bind ${cfg.listenAddress}
      reverse_proxy 127.0.0.1:${toString route.port}
      ${route.extraConfig}
    }
  '';

in
{
  options.services.tailnetGateway = {
    enable = mkEnableOption "Tailscale-only reverse proxy and wildcard DNS gateway";

    domain = mkOption {
      type = types.str;
      default = "home.arpa";
      description = ''
        Internal DNS suffix. Each route is exposed as `<name>.<domain>` and
        resolves to {option}`services.tailnetGateway.address`.
      '';
    };

    address = mkOption {
      type = types.str;
      example = "100.84.150.49";
      description = "Tailscale IPv4 address of this host that DNS records point at.";
    };

    listenAddress = mkOption {
      type = types.str;
      default = cfg.address;
      defaultText = lib.literalExpression "config.services.tailnetGateway.address";
      description = "Address Caddy binds its HTTP listener to.";
    };

    httpPort = mkOption {
      type = types.port;
      default = 80;
      description = "Port Caddy listens on.";
    };

    routes = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            port = mkOption {
              type = types.port;
              description = "Local loopback port to reverse proxy to.";
            };
            extraConfig = mkOption {
              type = types.lines;
              default = "";
              description = "Extra Caddy directives for this site block.";
            };
          };
        }
      );
      default = { };
      example = lib.literalExpression ''
        {
          prowlarr = { port = 9696; };
          jellyfin = { port = 8096; };
        }
      '';
      description = "Services to expose as `<name>.<domain>`.";
    };
  };

  config = mkIf cfg.enable {
    services.caddy = {
      enable = true;
      httpPort = cfg.httpPort;
      extraConfig = ''
        http://${cfg.domain}, http://home.${cfg.domain} {
          bind ${cfg.listenAddress}
          root * ${landing}
          file_server
        }

        ${concatStringsSep "\n" (mapAttrsToList siteBlock cfg.routes)}
      '';
    };

    # Caddy binds the Tailscale address, so it must start after tailscaled has
    # assigned it.
    systemd.services.caddy = {
      wants = [ "tailscaled.service" ];
      after = [ "tailscaled.service" ];
    };

    # Wildcard DNS for the suffix: every name under it resolves to this host.
    # Clients are pointed here by a Tailscale Split DNS nameserver entry.
    services.dnsmasq = {
      enable = true;
      resolveLocalQueries = false;
      settings = {
        address = [ "/${cfg.domain}/${cfg.address}" ];
        domain-needed = true;
        bogus-priv = true;
      };
    };
  };
}
