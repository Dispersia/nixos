{ pkgs, config, ... }:
{
  programs.git = {
    enable = true;
    lfs.enable = true;
    settings = {
      user = {
        name = "Aaron Housh";
        email = "dispersias@gmail.com";
      };
      push = {
        autoSetupRemote = true;
      };
      pull = {
        rebase = false;
      };
    };
  };
}
