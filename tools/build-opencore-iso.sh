#!/usr/bin/env bash
#
# Rebuild EFI/opencore-osx-proxmox-vm.iso with pinned OpenCore + kext versions.
#
# Produces the same 96 MiB MBR-partitioned image the repo has always shipped:
#   - MBR with a single FAT32 partition starting at LBA 1 (offset 512)
#   - FAT32 volume contains /EFI/BOOT/BOOTx64.efi, /EFI/OC/... and the
#     install-EFI-for-*.pkg + SOURCE/ + UTILS/ helpers preserved from the
#     previous ISO.
#
# Why this exists: OpenCore 1.0.5 was the first release with macOS Tahoe
# (Darwin 26) kext-injection fixes, and 1.0.7 added XhciPortLimit
# compatibility. Keep the bundled image synced with upstream so users don't
# hit injection panics on Tahoe installs. Also installs RestrictEvents +
# NVMeFix, caps WhateverGreen below Tahoe, and applies the hv_vmm_present
# VMM-mask kernel patch (see tools/patch_config.py) so Apple ID/iMessage/
# FaceTime work under KVM.
#
# Requirements on the build host: bash, curl, unzip, xmlstarlet, mtools,
# dosfstools, python3 (for plistlib).
#
# Usage:
#   sudo ./tools/build-opencore-iso.sh                # rebuild in place
#   OC_VERSION=1.0.7 LILU_VERSION=1.7.2 ./tools/build-opencore-iso.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_ISO="${OUT_ISO:-$REPO_DIR/EFI/opencore-osx-proxmox-vm.iso}"

OC_VERSION="${OC_VERSION:-1.0.7}"
LILU_VERSION="${LILU_VERSION:-1.7.2}"
VIRTUALSMC_VERSION="${VIRTUALSMC_VERSION:-1.3.7}"
WHATEVERGREEN_VERSION="${WHATEVERGREEN_VERSION:-1.7.0}"
RESTRICTEVENTS_VERSION="${RESTRICTEVENTS_VERSION:-1.1.6}"
NVMEFIX_VERSION="${NVMEFIX_VERSION:-1.1.3}"
# Downloaded so operators can opt in via config.plist when building custom
# images, but not installed into Kexts/ by default (AppleALC needs a codec
# layout ID nothing here can guess, and virtio disks have no analog audio).
APPLEALC_VERSION="${APPLEALC_VERSION:-1.9.7}"

IMAGE_SIZE_MIB="${IMAGE_SIZE_MIB:-96}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }; }
need curl; need unzip; need xmlstarlet; need python3
need mformat; need mcopy; need mdir; need mkfs.vfat

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

DL="$WORK/dl"; STAGE="$WORK/stage"; SRC="$WORK/src-iso"
mkdir -p "$DL" "$STAGE" "$SRC"

# --- 1. Extract the existing ISO so we preserve helpers/themes/ACPI/drivers -

if [[ ! -f "$OUT_ISO" ]]; then
  echo "Source ISO missing: $OUT_ISO" >&2; exit 1
fi

cat > "$WORK/mtoolsrc" <<EOF
drive x: file="$OUT_ISO" offset=512
EOF
export MTOOLSRC="$WORK/mtoolsrc" MTOOLS_SKIP_CHECK=1

echo "[1/7] Extracting existing ISO for reuse..."
mcopy -s -n x:/EFI "$SRC/" >/dev/null
mcopy -s -n x:/SOURCE "$SRC/" >/dev/null || true
mcopy -s -n x:/UTILS  "$SRC/" >/dev/null || true
# Top-level .pkg helpers (install-EFI-for-*).
for f in install-EFI-for-AMD-5000-6000-series.pkg \
         install-EFI-for-Native-GPUs-PIKERA-OFF.pkg \
         install-EFI-for-Nvidia-on-High-Sierra.pkg \
         install-EFI-for-Virtual-Machine-Only.pkg; do
  mcopy -n "x:/$f" "$SRC/$f" >/dev/null || true
done

# --- 2. Download OpenCore + kexts ------------------------------------------

fetch() {
  local url="$1" dest="$2"
  [[ -f "$dest" ]] && return 0
  echo "  fetching $(basename "$dest")"
  curl -fsSL --retry 4 --retry-delay 2 -o "$dest" "$url"
}

