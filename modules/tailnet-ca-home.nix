{ lib, pkgs, ... }:
lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
  home.packages = [ pkgs.nss.tools ];

  home.activation.tailnetCa = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ca=${./tailnet-ca.crt}
    nick="Caddy Local CA"

    add_cert() {
      db="$1"
      ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$db")"
      if [ ! -e "$db" ]; then
        ${pkgs.nss.tools}/bin/certutil -N --empty-password -d "sql:$db"
      fi
      if ! ${pkgs.nss.tools}/bin/certutil -d "sql:$db" -L -n "$nick" >/dev/null 2>&1; then
        ${pkgs.nss.tools}/bin/certutil -d "sql:$db" -A -t "C,," -n "$nick" -i "$ca"
      fi
    }

    add_cert "$HOME/.pki/nssdb"

    for prof in "$HOME"/.mozilla/firefox/*/; do
      [ -f "$prof/cert9.db" ] || continue
      add_cert "''${prof%/}"
    done
  '';
}
