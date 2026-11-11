#!/usr/bin/env bash
# Installs the Okta Verify payload from the vendor .deb into /opt/okta (run as root).
# The binaries are signature-checked, so they stay unpatched and run through nix-ld.
# Usage: sudo ./install-payload.sh /path/to/okta-verify-<version>-amd64.deb
set -euo pipefail

deb=${1:?usage: $0 <okta-verify.deb>}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

nix shell nixpkgs#binutils nixpkgs#xz -c bash -c "cd '$work' && ar x '$(readlink -f "$deb")' && tar xf data.tar.xz ./opt/okta"

systemctl stop okta-authenticator okta-feature-flag 2>/dev/null || true
rm -rf /opt/okta
install -d -m 0755 /opt
cp -a "$work/opt/okta" /opt/okta
chown -R root:root /opt/okta
systemctl start okta-feature-flag okta-authenticator 2>/dev/null || true
echo "Installed to /opt/okta"
