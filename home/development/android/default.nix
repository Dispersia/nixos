{ pkgs, config, ... }:
{
  home.packages = with pkgs; [
    android-studio
  ];

  home.sessionVariables = {
    ANDROID_HOME = "${config.home.homeDirectory}/.android/sdk";
  };
}
