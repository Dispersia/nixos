{
  pkgs,
  config,
  ...
}:
{
  home.packages = with pkgs; [
    neovim
  ];

  home.file.".config/nvim" = {
    source = ./config;
    recursive = true;
  };
}
