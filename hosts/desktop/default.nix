{
  config,
  pkgs,
  lib,
  hostName,
  inputs,
  username,
  ...
}:
{
  imports = [
    ../../modules/system.nix
    ../../modules/comin.nix
    ../../modules/comfyui.nix
    ../../modules/forge-neo.nix
    ../../modules/nordvpn.nix
    ../../modules/tailscale.nix
    ../../modules/printing.nix
    ../../modules/diagnostics.nix

    inputs.globalprotect-openconnect.nixosModules.default

    ./hardware-configuration.nix
  ];

  programs.globalprotect-openconnect.enable = true;

  # Override the module's default package: the upstream flake's package set
  # evaluates deprecated `stdenv.isLinux`/`stdenv.isDarwin` attributes and
  # spams evaluation warnings. This local copy uses `stdenv.hostPlatform.*`.
  programs.globalprotect-openconnect.package =
    pkgs.callPackage ../../pkgs/globalprotect-openconnect.nix
      {
        relocateScript = "${inputs.globalprotect-openconnect}/scripts/relocate-install-paths.sh";
      };

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  boot.kernelPackages = pkgs.linuxPackages_latest;

  services.displayManager.sddm = {
    enable = lib.mkForce true;
    wayland.enable = true;
  };

  # Image generation on the 7900 XT. The first start installs ROCm torch and
  # the rest of the requirements into ~/ComfyUI/venv (several GB); after that,
  # models go in ~/ComfyUI/models/<type>/ and custom nodes in
  # ~/ComfyUI/custom_nodes/. Bound to the tailnet address so home-server's
  # Caddy can reach it; it is published as https://comfy.home.arpa/.
  services.comfyuiUv = {
    enable = true;
    user = username;
    # Tailnet address for the home-server gateway, loopback for local use.
    listenAddress = "100.79.114.61,127.0.0.1";
  };

  # Forge Neo (the A1111-style WebUI the Mac mini runs) beside ComfyUI, sharing
  # ComfyUI's model folders: checkpoints, LoRAs, embeddings, VAEs and upscalers
  # are symlinked, so both UIs see the same files. `listen` binds 0.0.0.0;
  # the firewall keeps the LAN out and allows the tailnet.
  services.forge-neo = {
    enable = true;
    user = username;
    listen = true;
    sharedModelsDir = "${config.services.comfyuiUv.dataDir}/models";
  };

  networking.hostName = hostName;
  networking.networkmanager.enable = true;
  networking.firewall.allowedTCPPorts = [
    3724
    8085
  ];

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = true;
      PermitRootLogin = "no";
    };
  };

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  systemd.services.bluetooth-link-key-sync = {
    description = "Sync BR/EDR link key with Windows dual-boot";
    before = [ "bluetooth.service" ];
    wantedBy = [ "bluetooth.service" ];
    serviceConfig.Type = "oneshot";
    script = ''
      info="/var/lib/bluetooth/00:1A:7D:DA:71:15/01:29:B5:0A:13:BD/info"
      [ -f "$info" ] || exit 0
      ${pkgs.gnused}/bin/sed -i 's/^Key=.*/Key=8D45FD33B5A7B9B60638BC91B6D038FC/' "$info"
    '';
  };

  system.stateVersion = "26.11";
}
