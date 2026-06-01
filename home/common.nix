{
  pkgs,
  config,
  inputs,
  ...
}:
{
  imports = [
    ./development
    ./environment
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

    gh

    inputs.b123d-server.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];

  programs.bash.enable = true;

  programs.gpg = {
    enable = true;

    mutableKeys = true;
    mutableTrust = true;
  };
}
