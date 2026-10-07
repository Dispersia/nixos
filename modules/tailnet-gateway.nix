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
    optionalString
    types
    ;

  fqdn = name: "${name}.${cfg.domain}";
  scheme = if cfg.https then "https" else "http";
  tlsConfig = optionalString cfg.https "tls internal";

  # Optional browser-trusted name served with a Tailscale (Let's Encrypt)
  # certificate. Caddy recognizes *.ts.net hosts and fetches/renews the cert
  # from the local tailscaled daemon (see services.tailscale.permitCertUid),
  # so clients trust it without installing the internal CA.
  #
  # This site must bind the Tailscale address rather than 0.0.0.0: when it
  # shares a wildcard listener with the `tls internal` sites, the Caddyfile
  # adapter emits an explicit (public) automation policy for it, which disables
  # Caddy's built-in Tailscale handling and makes it try public ACME instead.
  hasTailscale = cfg.tailscaleHost != null;
  tailscaleSite = optionalString hasTailscale ''
    # Browser-trusted name with a Tailscale-issued certificate.
    https://${cfg.tailscaleHost} {
      bind ${cfg.address}
      reverse_proxy 127.0.0.1:${toString cfg.routes.${cfg.tailscaleRoute}.port}
    }
  '';

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
            mapAttrsToList (
              name: _: ''<li><a href="${scheme}://${fqdn name}/">${fqdn name}</a></li>''
            ) cfg.routes
          )}
        </ul>
      </body>
    </html>
  '';

  siteBlock = name: route: ''
    ${scheme}://${fqdn name} {
      bind ${cfg.listenAddress}
      ${tlsConfig}
      reverse_proxy 127.0.0.1:${toString route.port}
      ${route.extraConfig}
    }
  '';

  caRoot = "/var/lib/caddy/.local/share/caddy/pki/authorities/local";
in
{
  options.services.tailnetGateway = {
    enable = mkEnableOption "reverse proxy and wildcard DNS gateway for the tailnet and LAN";

    domain = mkOption {
      type = types.str;
      default = "home.arpa";
      description = "Internal DNS suffix. Routes are exposed as <name>.<domain>.";
    };

    address = mkOption {
      type = types.str;
      example = "100.84.150.49";
      description = "Tailscale IPv4 address of this host.";
    };

    dnsAddress = mkOption {
      type = types.str;
      default = cfg.address;
      defaultText = lib.literalExpression "config.services.tailnetGateway.address";
      example = "192.168.4.50";
      description = ''
        Address returned for <name>.<domain> and <domain>. Set this to the
        host's LAN address so clients on the same network connect directly
        instead of through Tailscale; advertise that address as a subnet route
        so off-LAN clients still reach it over the tailnet.
      '';
    };

    listenAddress = mkOption {
      type = types.str;
      default = cfg.address;
      defaultText = lib.literalExpression "config.services.tailnetGateway.address";
      description = "Address Caddy binds its listener to.";
    };

    httpPort = mkOption {
      type = types.port;
      default = 80;
      description = "Port Caddy listens on for HTTP.";
    };

    https = mkOption {
      type = types.bool;
      default = true;
      description = "Serve HTTPS with Caddy's internal CA; the CA root is served at http://ca.<domain>/root.crt.";
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
      description = "Services to expose as <name>.<domain>.";
    };

    tailscaleHost = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "home-server.tail1234.ts.net";
      description = ''
        Optional Tailscale MagicDNS name to serve with a public (Let's Encrypt)
        certificate. Caddy fetches that certificate from the local tailscaled
        daemon and renews it automatically, so clients trust the name without
        installing the internal CA. The route named by `tailscaleRoute` is
        reverse-proxied at the root of this name. HTTPS certificates must be
        enabled for the tailnet in the Tailscale admin console.
      '';
    };

    tailscaleRoute = mkOption {
      type = types.str;
      default = "jellyfin";
      description = ''
        Route from `routes` served at the root of `tailscaleHost`. Jellyfin
        needs to be at the root of a host, so this cannot be a path prefix.
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = !hasTailscale || builtins.hasAttr cfg.tailscaleRoute cfg.routes;
        message = "services.tailnetGateway.tailscaleRoute '${cfg.tailscaleRoute}' is not defined in services.tailnetGateway.routes.";
      }
    ];

    services.caddy = {
      enable = true;
      httpPort = cfg.httpPort;
      extraConfig = ''
        ${concatStringsSep "\n" (mapAttrsToList siteBlock cfg.routes)}

        ${tailscaleSite}

        ${scheme}://${cfg.domain}, ${scheme}://home.${cfg.domain} {
          bind ${cfg.listenAddress}
          ${tlsConfig}
          root * ${landing}
          file_server
        }

        http://ca.${cfg.domain} {
          bind ${cfg.listenAddress}
          root * ${caRoot}
          file_server
          header Content-Disposition "attachment; filename=root.crt"
        }
      '';
    };

    systemd.services.caddy = {
      wants = [ "tailscaled.service" ];
      after = [ "tailscaled.service" ];
    };

    # Let the caddy user fetch TLS certificates from the local tailscaled
    # daemon for the *.ts.net host above.
    services.tailscale.permitCertUid = mkIf hasTailscale "caddy";

    services.dnsmasq = {
      enable = true;
      resolveLocalQueries = false;
      settings = {
        address = [ "/${cfg.domain}/${cfg.dnsAddress}" ];
        "local-ttl" = 300;
        domain-needed = true;
        bogus-priv = true;
      };
    };
  };
}
