{ pkgs, inputs, ... }:
{
  home.packages = [
    inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.opencode2
  ];

  # Default every OpenCode 2 session to DeepSeek V4.1 Flash through OpenRouter.
  # Authenticate the provider first with `opencode auth login openrouter`
  # (or `/login` inside a Kimaki channel).
  home.file.".config/opencode/opencode.json".text = builtins.toJSON {
    "$schema" = "https://opencode.ai/config.json";
    model = "openrouter/deepseek/deepseek-v4.1-flash";
  };
}
