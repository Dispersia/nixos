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

    tree-sitter
  ];

  programs.bash.enable = true;
 
  programs.gpg = {
    enable = true;

    mutableKeys = true;
    mutableTrust = true;
  };

  services.gpg-agent = {
    enable = true;

    defaultCacheTtl = 3600;
    pinentry.package = pkgs.pinentry-qt;
  };
}
