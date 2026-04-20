#!/bin/bash
#
# Script: IOMMU-Groups.sh
# Goal: List PCI devices in IOMMU Groups
#
# Author: Gabriel Luchina
# https://luchina.com.br
# 20250627T2331

shopt -s nullglob

for iommu_group in $(ls /sys/kernel/iommu_groups/ | sort -V); do
    echo "IOMMU Group ${iommu_group}:"
    for pci_device in /sys/kernel/iommu_groups/$iommu_group/devices/*; do
        dev_id="${pci_device##*/}"
        info=$(lspci -nns "$dev_id" 2>/dev/null)
        if [ -n "$info" ]; then
            echo -e "\t$info"
        else
            echo -e "\t$dev_id (unable to read PCI info)"
        fi
    done
done
