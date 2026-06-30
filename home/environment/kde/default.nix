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
      lookAndFeel = "org.kde.breezedark.desktop";
      theme = "breeze-dark";
      colorScheme = "TokyoNight";
    };
    configFile.kwinrc.Wayland.InputMethod.value =
      "/etc/profiles/per-user/${username}/share/applications/org.fcitx.Fcitx5.desktop";
    configFile.kded5rc = {
      "Module-gtkconfig"."autoload" = false;
    };
    configFile.plasmanotifyrc.Notifications.PopupTimeout.value = 2500;
    configFile.plasma-localerc = {
      Formats.LANG = "zh_TW.UTF-8";
      Translations.LANGUAGE = "zh_TW";
    };
  };

  gtk = {
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

  home.file.".local/share/color-schemes/TokyoNight.colors".source = ./TokyoNight.colors;

  home.packages = with pkgs; [
    kdePackages.breeze-icons
    kdePackages.kde-gtk-config
  ];

  home.sessionVariables = {
    QT_QPA_PLATFORMTHEME = "kde";
  };
}
