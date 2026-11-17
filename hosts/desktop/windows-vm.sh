#!/usr/bin/env bash
# Manage the "Windows on bare metal" VM: boots the physical Windows install
# from its own disk as a KVM guest. See windows-vm.nix for the full story.
#
# Windows must be FULLY shut down before `start` (in Windows, disable fast
# startup and hibernation with `powercfg /h off` as administrator) and none of
# its partitions may be mounted on the host, otherwise the NTFS volume is
# dirty and booting it in the VM risks corruption.
set -euo pipefail

DOMAIN="@DOMAIN@"
DOMAIN_XML="@DOMAIN_XML@"
WINDOWS_DISK="@WINDOWS_DISK@"
ESP_SOURCE="@ESP_SOURCE@"
ESP_IMAGE="@ESP_IMAGE@"
ESP_SIZE_MIB="@ESP_SIZE_MIB@"
VIRTIO_WIN_ISO="@VIRTIO_WIN_ISO@"

die() { printf 'windows-vm: %s\n' "$*" >&2; exit 1; }

virsh() { command virsh --connect qemu:///system "$@"; }

domain_state() {
  virsh domstate "$DOMAIN" 2>/dev/null || true
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    die "$1 needs root:  sudo windows-vm $1"
  fi
}

build_esp() {
  img="${ESP_IMAGE}.new"
  if [ ! -d "${ESP_SOURCE}/Boot" ]; then
    die "no Windows boot files at ${ESP_SOURCE}/Boot"
  fi

  rm -f "$img"
  trap 'rm -f "$img"' EXIT

  # 1 MiB gap before the partition (4K alignment, like a real ESP). The
  # FAT32 filesystem is created first and the GPT table last, so the backup
  # GPT does not land in the FAT data area.
  truncate -s "${ESP_SIZE_MIB}M" "$img"
  mkfs.fat -F 32 -n WINESP --offset=2048 "$img" >/dev/null

  # @@1048576 is the partition offset in bytes: mtools writes inside the
  # (not yet existing) partition. OVMF cannot boot a partition-less
  # "superfloppy" image ("No mapping" failure), hence the partition table.
  mmd -i "$img@@1048576" ::/EFI ::/EFI/BOOT
  mcopy -i "$img@@1048576" -s "$ESP_SOURCE" ::/EFI/
  # OVMF boots the removable-media fallback \EFI\BOOT\BOOTX64.EFI when the
  # VM's NVRAM has no boot entries; bootmgfw.efi wants its BCD store next to
  # itself, so keep a copy there too.
  mcopy -i "$img@@1048576" "$ESP_SOURCE/Boot/bootmgfw.efi" ::/EFI/BOOT/BOOTX64.EFI
  mcopy -i "$img@@1048576" "$ESP_SOURCE/Boot/BCD" ::/EFI/BOOT/BCD

  sgdisk --clear --new=1:2048:0 --typecode=1:ef00 --change-name=1:ESP "$img" >/dev/null

  mv -f "$img" "$ESP_IMAGE"
  trap - EXIT
  printf 'windows-vm: wrote %s (%s used)\n' "$ESP_IMAGE" "$(du -h "$ESP_IMAGE" | cut -f1)"
}

ensure_network() {
  if ! virsh net-info default >/dev/null 2>&1; then
    virsh net-define /dev/stdin <<'XML'
<network>
  <name>default</name>
  <forward mode='nat'/>
  <bridge name='virbr0' stp='on' delay='0'/>
  <ip address='192.168.122.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.122.2' end='192.168.122.254'/>
    </dhcp>
  </ip>
</network>
XML
  fi
  virsh net-autostart default >/dev/null
  virsh net-start default >/dev/null 2>&1 || true
}

cmd_setup() {
  require_root setup
  if [ "$(domain_state)" = running ]; then
    die "the VM is running; shut it down first (windows-vm stop)"
  fi

  if [ -f "$ESP_IMAGE" ]; then
    echo "windows-vm: keeping existing $ESP_IMAGE (refresh: sudo windows-vm sync-esp)"
  else
    build_esp
  fi

  ensure_network

  if virsh dominfo "$DOMAIN" >/dev/null 2>&1; then
    echo "windows-vm: domain '$DOMAIN' is already defined; to reset it from the repo:"
    echo "  virsh --connect qemu:///system destroy $DOMAIN  # only if running"
    echo "  virsh --connect qemu:///system define $DOMAIN_XML"
  else
    virsh define "$DOMAIN_XML"
  fi

  cat <<EOF

Next steps:
  1. In Windows (booted physically):  powercfg /h off   as administrator.
     This disables fast startup and hibernation, which is required before
     this VM may boot the disk.
  2. windows-vm start
  3. In the VM, install the guest drivers from the attached CD:
     $VIRTIO_WIN_ISO  (run virtio-win-guest-tools.exe)
EOF
}

cmd_sync_esp() {
  require_root sync-esp
  if [ "$(domain_state)" = running ]; then
    die "the VM is running; shut it down first (windows-vm stop)"
  fi
  build_esp
}

cmd_start() {
  mounts=$(lsblk -nro MOUNTPOINTS "$WINDOWS_DISK" 2>/dev/null | tr -d '[:space:]' || true)
  if [ -n "$mounts" ]; then
    die "partitions of $WINDOWS_DISK are mounted on the host; unmount them first"
  fi

  case "$(domain_state)" in
    running)
      echo "windows-vm: already running"
      return
      ;;
    "")
      die "domain '$DOMAIN' is not defined yet; run: sudo windows-vm setup"
      ;;
  esac

  virsh start "$DOMAIN"
  echo "windows-vm: starting; open the console with: virt-manager --connect qemu:///system"
}

cmd_stop() {
  case "$(domain_state)" in
    running)
      virsh shutdown "$DOMAIN"
      echo "windows-vm: graceful shutdown requested"
      echo "  (if Windows ignores it: virsh --connect qemu:///system destroy $DOMAIN)"
      ;;
    *)
      echo "windows-vm: not running"
      ;;
  esac
}

cmd_status() {
  printf 'domain:    %s\n' "$(domain_state)"
  if [ -f "$ESP_IMAGE" ]; then
    printf 'ESP image: %s (%s used, synced %s)\n' \
      "$ESP_IMAGE" \
      "$(du -h "$ESP_IMAGE" | cut -f1)" \
      "$(date -r "$ESP_IMAGE" '+%F %T')"
  else
    printf 'ESP image: missing (run: sudo windows-vm setup)\n'
  fi
  lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS "$WINDOWS_DISK"
}

usage() {
  cat <<'EOF'
Boot the physical Windows install in a KVM VM.

Usage: windows-vm <command>

Commands:
  setup      [root]  build the virtual ESP copy, define the libvirt domain
  sync-esp   [root]  refresh the ESP copy from /boot/EFI/Microsoft
  start              start the VM (Windows must be fully shut down)
  stop               request a graceful shutdown
  status             show domain state, ESP image and Windows disk mounts

setup/sync-esp need root. start/stop/status run as your user; that requires
one logout/login after the first `nixos-rebuild switch` (libvirtd group).
EOF
}

case "${1:-}" in
  setup) cmd_setup ;;
  sync-esp) cmd_sync_esp ;;
  start) cmd_start ;;
  stop) cmd_stop ;;
  status) cmd_status ;;
  help | "") usage ;;
  *)
    usage >&2
    exit 1
    ;;
esac
