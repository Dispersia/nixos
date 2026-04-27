{ pkgs, config, ... }: {
  home.packages = [
    pkgs.vim
    pkgs.git

    pkgs.neofetch
    pkgs.nnn

    pkgs.zip
    pkgs.xz
    pkgs.unzip

    pkgs.ripgrep
    pkgs.jq
    pkgs.fzf
    pkgs.eza

    pkgs.file
    pkgs.which
    pkgs.tree
    pkgs.zstd

    pkgs.btop

    pkgs.lsof
  ];
}