#!/bin/bash
#
# Script: check-iommu-enabled.sh
# Goal: Check if IOMMU is enabled on your system
#
# Author: Gabriel Luchina
# https://luchina.com.br
# 20220128T1112
#

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

echo "Checking if IOMMU is enabled..."

iommu_check=$(dmesg 2>/dev/null | grep -i -E 'iommu|DMAR|amd-vi')

if [ -n "$iommu_check" ]; then
    echo -e "${GREEN}IOMMU is enabled in the kernel.${NC}"
    echo
    echo "Matched kernel log entries:"
    echo "$iommu_check"
else
    echo -e "${RED}IOMMU was not detected.${NC}"
    echo
    echo -e "${YELLOW}Possible causes:${NC}"
    echo "  1. IOMMU is disabled in BIOS/UEFI (enable VT-d for Intel or SVM/IOMMU for AMD)."
    echo "  2. The kernel command line is missing the IOMMU parameter:"
    echo "       Intel: intel_iommu=on"
    echo "       AMD:   amd_iommu=on"
    echo "     Add it to GRUB_CMDLINE_LINUX_DEFAULT in /etc/default/grub,"
    echo "     then run: update-grub && reboot"
    exit 1
fi
