{ pkgs, ... }:
{
  home.packages = with pkgs; [
    vim
    git

    nnn

    zip
    xz
    unzip

    ripgrep
    jq
    fzf
    eza

    file
    which
    tree
    zstd

    btop

    lsof

    gh

    unrar
  ];

  programs.bash.enable = true;
}
