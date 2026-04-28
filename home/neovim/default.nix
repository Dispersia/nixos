{
  inputs,
  pkgs,
  config,
  ...
}:
let
  unstable = import inputs.nixpkgs-unstable {
    system = pkgs.stdenv.hostPlatform.system;
  };
in
{
  home.packages = [
    unstable.neovim
  ];

  home.file.".config/nvim" = {
    source = ./config;
    recursive = true;
  };
}