echo "[2/7] Downloading OpenCore $OC_VERSION + kexts..."
fetch "https://github.com/acidanthera/OpenCorePkg/releases/download/${OC_VERSION}/OpenCore-${OC_VERSION}-RELEASE.zip"               "$DL/OpenCore.zip"
fetch "https://github.com/acidanthera/Lilu/releases/download/${LILU_VERSION}/Lilu-${LILU_VERSION}-RELEASE.zip"                       "$DL/Lilu.zip"
fetch "https://github.com/acidanthera/VirtualSMC/releases/download/${VIRTUALSMC_VERSION}/VirtualSMC-${VIRTUALSMC_VERSION}-RELEASE.zip" "$DL/VirtualSMC.zip"
fetch "https://github.com/acidanthera/WhateverGreen/releases/download/${WHATEVERGREEN_VERSION}/WhateverGreen-${WHATEVERGREEN_VERSION}-RELEASE.zip" "$DL/WhateverGreen.zip"
fetch "https://github.com/acidanthera/AppleALC/releases/download/${APPLEALC_VERSION}/AppleALC-${APPLEALC_VERSION}-RELEASE.zip"       "$DL/AppleALC.zip"
fetch "https://github.com/acidanthera/RestrictEvents/releases/download/${RESTRICTEVENTS_VERSION}/RestrictEvents-${RESTRICTEVENTS_VERSION}-RELEASE.zip" "$DL/RestrictEvents.zip"
fetch "https://github.com/acidanthera/NVMeFix/releases/download/${NVMEFIX_VERSION}/NVMeFix-${NVMEFIX_VERSION}-RELEASE.zip"           "$DL/NVMeFix.zip"

mkdir -p "$DL/OpenCore" "$DL/Lilu" "$DL/VirtualSMC" "$DL/WhateverGreen" \
         "$DL/AppleALC" "$DL/RestrictEvents" "$DL/NVMeFix"
unzip -q -o "$DL/OpenCore.zip"       -d "$DL/OpenCore"
unzip -q -o "$DL/Lilu.zip"           -d "$DL/Lilu"
unzip -q -o "$DL/VirtualSMC.zip"     -d "$DL/VirtualSMC"
unzip -q -o "$DL/WhateverGreen.zip"  -d "$DL/WhateverGreen"
unzip -q -o "$DL/AppleALC.zip"       -d "$DL/AppleALC"
unzip -q -o "$DL/RestrictEvents.zip" -d "$DL/RestrictEvents"
unzip -q -o "$DL/NVMeFix.zip"        -d "$DL/NVMeFix"

# --- 3. Assemble staging EFI tree from the existing layout -----------------

echo "[3/7] Staging EFI tree..."
cp -a "$SRC/EFI" "$STAGE/"
# Also carry the repo-local helpers and top-level .pkg blobs.
[[ -d "$SRC/SOURCE" ]] && cp -a "$SRC/SOURCE" "$STAGE/"
[[ -d "$SRC/UTILS"  ]] && cp -a "$SRC/UTILS"  "$STAGE/"
for f in "$SRC"/install-EFI-for-*.pkg; do [[ -e "$f" ]] && cp -a "$f" "$STAGE/"; done

# Strip macOS AppleDouble / Finder metadata that leaks in from previous
# extractions (.DS_Store, ._*). They confuse nothing but bloat the ISO.
find "$STAGE" \( -name '.DS_Store' -o -name '._*' \) -print -delete | sed 's/^/  dropped: /' || true

# OpenCore binaries come from X64/EFI of the release zip.
OC_X64="$DL/OpenCore/X64/EFI"
install -m 0644 "$OC_X64/BOOT/BOOTx64.efi"    "$STAGE/EFI/BOOT/BOOTx64.efi"
install -m 0644 "$OC_X64/OC/OpenCore.efi"     "$STAGE/EFI/OC/OpenCore.efi"
for d in OpenCanopy.efi OpenRuntime.efi ResetNvramEntry.efi HfsPlus.efi UsbMouseDxe.efi; do
  if [[ -f "$OC_X64/OC/Drivers/$d" ]]; then
    install -m 0644 "$OC_X64/OC/Drivers/$d" "$STAGE/EFI/OC/Drivers/$d"
  elif [[ -f "$DL/OpenCore/X64/EFI/OC/Drivers/$d" ]]; then
    install -m 0644 "$DL/OpenCore/X64/EFI/OC/Drivers/$d" "$STAGE/EFI/OC/Drivers/$d"
  fi
