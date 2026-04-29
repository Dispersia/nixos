{ pkg, config, ... }:
{
  programs.google-cloud-sdk = {
    enable = true;
  };
}
