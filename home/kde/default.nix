{
  inputs,
  pkgs,
  config,
  username,
  ...
}:
{
  imports = [
    inputs.plasma-manager.homeModules.plasma-manager
  ];

  programs.plasma = {
    enable = true;
    workspace = {
      lookAndFeel = "org.kde.breeze.desktop";
      theme = "breeze-dark";
      colorScheme = "BreezeDark";
    };
    configFile.kwinrc.Wayland.InputMethod.value = "/etc/profiles/per-user/${username}/share/applications/org.fcitx.Fcitx5.desktop";
  };

  gtk = {
    enable = true;

    theme = {
      name = "Breeze-Dark";
      package = pkgs.kdePackages.breeze-gtk;
    };

    gtk3.extraConfig = {
      gtk-application-prefer-dark-theme = true;
    };

    gtk4.extraConfig = {
      gtk-application-prefer-dark-theme = true;
    };
  };

  qt = {
    enable = true;
    platformTheme.name = "kde";
    style.name = "breeze";
  };

  home.packages = with pkgs; [
    kdePackages.breeze-gtk
    kdePackages.breeze-icons
    kdePackages.kde-gtk-config
  ];

  home.sessionVariables = {
    QT_QPA_PLATFORMTHEME = "kde";
  };
}
