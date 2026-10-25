# Agent notes for this repo

## Nix: deprecated `stdenv` platform attributes

Never use the deprecated `stdenv` platform aliases:

- ❌ `stdenv.isLinux` / `stdenv.isDarwin`
- ❌ `pkgs.stdenv.isLinux` / `pkgs.stdenv.isDarwin` (and other `stdenv.is*` variants)

They emit evaluation warnings (`stdenv.isLinux is deprecated, use
stdenv.hostPlatform.isLinux instead`). Always use the `hostPlatform` forms:

- ✅ `stdenv.hostPlatform.isLinux` / `stdenv.hostPlatform.isDarwin`
- ✅ `pkgs.stdenv.hostPlatform.isLinux` / `pkgs.stdenv.hostPlatform.isDarwin`

To check a config evaluation is warning-free:

```sh
nix eval --abort-on-warn .#nixosConfigurations.desktop.config.system.build.toplevel.drvPath
```

## GlobalProtect

`hosts/desktop/default.nix` overrides `programs.globalprotect-openconnect.package`
with `pkgs/globalprotect-openconnect.nix`. The upstream flake
(`github:yuezk/GlobalProtect-openconnect`) evaluates deprecated `stdenv.is*`
attributes inside its own package set; overriding the package keeps the NixOS
module but prevents that code path from being evaluated. Do not remove the
override or let the module fall back to its default package, and keep the local
package copy free of deprecated attributes. When bumping the upstream input,
update `version` and the archive hashes in `pkgs/globalprotect-openconnect.nix`
to match the upstream `flake.nix`.
