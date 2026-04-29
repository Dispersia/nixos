{ pkgs, config, ... }:
{
  home.packages = [ 
    pkgs.google-cloud-sdk
    pkgs.claude-code
  ];
}
