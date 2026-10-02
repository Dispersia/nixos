{
  config,
  pkgs,
  hostName,
  username,
  ...
}:
{
  imports = [
    ../../modules/darwin-system.nix
    ../../modules/comin-darwin.nix
    ../../modules/yomifin-ocr.nix
  ];

  services.yomifin.ocr = {
    enable = true;
    user = username;
    # Reachable from the home server over the LAN (en0). Keep this in sync with
    # the Jellyfin YomiFin plugin's OcrSidecarUrl; use a DHCP reservation so it
    # does not drift.
    host = "192.168.4.37";
    authTokenFile = "/Users/dispe/.config/yomifin-ocr/token";
    engines = [
      "yomitoku"
      "paddleocr"
    ];
  };

  services.tailscale.enable = true;

  users.knownUsers = [ "${username}" ];
  users.users.${username} = {
    home = "/Users/${username}";
    uid = 501;
    shell = pkgs.nushell;
  };

  system.primaryUser = username;

  homebrew.enable = false;

  system.stateVersion = 6;
}
