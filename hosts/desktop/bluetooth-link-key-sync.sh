#!/usr/bin/env bash
# Copy the Windows BR/EDR link key for the "Audioengine ONE" headset into
# BlueZ's info file, so the device keeps working on Linux after it has been
# re-paired on the Windows side of this dual-boot machine.
#
# Windows keeps link keys in the SYSTEM registry hive under
#   HKLM\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Keys\<adapter>\<device>
# and only lets SYSTEM read them. Both OSes use the same physical adapter, so
# the device only authenticates when both sides hold the same link key.
#
# Runs as root, before bluetooth.service. It never fails the boot: if the
# Windows volume can't be read (locked, hibernated, absent), the existing key
# in BlueZ's info file is left untouched.

set -u

adapter="00:1A:7D:DA:71:15"
device="01:29:B5:0A:13:BD"
adapter_hex=$(printf '%s' "$adapter" | tr -d ':' | tr 'A-Z' 'a-z')
device_hex=$(printf '%s' "$device" | tr -d ':' | tr 'A-Z' 'a-z')
info="/var/lib/bluetooth/$adapter/$device/info"

log() { echo "bluetooth-link-key-sync: $*"; }

if [ ! -f "$info" ]; then
  log "$info not found (device not paired on this adapter yet); skipping"
  exit 0
fi

# Read a "hex:8d,45,..." value named $1 from the regedit text on stdin and
# print it as 32 upper-case hex chars. Follows regedit line-continuations.
hex_of() {
  awk -v d="$1" '
    tolower($0) ~ ("^\"" d "\"=hex:") { found = 1 }
    found { print; if ($0 !~ /\\$/) exit }' \
    | sed -E 's/^[^=]*=hex://I' \
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

# Print the 32-char link key for $device_hex out of a SYSTEM hive, else return 1.
read_key() {
  hive="$1"
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

newkey=""
for dev in /dev/disk/by-uuid/*; do
  [ -e "$dev" ] || continue
  [ "$(blkid -s TYPE -o value "$dev" 2>/dev/null)" = ntfs ] || continue

  mnt=$(mktemp -d)
  # ntfs3 is in-kernel; ntfs-3g (FUSE) is the fallback and can read a
  # hibernated/dirty volume read-only thanks to `force`.
  if mount -t ntfs3 -o ro "$dev" "$mnt" 2>/dev/null \
    || ntfs-3g -o ro,force "$dev" "$mnt" 2>/dev/null; then
    hive="$mnt/Windows/System32/config/SYSTEM"
    if [ -f "$hive" ] && newkey=$(read_key "$hive"); then
      umount "$mnt" 2>/dev/null || true
      rmdir "$mnt" 2>/dev/null || true
      break
    fi
    umount "$mnt" 2>/dev/null || true
  fi
  rmdir "$mnt" 2>/dev/null || true
  newkey=""
done

if [ -n "$newkey" ]; then
  log "applying Windows link key $newkey to $info"
  sed -i "s/^Key=.*/Key=$newkey/" "$info"
else
  log "no Windows link key found; leaving $info unchanged"
fi
