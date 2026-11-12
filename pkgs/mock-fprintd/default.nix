{
  lib,
  stdenv,
  python3,
  makeWrapper,
  glib,
  gobject-introspection,
}:

# A mock ``fprintd``: a D-Bus service exposing the ``net.reactivated.Fprint``
# API that always reports a matching fingerprint. Intended for testing services
# that consume biometric authentication (PAM, desktop shells, ...). It is not a
# real fingerprint daemon and provides no security whatsoever.
let
  python = python3.withPackages (ps: [ ps.pygobject3 ]);

  # Where PyGObject finds the GObject Introspection typelibs for Gio/GLib.
  typelibPath = lib.makeSearchPath "lib/girepository-1.0" [
    glib
    gobject-introspection
  ];
in
stdenv.mkDerivation (finalAttrs: {
  pname = "mock-fprintd";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 mock-fprintd.py \
      "$out/libexec/mock-fprintd/mock-fprintd.py"

    makeWrapper ${python}/bin/python3 "$out/bin/mock-fprintd" \
      --add-flags "$out/libexec/mock-fprintd/mock-fprintd.py" \
      --prefix GI_TYPELIB_PATH : "${typelibPath}"

    install -Dm644 net.reactivated.Fprint.conf \
      "$out/share/dbus-1/system.d/net.reactivated.Fprint.conf"

    install -d "$out/share/dbus-1/system-services"
    substitute net.reactivated.Fprint.service.in \
      "$out/share/dbus-1/system-services/net.reactivated.Fprint.service" \
      --subst-var-by exec "$out/bin/mock-fprintd"

    runHook postInstall
  '';

  meta = {
    description = "Mock fprintd D-Bus service that always reports a fingerprint match";
    longDescription = ''
      Implements the net.reactivated.Fprint D-Bus API and always succeeds at
      fingerprint verification. For testing services that use biometric
      authentication. This disables real biometric security wherever it is
      used.
    '';
    license = lib.licenses.mit;
    mainProgram = "mock-fprintd";
    platforms = lib.platforms.linux;
  };
})
