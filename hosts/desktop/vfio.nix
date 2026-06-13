{
  config,
  pkgs,
  lib,
  ...
}:
let
  gpuHandoffHook = pkgs.writeShellScript "win11-gpu-handoff" ''
    guest="$1"
    op="$2"
    subop="$3"

    [ "$guest" = "win11" ] || exit 0

    systemctl="${pkgs.systemd}/bin/systemctl"

    # libvirt passes the full (expanded) domain XML on stdin for prepare/release.
    # Only tear the host display down if THIS domain actually passes the physical
    # 7900 (host 03:00.*) through. We must match the hostdev *source* address,
    # which libvirt renders as
    #     <address domain='0x0000' bus='0x03' slot='0x00' .../>
    # with NO `type='pci'`. Guest-assigned PCI addresses always start with
    # `<address type='pci' ...>`, and a plain Q35 install routinely lands a virtio
    # device on guest bus 0x03 slot 0x00 -- matching the bare `bus='0x03'
    # slot='0x00'` substring would fire mid-install (no passthrough yet) and kill
    # the desktop right after "create domain". Anchoring to `<address domain=`
    # disambiguates host source from guest addresses.
    xml="$(cat)"
    case "$xml" in
      *"<address domain='0x0000' bus='0x03' slot='0x00'"*) : ;;
      *) exit 0 ;;
    esac

    # The 7900 is boot_vga and drives the live desktop, so amdgpu won't release
    # it until the display-manager, the fb consoles, AND the boot framebuffer
    # (simple-framebuffer on this kernel, efi-framebuffer on older ones) are all
    # detached. managed='yes' then rebinds amdgpu <-> vfio-pci around the guest.
    if [ "$op" = "prepare" ] && [ "$subop" = "begin" ]; then
      "$systemctl" stop display-manager.service
      sleep 4
      for vtcon in /sys/class/vtconsole/vtcon*/bind; do
        echo 0 > "$vtcon" 2>/dev/null || true
      done
      echo efi-framebuffer.0 > /sys/bus/platform/drivers/efi-framebuffer/unbind 2>/dev/null || true
      echo simple-framebuffer.0 > /sys/bus/platform/drivers/simple-framebuffer/unbind 2>/dev/null || true
      # Belt-and-suspenders: drop amdgpu from the card explicitly so libvirt's
      # managed detach can't lose a race with a lingering host hold.
      for dev in 0000:03:00.0 0000:03:00.1; do
        echo "$dev" > /sys/bus/pci/devices/"$dev"/driver/unbind 2>/dev/null || true
      done
    fi

    # On release/end libvirt has already reattached amdgpu to the host, so we
    # just bring the consoles, framebuffer and login screen back.
    if [ "$op" = "release" ] && [ "$subop" = "end" ]; then
      echo efi-framebuffer.0 > /sys/bus/platform/drivers/efi-framebuffer/bind 2>/dev/null || true
      echo simple-framebuffer.0 > /sys/bus/platform/drivers/simple-framebuffer/bind 2>/dev/null || true
      for vtcon in /sys/class/vtconsole/vtcon*/bind; do
        echo 1 > "$vtcon" 2>/dev/null || true
      done
      "$systemctl" start display-manager.service
    fi
  '';
in
{
  boot.kernelParams = [
    "amd_iommu=on"
    "iommu=pt"
  ];

  # vfio modules must be available, but we do NOT bind the GPU ids at boot.
  # The card stays on amdgpu for normal desktop use; the VM's managed='yes'
  # hostdevs rebind amdgpu -> vfio-pci on `virsh start win11` and back on
  # shutdown, with gpuHandoffHook tearing down / restoring the desktop.
  boot.kernelModules = [
    "vfio_pci"
    "vfio"
    "vfio_iommu_type1"
  ];

  virtualisation.libvirtd = {
    qemu = {
      swtpm.enable = true;
      runAsRoot = true;
    };
    hooks.qemu.win11-gpu-handoff = gpuHandoffHook;
  };

  virtualisation.spiceUSBRedirection.enable = true;

  environment.systemPackages = with pkgs; [
    virtio-win
    looking-glass-client
    virt-viewer
  ];
}