done

# HfsPlus.efi is not shipped in OpenCorePkg; if the old ISO had it, keep it.
if [[ ! -f "$STAGE/EFI/OC/Drivers/HfsPlus.efi" && -f "$SRC/EFI/OC/Drivers/HfsPlus.efi" ]]; then
  install -m 0644 "$SRC/EFI/OC/Drivers/HfsPlus.efi" "$STAGE/EFI/OC/Drivers/HfsPlus.efi"
fi

# Drop-in replace the 3 Acidanthera kexts that ship in the base ISO.
replace_kext() {
  local name="$1" src_zip_dir="$2"
  local dst="$STAGE/EFI/OC/Kexts/${name}.kext"
  local src="$src_zip_dir/${name}.kext"
  [[ -d "$src" ]] || { echo "Kext source missing: $src" >&2; exit 1; }
  rm -rf "$dst"
  cp -a "$src" "$dst"
}
replace_kext Lilu          "$DL/Lilu"
replace_kext VirtualSMC    "$DL/VirtualSMC/Kexts"
replace_kext WhateverGreen "$DL/WhateverGreen"

# Install RestrictEvents + NVMeFix (required companions for the VMM-mask
# kernel patch applied below: RestrictEvents backs revpatch=sbvmm so OTA
# updates keep working, and silences MacPro7,1's memory-config nag; NVMeFix
# is harmless on virtio disks and needed for NVMe passthrough). Installed
# into the base EFI/OC/Kexts tree and every SOURCE/EFI-*/EFI/OC/Kexts
# variant tree so their config.plist Kernel>Add entries (added below) never
# point at a missing bundle.
install_kext() {
  local name="$1" src_zip_dir="$2" dst_root="$3"
  local dst="$dst_root/${name}.kext"
  local src="$src_zip_dir/${name}.kext"
  [[ -d "$src" ]] || { echo "Kext source missing: $src" >&2; exit 1; }
  rm -rf "$dst"
  cp -a "$src" "$dst"
}
install_kext RestrictEvents "$DL/RestrictEvents" "$STAGE/EFI/OC/Kexts"
install_kext NVMeFix        "$DL/NVMeFix"        "$STAGE/EFI/OC/Kexts"
for vdir in "$STAGE"/SOURCE/EFI-*/EFI/OC/Kexts; do
  [[ -d "$vdir" ]] || continue
  install_kext RestrictEvents "$DL/RestrictEvents" "$vdir"
  install_kext NVMeFix        "$DL/NVMeFix"        "$vdir"
done

# --- 4. Normalise config.plist ----------------------------------------------
#
# Idempotent pass applied to the base config.plist and all four SOURCE
# variant configs:
#   - SecureBootModel=Disabled (Dortania recommendation for VM installs)
#   - Rewrite the stale "# BASE EFI ... OC 1.0.x" header comment
#   - Kernel>Add: install RestrictEvents.kext + NVMeFix.kext, cap
#     WhateverGreen at MaxKernel=24.99.99 (AMD GPU connector patching is
#     broken on Tahoe/Darwin 25+ per Dortania's Tahoe guide)
#   - Kernel>Patch: append the hv_vmm_present<->hibernatecount swap from
#     Artefacts/Patches/.../patch-bcm-virtual.plist (Apple ID/iMessage/
#     FaceTime under KVM), MinKernel raised to 24.0.0
#   - NVRAM boot-args: append revpatch=sbvmm (companion for RestrictEvents
#     so OTA updates keep working once the VMM is masked)

echo "[4/7] Normalising config.plist files..."
BCM_PATCH="$REPO_DIR/Artefacts/Patches/BCM94360 - Bluetooth - Sonoma and Sequoia/patch-bcm-virtual.plist"
[[ -f "$BCM_PATCH" ]] || { echo "Missing VMM-mask patch source: $BCM_PATCH" >&2; exit 1; }

CONFIGS=( "$STAGE/EFI/OC/config.plist" )
while IFS= read -r -d '' c; do CONFIGS+=( "$c" ); done \
  < <(find "$STAGE/SOURCE" -name config.plist -print0 2>/dev/null)

for c in "${CONFIGS[@]}"; do
  echo "  patching ${c#"$STAGE"/}"
  python3 "$SCRIPT_DIR/patch_config.py" "$c" "$OC_VERSION" "$BCM_PATCH"
done

