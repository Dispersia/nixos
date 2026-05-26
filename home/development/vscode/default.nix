{ pkgs, config, inputs, ... }:
{
  programs.vscode = {
    enable = true;
    package = pkgs.vscode.fhs;
  };
}
