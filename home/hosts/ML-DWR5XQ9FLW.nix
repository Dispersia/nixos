{ ... }:
{
  imports = [
    ../cli

    ../development/claude

    ../environment/gpg
  ];

  # Git + LFS only; this work Mac keeps its own commit identity instead of the
  # personal one set by ../development/git.
  programs.git = {
    enable = true;
    lfs.enable = true;
  };
}
