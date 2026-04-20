#!/bin/bash -e
#
# build-image.sh
# Build a FAT32 Recovery partition image from downloaded macOS recovery files
# and convert it to a raw disk for QEMU/Proxmox.
#

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

SPARSE_IMAGE="Recovery.dmg.sparseimage"
OUTPUT_DMG="Recovery.RO.dmg"
OUTPUT_RAW="Recovery.raw"

DEVICE=""

cleanup() {
    local exit_code=$?
    if [ -n "$DEVICE" ]; then
        hdiutil detach "$DEVICE" >/dev/null 2>&1 || true
    fi
    rm -f "$SPARSE_IMAGE" "$OUTPUT_DMG" >/dev/null 2>&1 || true
    exit "$exit_code"
}
trap cleanup EXIT

echo -e "${YELLOW}[*] Checking prerequisites...${NC}"
for bin in hdiutil diskutil qemu-img; do
    if ! command -v "$bin" >/dev/null 2>&1; then
        echo -e "${RED}[!] Required tool not found: $bin${NC}"
        exit 1
    fi
done

echo -e "${YELLOW}[*] Removing previous artifacts...${NC}"
rm -rf "$OUTPUT_DMG" "$OUTPUT_RAW" "$SPARSE_IMAGE"

echo -e "${YELLOW}[*] Creating sparse recovery image...${NC}"
hdiutil create -size 800m -layout "UNIVERSAL HD" -type SPARSE -o Recovery.dmg

echo -e "${YELLOW}[*] Attaching sparse image...${NC}"
DEVICE=$(hdiutil attach -nomount "$SPARSE_IMAGE" | head -n 1 | awk '{print $1}')
echo -e "    new device: ${GREEN}${DEVICE}${NC}"

echo -e "${YELLOW}[*] Partitioning and mounting RECOVERY volume...${NC}"
diskutil partitionDisk "${DEVICE}" 1 MBR fat32 RECOVERY R
N=$(echo "$DEVICE" | tr -dc '0-9')
diskutil mount "disk${N}s1"
MOUNT="$(diskutil info "disk${N}s1" | sed -n 's/.*Mount Point: *//p')"

echo -e "${YELLOW}[*] Copying recovery payload to ${MOUNT}/com.apple.recovery.boot/...${NC}"
mkdir -p "$MOUNT/com.apple.recovery.boot"
cp ./*.dmg ./*.chunklist "$MOUNT/com.apple.recovery.boot/"

echo -e "${YELLOW}[*] Unmounting and detaching volume...${NC}"
diskutil umount "disk${N}s1"
hdiutil detach "$DEVICE"
DEVICE=""

echo -e "${YELLOW}[*] Converting sparse image to read-only DMG...${NC}"
hdiutil convert -format UDZO "$SPARSE_IMAGE" -o "$OUTPUT_DMG"
rm -f "$SPARSE_IMAGE"

echo -e "${YELLOW}[*] Converting DMG to raw disk for QEMU...${NC}"
qemu-img convert -f dmg -O raw "$OUTPUT_DMG" "$OUTPUT_RAW"
rm -f "$OUTPUT_DMG"

echo -e "${GREEN}[+] Recovery image built: ${OUTPUT_RAW}${NC}"
