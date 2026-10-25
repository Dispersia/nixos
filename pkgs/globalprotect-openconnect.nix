# Copy of the `prebuilt` package from the upstream flake
# (github:yuezk/GlobalProtect-openconnect), with the deprecated
# `stdenv.isLinux` / `stdenv.isDarwin` attributes replaced by
# `stdenv.hostPlatform.*` so evaluation stays warning-free.
#
# The upstream NixOS module is still used (see hosts/desktop/default.nix),
# but its `package` option is overridden with this derivation. Otherwise the
# module's default would force the upstream flake's package set, which is
# where the deprecation warnings come from.
#
# When updating to a new upstream release, bump `version` and the archive
# hashes below (they match the ones in the upstream flake.nix).
{
  lib,
  stdenv,
  fetchurl,
  libarchive,
  runCommand,
  autoPatchelfHook,
  wrapGAppsHook4,
  # Linux build dependencies
  libxml2,
  zlib,
  openssl,
  lz4,
  gnutls,
  p11-kit,
  nettle,
  gmp,
  glib,
  gtk3,
  libsoup_3,
  webkitgtk_4_1,
  glib-networking,
  libsecret,
  libayatana-appindicator,
  # Runtime tools
  coreutils,
  iproute2,
  systemd,
  procps,
  util-linux,
  nettools,
  xdg-utils,
  relocateScript,
}:
let
  pname = "globalprotect-openconnect";
  version = "3.2.0";
  releaseTag = "v${version}";
  cpu = stdenv.hostPlatform.parsed.cpu.name;

  gpguiHashes = {
    x86_64 = "sha256-Y0MbRebzQCPjvXUyWF8grBxGPuvDhIlnvEoEkFl5WMI=";
    aarch64 = "sha256-TnQPKllHSRfl/ir6PYZE6dVb8XUtayg7CRZUkWE4jsw=";
  };

  binaryHashes = {
    x86_64 = "sha256-3SvFEL9C8uB+ekp/PygBw0k8vZwdbnBWnvBcfGN8e1A=";
    aarch64 = "sha256-3lVKM1lnYQsgAboBCRuzEOFY/uB8+lf+yrxIRJJZtV4=";
  };

  unpackReleaseAsset =
    { name, archive }:
    runCommand name { nativeBuildInputs = [ libarchive ]; } ''
      mkdir -p "$out"
      bsdtar --extract --file ${archive} --directory "$out" --strip-components 1
    '';

  gpgui = unpackReleaseAsset {
    name = "gpgui-${version}-${cpu}";
    archive = fetchurl {
      url = "https://github.com/yuezk/GlobalProtect-openconnect/releases/download/${releaseTag}/gpgui_${cpu}.bin.tar.xz";
      hash = gpguiHashes.${cpu};
    };
  };

  binaryPackage = unpackReleaseAsset {
    name = "${pname}-${version}-${cpu}-binary";
    archive = fetchurl {
      url = "https://github.com/yuezk/GlobalProtect-openconnect/releases/download/${releaseTag}/${pname}_${version}_${cpu}.bin.tar.xz";
      hash = binaryHashes.${cpu};
    };
  };

  linuxRuntimeDependencies = [
    glib-networking
    libayatana-appindicator
    xdg-utils
  ];

  runtimeTools = [
    coreutils
    iproute2
    systemd
    procps
    util-linux
    nettools
    xdg-utils
  ];

  nativeRuntimeWrapping = lib.optionalString stdenv.hostPlatform.isLinux ''
    gappsWrapperArgs+=(
      --prefix PATH : "/run/wrappers/bin:${lib.makeBinPath runtimeTools}"
      --set GP_COMMAND_PATH "${lib.makeBinPath runtimeTools}"
      --set-default GP_VPNC_SCRIPT "$out/libexec/gpclient/vpnc-script"
      --set-default GP_CLIENT_BINARY "$out/bin/gpclient"
      --set-default GP_SERVICE_BINARY "$out/bin/gpservice"
      --set-default GP_AUTH_BINARY "$out/bin/gpauth"
      --set-default GP_GUI_BINARY "$out/bin/gpgui"
      --set-default GP_GUI_HELPER_BINARY "$out/bin/gpgui-helper"
      --set-default GP_VPNC_SCRIPT_INSTALLER_BINARY "$out/libexec/gpclient/gp-vpnc-script-installer"
      --set-default GP_HIP_SCRIPT_INSTALLER_BINARY "$out/libexec/gpclient/gp-hip-script-installer"
    )
  '';

  rewriteVpncScriptToolPaths = lib.optionalString stdenv.hostPlatform.isLinux ''
    substituteInPlace $out/libexec/gpclient/vpnc-script \
      --replace-fail /usr/bin/resolvectl ${systemd}/bin/resolvectl \
      --replace-fail /usr/bin/busctl ${systemd}/bin/busctl
  '';

  linuxBuildInputs = [
    libxml2
    zlib
    openssl
    lz4
    gnutls
    p11-kit
    nettle
    gmp
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    glib
    gtk3
    libsoup_3
    webkitgtk_4_1
    glib-networking
    libsecret
    libayatana-appindicator
  ];

  installNixosPolkitRule = ''
    chmod u+w $out/share $out/share/polkit-1 2>/dev/null || true
    install -d $out/share/polkit-1/rules.d
    cat > $out/share/polkit-1/rules.d/49-gpgui.rules <<EOF
    polkit.addRule(function(action, subject) {
      if (
        action.id == "org.freedesktop.policykit.exec" &&
        action.lookup("program") == "$out/bin/gpservice" &&
        subject.active
      ) {
        return polkit.Result.YES;
      }
    });
    EOF
  '';
in
stdenv.mkDerivation {
  inherit pname version;

  src = binaryPackage;
  dontBuild = true;

  nativeBuildInputs = [
    autoPatchelfHook
    wrapGAppsHook4
  ];

  buildInputs = linuxBuildInputs;
  # Kept for parity with upstream; consumed by naersk in `fromSource`, inert here.
  runtimeDependencies = linuxRuntimeDependencies;
  preFixup = nativeRuntimeWrapping;

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp -r artifacts/usr/bin $out/bin
    cp -r artifacts/usr/libexec $out/libexec
    cp -r artifacts/usr/share $out/share

    if [ -d artifacts/usr/lib ]; then
      cp -r artifacts/usr/lib $out/lib
    fi

    install -Dm755 ${gpgui}/gpgui $out/bin/gpgui

    ${rewriteVpncScriptToolPaths}
    sh ${relocateScript} "$out" /usr "$out"
    ${installNixosPolkitRule}

    runHook postInstall
  '';
}
