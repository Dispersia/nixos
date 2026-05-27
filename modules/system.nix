{
  pkgs,
  lib,
  hostName,
  username,
  ...
}:
let
  nrfconnect = pkgs.writeShellScriptBin "nrfconnect" ''
    SQUASHFS="$HOME/.local/share/nrfconnect/squashfs-root"
    NRFUTIL_DEVICE="$SQUASHFS/resources/app.asar.unpacked/resources/nrfutil-sandboxes/8.1.1/device/2.17.5/bin/nrfutil-device"

    if [ -f "$NRFUTIL_DEVICE" ] && ! ${pkgs.patchelf}/bin/patchelf --print-rpath "$NRFUTIL_DEVICE" 2>/dev/null | grep -q "current-system"; then
      ${pkgs.patchelf}/bin/patchelf --add-rpath /run/current-system/sw/lib "$NRFUTIL_DEVICE"
    fi

    export LD_LIBRARY_PATH="${lib.makeLibraryPath (with pkgs; [
      glib gtk3 nss nspr dbus.lib cups.lib libdrm gdk-pixbuf pango cairo
      libX11 libXcomposite libXdamage libXext libXfixes libXrandr
      libgbm expat libxcb libxkbcommon alsa-lib libglvnd systemd
    ])}:/run/current-system/sw/lib"

    export PATH="${pkgs.xdg-utils}/bin:$PATH"
    exec "$SQUASHFS/nrfconnect" --no-sandbox "$@"
  '';
in
{
  virtualisation.libvirtd.enable = true;

  programs.virt-manager.enable = true;

  programs.nix-ld.enable = true;

  programs.nix-ld.libraries = [
    pkgs.libidn2
  ];

  users.users.${username} = {
    isNormalUser = true;
    description = username;
    extraGroups = [
      "wheel"
      "networkmanager"
      "video"
      "kvm"
      "libvirtd"
      "adbusers"
    ];
    shell = pkgs.nushell;
  };

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  services.udev.packages = [
    pkgs.segger-jlink
    pkgs.nrf-udev
  ];

  system.activationScripts.jlinkSymlink = {
    text = ''
      mkdir -p /opt/SEGGER
      ln -sfn ${pkgs.segger-jlink}/opt/SEGGER/JLink /opt/SEGGER/JLink
    '';
  };

  environment.systemPackages = [ nrfconnect ];

  environment.sessionVariables = {
    GBM_BACKEND = "nvidia-drm";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
  };

  nix.settings.trusted-users = [ username ];

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];

    substituters = [
      "https://cache.nixos.org"
    ];

    builders-use-substitutes = true;
  };

  nix.gc = {
    automatic = lib.mkDefault true;
    dates = lib.mkDefault "weekly";
    options = lib.mkDefault " --delete-older-than 7d";
  };

  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.permittedInsecurePackages = [ "segger-jlink-qt4-874" ];
  nixpkgs.config.segger-jlink.acceptLicense = true;

  i18n.defaultLocale = "en_US.UTF-8";

  fonts = {
    packages = with pkgs; [
      material-design-icons

      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-color-emoji

      nerd-fonts.symbols-only
      nerd-fonts.fira-code
      nerd-fonts.jetbrains-mono
    ];

    fontconfig.defaultFonts = {
      serif = [
        "Noto Serif"
        "Noto Color Emoji"
      ];
      sansSerif = [
        "Noto Sans"
        "Noto Color Emoji"
      ];
      monospace = [
        "JetBrainsMono Nerd Font"
        "Noto Color Emoji"
      ];
      emoji = [ "Noto Color Emoji" ];
    };
  };

  services = {
    desktopManager.plasma6.enable = true;
    displayManager.sddm.enable = false;

    pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      jack.enable = true;
    };
  };

  time.timeZone = "America/Phoenix";

  #system.rebuild.flake = "/home/${username}/.config/nixos#${hostName}";
}