# --- 5. Validate with ocvalidate --------------------------------------------
#
# Use the ocvalidate binary from the OC_VERSION release zip we already
# downloaded above -- NOT the ISO's bundled UTILS copy, which is pinned to
# OpenCore 1.0.4 and rejects 1.0.7 configs. Best-effort: skip if the Linux
# binary isn't runnable on this host (e.g. non-x86_64 build machine).

echo "[5/7] Validating config.plist files with ocvalidate..."
OCVALIDATE="$DL/OpenCore/Utilities/ocvalidate/ocvalidate.linux"
if [[ -f "$OCVALIDATE" ]]; then
  chmod +x "$OCVALIDATE"
  if "$OCVALIDATE" "$STAGE/EFI/OC/config.plist" >/dev/null 2>&1; then
    for c in "${CONFIGS[@]}"; do
      echo "  validating ${c#"$STAGE"/}"
      "$OCVALIDATE" "$c" || { echo "ocvalidate failed on $c" >&2; exit 1; }
    done
  else
    echo "  ocvalidate.linux is not runnable on this host; skipping validation." >&2
  fi
else
  echo "  ocvalidate.linux not found in OpenCore release zip; skipping validation." >&2
fi

# --- 6. Build the new FAT32 image ------------------------------------------

echo "[6/7] Building 96 MiB FAT32 image..."
PART_SECTORS=$(( (IMAGE_SIZE_MIB * 1024 * 1024 - 512) / 512 ))
TOTAL_SECTORS=$(( IMAGE_SIZE_MIB * 1024 * 1024 / 512 ))
TMP_IMG="$WORK/new.iso"
TMP_FAT="$WORK/fat.img"

dd if=/dev/zero of="$TMP_IMG" bs=1M count="$IMAGE_SIZE_MIB" status=none
dd if=/dev/zero of="$TMP_FAT" bs=512 count="$PART_SECTORS" status=none

mkfs.vfat -F 32 -n OPENCORE "$TMP_FAT" >/dev/null

# Populate the FAT32 partition via mtools (no loop device needed).
cat > "$WORK/mtoolsrc.new" <<EOF
drive y: file="$TMP_FAT"
EOF
MTOOLSRC="$WORK/mtoolsrc.new" MTOOLS_SKIP_CHECK=1 mcopy -s -n "$STAGE"/* y:/

# Write FAT32 payload at LBA 1, then stamp the MBR.
dd if="$TMP_FAT" of="$TMP_IMG" bs=512 seek=1 conv=notrunc status=none

python3 - "$TMP_IMG" "$PART_SECTORS" <<'PYEOF'
import struct, sys
path, sectors = sys.argv[1], int(sys.argv[2])
with open(path, 'r+b') as f:
    f.seek(0)
    mbr = bytearray(f.read(512))
    # Zero any existing partition table + signature.
    mbr[446:512] = b'\x00' * 66
    # One FAT32 LBA partition (type 0x0C) starting at LBA 1.
    entry = bytearray(16)
    entry[0] = 0x80                                # bootable
    entry[1:4] = b'\x00\x01\x01'                   # CHS start (filler)
    entry[4] = 0x0C                                # FAT32 LBA
    entry[5:8] = b'\xfe\xff\xff'                   # CHS end (filler)
    entry[8:12] = struct.pack('<I', 1)             # start LBA
    entry[12:16] = struct.pack('<I', sectors)      # sector count
    mbr[446:446+16] = entry
    mbr[510:512] = b'\x55\xaa'
    f.seek(0); f.write(mbr)
PYEOF

# --- 7. Replace the shipped ISO --------------------------------------------

echo "[7/7] Installing new ISO at $OUT_ISO"
mv -f "$TMP_IMG" "$OUT_ISO"

# Sanity check: re-read the volume via mtools from the final image.
cat > "$WORK/mtoolsrc.verify" <<EOF
drive z: file="$OUT_ISO" offset=512
EOF
MTOOLSRC="$WORK/mtoolsrc.verify" MTOOLS_SKIP_CHECK=1 mdir z:/EFI/OC | sed 's/^/  /'

echo "Done. OpenCore=$OC_VERSION Lilu=$LILU_VERSION VirtualSMC=$VIRTUALSMC_VERSION WhateverGreen=$WHATEVERGREEN_VERSION RestrictEvents=$RESTRICTEVENTS_VERSION NVMeFix=$NVMEFIX_VERSION"
