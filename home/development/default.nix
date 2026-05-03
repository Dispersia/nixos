{ pkgs, config, ... }:
{
  imports = [
    ./android
    ./claude
    ./git
    ./kicad
    ./neovim
    ./postman
    ./vscode
  ];
}
