{ username, ... }:
{
  home = {
    inherit username;

    stateVersion = "26.11";
  };

  programs.home-manager.enable = true;
}
