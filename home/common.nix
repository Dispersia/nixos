{ pkgs, config, ... }: {
  home.packages = with pkgs; [
    vim
    git

    neofetch
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
  ];
}