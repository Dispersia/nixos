{ pkgs, config, ... }:
{
  programs.carapace = {
    enable = true;
    enableNushellIntegration = true;
  };
}
