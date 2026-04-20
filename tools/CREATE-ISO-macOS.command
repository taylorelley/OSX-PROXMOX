#!/bin/bash
#
# Script: create-iso-macOS
# Goal: create "ISO" file for use in the Proxmox VE Environment
#
# Author: Gabriel Luchina
# https://luchina.com.br
# 20211116T2245

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

clear

echo -e "\n${GREEN}Automated script to create an \"ISO\" file of a macOS installer for Proxmox VE${NC}"
echo -e "BY: ${YELLOW}https://luchina.com.br${NC}"
echo -e "SUPPORT: ${YELLOW}https://osx-proxmox.com${NC}"

echo -n -e "\nPath to temporary files (work dir): "
read -r TEMPDIR
if [ ! -d "$TEMPDIR" ]; then
    echo -e "${RED}[!] The temporary directory does not exist: $TEMPDIR${NC}"
    exit 1
fi

echo -n -e "Path to macOS Installation (.app) file: "
read -r APPOSX
if [ ! -d "$APPOSX" ] || [ ! -x "$APPOSX/Contents/Resources/createinstallmedia" ]; then
    echo -e "${RED}[!] macOS installer not found at: $APPOSX${NC}"
    echo    "    Expected: \$APPOSX/Contents/Resources/createinstallmedia"
    exit 1
fi

echo ""

## Core
cd "$TEMPDIR" || exit 1

echo -e "${YELLOW}[*] Removing any previous macOS-install.* artifacts...${NC}"
rm -rf macOS-install* > /dev/null 2> /dev/null

echo -e "${YELLOW}[*] Creating 16 GB scratch DMG...${NC}"
hdiutil create -o macOS-install -size 16g -layout GPTSPUD -fs HFS+J > /dev/null 2> /dev/null

echo -e "${YELLOW}[*] Attaching DMG at /Volumes/install_build...${NC}"
hdiutil attach -noverify -mountpoint /Volumes/install_build macOS-install.dmg > /dev/null 2> /dev/null

echo -e "${YELLOW}[*] Running createinstallmedia (this can take several minutes)...${NC}"
sudo "${APPOSX}/Contents/Resources/createinstallmedia" --volume /Volumes/install_build --nointeraction

echo -e "${YELLOW}[*] Detaching installer volumes...${NC}"
hdiutil detach -force "/Volumes/Install macOS"* > /dev/null 2> /dev/null && sleep 3s > /dev/null 2> /dev/null
hdiutil detach -force "/Volumes/Shared Support"* > /dev/null 2> /dev/null

echo -e "${YELLOW}[*] Renaming DMG to .iso...${NC}"
mv macOS-install.dmg macOS-install.iso > /dev/null 2> /dev/null

echo ""
echo -e "${GREEN}[+] Done. Image created: ${TEMPDIR}/macOS-install.iso${NC}"
echo    "    Upload it to Proxmox as an ISO and attach it to the VM's CD/DVD drive."
echo ""
