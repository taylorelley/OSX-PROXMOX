#!/usr/bin/env python3
"""Idempotently normalize an OpenCore config.plist for osx-proxmox VM use.

Used by build-opencore-iso.sh against the base config.plist and every
SOURCE/EFI-*/EFI/OC/config.plist variant. Safe to re-run: running it twice
in a row on the same file produces byte-identical output.

Usage: patch_config.py <config.plist> <oc_version> <bcm-virtual-patch.plist>
"""
import plistlib
import re
import sys

CONFIG_PATH, OC_VERSION, BCM_PATCH_PATH = sys.argv[1], sys.argv[2], sys.argv[3]

with open(CONFIG_PATH, "rb") as f:
    cfg = plistlib.load(f)

# --- 1. Rewrite the stale "# BASE EFI ... OC 1.0.x" header comment key,
#        preserving its position in the top-level dict. -------------------
comment_re = re.compile(r"^# BASE EFI\b")
new_comment_key = f"# BASE EFI - For Proxmox - RELEASE Version - OC {OC_VERSION}"
rebuilt = {}
for k, v in cfg.items():
    if comment_re.match(k):
        rebuilt[new_comment_key] = v
    else:
        rebuilt[k] = v
cfg = rebuilt

# --- 2. SecureBootModel = Disabled (Dortania recommendation for VM installs)
cfg.setdefault("Misc", {}).setdefault("Security", {})["SecureBootModel"] = "Disabled"

# --- 3. Kernel>Add: install RestrictEvents + NVMeFix, cap WhateverGreen ---
kernel = cfg.setdefault("Kernel", {})
kext_add = kernel.setdefault("Add", [])

existing_bundles = {e.get("BundlePath") for e in kext_add}


def make_kext_entry(bundle, executable, comment):
    return {
        "Arch": "Any",
        "BundlePath": bundle,
        "Comment": comment,
        "Enabled": True,
        "ExecutablePath": executable,
        "MaxKernel": "",
        "MinKernel": "",
        "PlistPath": "Contents/Info.plist",
    }


# Set MaxKernel=24.99.99 on WhateverGreen (Dortania: AMD GPU connector
# patching is broken on Tahoe/Darwin 25+; disable WEG there).
for e in kext_add:
    if e.get("BundlePath") == "WhateverGreen.kext":
        e["MaxKernel"] = "24.99.99"

wg_index = next(
    (i for i, e in enumerate(kext_add) if e.get("BundlePath") == "WhateverGreen.kext"),
    len(kext_add) - 1,
)
insert_at = wg_index + 1

new_kexts = [
    ("RestrictEvents.kext", "Contents/MacOS/RestrictEvents",
     "RestrictEvents - VMM board-id for OTA updates (revpatch=sbvmm)"),
    ("NVMeFix.kext", "Contents/MacOS/NVMeFix",
     "NVMeFix - NVMe power management for passthrough disks"),
]
for bundle, executable, comment in new_kexts:
    if bundle in existing_bundles:
        continue
    kext_add.insert(insert_at, make_kext_entry(bundle, executable, comment))
    insert_at += 1
    existing_bundles.add(bundle)

# --- 4. Kernel>Patch: append the hv_vmm_present<->hibernatecount swap ------
# Makes kern.hv_vmm_present resolve to the (always-zero) hibernatecount OID
# so Apple's attestation sees a physical machine -- fixes Apple ID/iMessage/
# FaceTime under KVM. RestrictEvents.kext + revpatch=sbvmm (both applied
# above/below) keep the OTA update path working once the VMM is masked.
with open(BCM_PATCH_PATH, "rb") as f:
    bcm = plistlib.load(f)

kext_patch = kernel.setdefault("Patch", [])
existing_finds = {e.get("Find") for e in kext_patch}

for src in bcm["Kernel"]["Patch"]:
    if src.get("Find") in existing_finds:
        continue
    entry = dict(src)
    entry["MinKernel"] = "24.0.0"
    entry["Comment"] = entry.get("Comment", "").replace(
        "Sonoma and Sequoia", "Sonoma/Sequoia/Tahoe VMM mask"
    )
    kext_patch.append(entry)
    existing_finds.add(entry.get("Find"))

# --- 5. NVRAM boot-args: append revpatch=sbvmm (companion for RestrictEvents)
nvram_add = cfg.setdefault("NVRAM", {}).setdefault("Add", {})
guid = "7C436110-AB2A-4BBB-A880-FE41995C9F82"
guid_dict = nvram_add.setdefault(guid, {})
boot_args = guid_dict.get("boot-args", "")
tokens = boot_args.split()
if "revpatch=sbvmm" not in tokens:
    tokens.append("revpatch=sbvmm")
    guid_dict["boot-args"] = " ".join(tokens)

with open(CONFIG_PATH, "wb") as f:
    plistlib.dump(cfg, f, sort_keys=False)
