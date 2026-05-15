{ pkgs, config, ... }:
{
  programs.nushell = {
    enable = true;
    configFile.source = ./config.nu;
    envFile.source = ./env.nu;
    shellAliases = {
      vi = "nvim";
      vim = "nvim";
      nano = "nvim";
    };
    environmentVariables = {
      CLAUDE_CODE_USE_VERTEX = "1";
      CLOUD_ML_REGION = "us-east5";
      ANTHROPIC_VERTEX_PROJECT_ID = "crv-engineering-ai-prd-8058";
    };
  };
}
