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
