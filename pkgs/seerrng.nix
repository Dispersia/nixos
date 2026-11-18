# SeerrNG (<https://github.com/snapetech-org/seerrng>), a community fork of
# Seerr that also handles music, books, comics, ROMs and software requests.
#
# Upstream publishes a self-contained Linux x64 runtime archive containing the
# production `node_modules` plus the compiled Next.js (`.next`) and server
# (`dist`) output. Repacking that archive is deliberate: building the frontend
# from source would require vendoring both the pnpm store and the separate
# `lumen/` npm project into the sandbox, which upstream does not support.
#
# The archive's native addons (bcrypt, better-sqlite3, sharp, @swc/core,
# @next/swc) are built against glibc on the release runner, so `autoPatchelfHook`
# rewrites their interpreter and RPATH for NixOS. `--preserve-origin` keeps
# sharp's `$ORIGIN` RUNPATH intact so it still finds the bundled libvips.
#
# To bump: set `version` to the new release tag and recompute `src.hash` with
# `nix store prefetch-file --json <url>`.
{
  lib,
  stdenv,
  fetchurl,
  nodejs_24,
  makeWrapper,
  autoPatchelfHook,
  # Runtime C++ standard library for the bundled native addons.
  # (`libstdc++`/`libgcc_s` are the only non-glibc shared objects needed.)
}:

let
  version = "3.72.38";
in
stdenv.mkDerivation {
  pname = "seerrng";
  inherit version;

  src = fetchurl {
    url = "https://github.com/snapetech-org/seerrng/releases/download/v${version}/seerrng-v${version}-linux-x64.tar.gz";
    hash = "sha256-tRBGPFaVfk4jZ+XvSipMG6gdGbEBUUlShis8a6Yc788=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
    nodejs_24
  ];

  buildInputs = [ stdenv.cc.cc.lib ];

  # The addons link against the libvips shared object shipped in the same tree
  # (resolved through sharp's `$ORIGIN` RUNPATH, not a Nix library path), so it
  # is expected to look "missing" to autoPatchelf.
  autoPatchelfIgnoreMissingDeps = [ "*" ];
  autoPatchelfFlags = [ "--preserve-origin" ];

  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;

  # patchelf overwrites the initializer in upstream's libvips when growing its
  # ELF headers. Keep that library out of fixup, then copy it back from source.
  preFixup = ''
    vips=(node_modules/.pnpm/@img+sharp-libvips-linux-x64@*/node_modules/@img/sharp-libvips-linux-x64/lib/libvips-cpp.so.*)
    test "''${#vips[@]}" -eq 1 && test -f "$vips" || exit 1
    rm "$out/share/seerrng/$vips"
    restoreLibvips() { cp -p "$vips" "$out/share/seerrng/$vips"; }
    postFixupHooks+=(restoreLibvips)
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    (cd "$out/share/seerrng" && node -e 'require("sharp")({ create: { width: 1, height: 1, channels: 3, background: "red" } }).png().toBuffer().catch(e => { console.error(e); process.exitCode = 1; })')
    runHook postInstallCheck
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/seerrng
    cp -a ./. $out/share/seerrng/

    # Upstream's launchers assume a system `node`; replace them with a wrapper
    # pinned to the Node major version the release was built with.
    rm -f \
      $out/share/seerrng/start.sh \
      $out/share/seerrng/start.cmd \
      $out/share/seerrng/seerrng \
      $out/share/seerrng/seerrng.cmd

    makeWrapper ${nodejs_24}/bin/node $out/bin/seerrng \
      --add-flags "$out/share/seerrng/dist/index.js" \
      --chdir "$out/share/seerrng" \
      --set NODE_ENV production

    runHook postInstall
  '';

  meta = {
    description = "Fork of Seerr that also manages music, books, comics, ROMs and software requests";
    homepage = "https://github.com/snapetech-org/seerrng";
    license = lib.licenses.mit;
    mainProgram = "seerrng";
    platforms = [ "x86_64-linux" ];
  };
}
