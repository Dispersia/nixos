{ pkgs, ... }:
{
  programs.obsidian = {
    enable = true;

    vaults.notes.target = "Documents/Obsidian";

    defaultSettings = {
      communityPlugins = with pkgs.obsidianPlugins; [
        tasknotes
        halyard-sync
      ];
    };
  };
}
