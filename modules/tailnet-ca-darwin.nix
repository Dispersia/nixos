{ ... }:
let
  ca = ./tailnet-ca.crt;
  nickname = "Caddy Local Authority - 2026 ECC Root";
in
{
  security.pki.certificateFiles = [ ca ];

  system.activationScripts.tailnetCa.text = ''
    if ! /usr/bin/security find-certificate -c "${nickname}" /Library/Keychains/System.keychain >/dev/null 2>&1; then
      /usr/bin/security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ${ca}
    fi
  '';
}
