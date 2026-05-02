{
  pkgs,
  config,
  ...
}:
{
  xdg.configFile.nvim = {
    source = ./config;
    recursive = true;
  };

  programs.neovim = {
    enable = true;
    extraConfig = ''
      :luafile ~/.config/nvim/init.lua
    '';
    viAlias = true;
    vimAlias = true;
    defaultEditor = true;
    plugins = with pkgs.vimPlugins; [
      nvim-treesitter.withAllGrammars
    ];
  };
}
