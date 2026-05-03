{ pkgs, config, ... }:
{
  imports = [
    ./carapace
    ./direnv
    ./nushell
    ./starship
  ];
}
