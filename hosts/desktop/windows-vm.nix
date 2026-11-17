{
  lib,
  pkgs,
  username,
  ...
}:
# Boot the bare-metal Windows install (its own NVMe disk) as a KVM guest.
#
# Windows shares the EFI system partition with NixOS: its boot files live on
# the NixOS disk (/boot/EFI/Microsoft, next to systemd-boot) and the Windows
# disk itself only holds MSR + C: + WinRE. The VM therefore gets
#   - a small virtual *copy* of that ESP (rebuilt by `windows-vm sync-esp`),
#   - the whole Windows disk as a raw block device (the BCD references C: by
#     GPT partition GUID, so the whole disk must be passed through),
# and never sees the NixOS disk.
#
# Usage:
#   sudo nixos-rebuild switch --flake .#desktop  # once; then log out/in once
#                                                # for the libvirtd group
#   sudo windows-vm setup                        # build ESP copy, define VM
#   windows-vm start                             # boot Windows in the VM
#   windows-vm stop                              # graceful shutdown
#   sudo windows-vm sync-esp                     # after Windows boot updates
#
# Windows side: disable fast startup/hibernation (`powercfg /h off` as
# administrator) and always fully shut down before starting the VM; otherwise
# the NTFS volume is dirty and booting it in the VM risks corruption.
let
  # Physical Windows disk: whole-disk passthrough via its stable id.
  windowsDisk = "/dev/disk/by-id/nvme-AGAMMIXS70B-1T-CS_2N172L1AQBLJ";

  # Virtual ESP image (GPT + one FAT32 ESP partition), built from
  # /boot/EFI/Microsoft. OVMF cannot boot a partition-less "superfloppy"
  # image ("No mapping" failure), hence the partition table.
  espImage = "/var/lib/libvirt/images/windows-esp.img";
  espSource = "/boot/EFI/Microsoft";
  espSizeMiB = 256;

  domainName = "windows-physical";

  # Original virtio-win ISO (the fetchurl source of pkgs.virtio-win),
  # attached to the VM as a CD-ROM for guest drivers/tools.
  virtioWinIso = pkgs.virtio-win.src;

  domainXml = pkgs.writeText "${domainName}-domain.xml" (
    lib.replaceStrings
      [ "@WINDOWS_DISK@" "@ESP_IMAGE@" "@VIRTIO_WIN_ISO@" ]
      [ windowsDisk espImage (toString virtioWinIso) ]
      (builtins.readFile ./windows-vm-domain.xml)
  );

  windowsVm = pkgs.writeShellApplication {
    name = "windows-vm";
    runtimeInputs = with pkgs; [
      coreutils
      dosfstools
      gptfdisk
      libvirt
      mtools
      util-linux
    ];
    text =
      lib.replaceStrings
        [
          "@DOMAIN@"
          "@DOMAIN_XML@"
          "@WINDOWS_DISK@"
          "@ESP_SOURCE@"
          "@ESP_IMAGE@"
          "@ESP_SIZE_MIB@"
          "@VIRTIO_WIN_ISO@"
        ]
        [
          domainName
          (toString domainXml)
          windowsDisk
          espSource
          espImage
          (toString espSizeMiB)
          (toString virtioWinIso)
        ]
        (builtins.readFile ./windows-vm.sh);
  };
in
{
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      # Host-architecture-only QEMU build (smaller closure; still has
      # SPICE + USB redirection).
      package = pkgs.qemu_kvm;
      # Let the emulator process open /dev/nvme0n1 for the raw disk
      # passthrough; the qemu-libvirtd user cannot read it otherwise.
      runAsRoot = true;
      # Emulated TPM 2.0 for the VM (Windows 11 requirement; harmless
      # otherwise).
      swtpm.enable = true;
    };
  };

  programs.virt-manager.enable = true;
  # USB redirection into the VM (redirdev/spicevmc in the domain XML).
  virtualisation.spiceUSBRedirection.enable = true;

  users.users.${username}.extraGroups = [ "libvirtd" ];

  environment.systemPackages = [
    windowsVm
  ];
}
