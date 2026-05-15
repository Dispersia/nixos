{ pkgs, config, ... }:
{
  imports = [
    ./development
    ./environment
    #./language
    ./shell
  ];

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
  ];

  programs.bash.enable = true;

  programs.gpg = {
    enable = true;

    mutableKeys = true;
    mutableTrust = true;
  };
}
