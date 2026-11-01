#!/usr/bin/env bash
# Copy the Windows BR/EDR link key for the "Audioengine ONE" headset into
# BlueZ's bond files, so the device keeps working on Linux after it has been
# re-paired on the Windows side of this dual-boot machine.
#
# Windows keeps link keys in the SYSTEM registry hive under
#   HKLM\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Keys\<adapter>\<device>
# and only lets SYSTEM read them. The headset only remembers one host, so it
# must be paired on Windows and Linux with the same adapter address and the
# same key; we key off whichever adapter it is bonded to locally.
#
# Runs as root, before bluetooth.service. It never fails the boot: if the
# Windows volume can't be read (locked, hibernated, absent), existing keys are
# left untouched.

set -u

device="01:29:B5:0A:13:BD"
device_hex=$(printf '%s' "$device" | tr -d ':' | tr 'A-Z' 'a-z')
bt_dir="/var/lib/bluetooth"

log() { echo "bluetooth-link-key-sync: $*"; }

# Read a "hex:8d,45,..." / "hex(3):8d,45,..." value named $1 from the regedit
# text on stdin and print it as 32 upper-case hex chars. Follows regedit
# line-continuations.
hex_of() {
  awk -v d="$1" '
    tolower($0) ~ ("^\"" d "\"=hex") { found = 1 }
    found { print; if ($0 !~ /\\$/) exit }' \
    | sed -E 's/^[^=]*=hex(\([0-9]+\))?://I' \
    | tr -dc '0-9A-Fa-f' \
    | tr 'a-f' 'A-F'
}

# Print the name of the hive's current control set (e.g. "ControlSet001").
current_cs() {
  hive="$1"
  line=$(hivexregedit --export "$hive" Select 2>/dev/null \
           | grep -iE '^"Current"=dword:' | head -n1)
  hex=$(printf '%s' "$line" | sed -E 's/.*=dword://I' | tr -d ' \r')
  [ -n "$hex" ] || return 1
  printf 'ControlSet%03d' "$((16#$hex))"
}

# Print the 32-char link key for $device_hex under adapter $2, else return 1.
read_key() {
  hive="$1"
  adapter_hex="$2"
  # Prefer the hive's current control set, then fall back to the usual ones.
  cur=$(current_cs "$hive" || true)
  for cs in $cur ControlSet001 ControlSet002 ControlSet003; do
    base="$cs\\Services\\BTHPORT\\Parameters\\Keys\\$adapter_hex"

    # Common layout: link key is a binary value named after the device MAC.
    out=$(hivexregedit --export "$hive" "$base" 2>/dev/null) || out=""
    key=$(printf '%s' "$out" | hex_of "$device_hex")
    if [ "${#key}" -eq 32 ]; then
      printf '%s' "$key"
      return 0
    fi

    # Alternative layout: a per-device subkey holding a "Key" value.
    out=$(hivexregedit --export "$hive" "$base\\$device_hex" 2>/dev/null) || out=""
    key=$(printf '%s' "$out" | hex_of key)
    if [ "${#key}" -eq 32 ]; then
      printf '%s' "$key"
      return 0
    fi
  done
  return 1
}

# Mount the first NTFS volume that holds a Windows SYSTEM hive, print its
# mount point, or return 1.
find_windows() {
  for dev in /dev/disk/by-uuid/*; do
    [ -e "$dev" ] || continue
    [ "$(blkid -s TYPE -o value "$dev" 2>/dev/null)" = ntfs ] || continue

    mnt=$(mktemp -d)
    # ntfs3 is in-kernel; ntfs-3g (FUSE) is the fallback and can read a
    # hibernated/dirty volume read-only thanks to `force`.
    if mount -t ntfs3 -o ro "$dev" "$mnt" 2>/dev/null \
      || ntfs-3g -o ro,force "$dev" "$mnt" 2>/dev/null; then
      if [ -f "$mnt/Windows/System32/config/SYSTEM" ]; then
        printf '%s' "$mnt"
        return 0
      fi
      umount "$mnt" 2>/dev/null || true
    fi
    rmdir "$mnt" 2>/dev/null || true
  done
  return 1
}

if ! mnt=$(find_windows); then
  log "no Windows SYSTEM hive found; leaving keys unchanged"
  exit 0
fi
hive="$mnt/Windows/System32/config/SYSTEM"

applied=0
for info in "$bt_dir"/*/"$device"/info; do
  [ -f "$info" ] || continue
  adapter=$(basename "$(dirname "$(dirname "$info")")")
  adapter_hex=$(printf '%s' "$adapter" | tr -d ':' | tr 'A-Z' 'a-z')

  if key=$(read_key "$hive" "$adapter_hex"); then
    log "applying Windows link key $key to adapter $adapter"
    sed -i "s/^Key=.*/Key=$key/" "$info"
    applied=$((applied + 1))
  else
    log "no Windows link key for adapter $adapter; leaving it unchanged"
  fi
done

umount "$mnt" 2>/dev/null || true
rmdir "$mnt" 2>/dev/null || true
log "done; updated $applied bond(s)"
