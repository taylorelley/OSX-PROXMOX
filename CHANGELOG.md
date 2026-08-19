OpenCore Changelog
==================

#### Latest versions
- Check history of commits

#### 2026.08.19 – AMD/Tahoe VM hygiene improvements

- **Per-VM OpenCore ISOs.** Every VM previously shared one OpenCore ISO and,
  unless menu 201's SMBIOS step was run manually, one hardcoded serial
  (`C02YG0KQHX87`) baked into the base image. `create_vm` now copies the
  base ISO to `opencore-vm<VMID>.iso`, generates a fresh GenSMBIOS serial
  for it, and sets its ROM from the VM's network MAC address. Falls back
  gracefully to the shared ISO if SMBIOS generation fails (it needs network
  access for `macserial`). New menu 206 cleans up per-VM ISOs orphaned by
  VM deletion; menu 205 can now target either the base ISO or a per-VM ISO.
- **Tahoe SMBIOS fix.** The default `iMacPro1,1` SMBIOS is not on Apple's
  Tahoe (26) supported-model allow-list and is rejected by its installer.
  Tahoe VMs now default to `MacPro7,1` (its "memory modules misconfigured"
  nag is silenced by the newly-bundled `RestrictEvents.kext`); every other
  release keeps `iMacPro1,1`. Override with `OSX_SMBIOS_MODEL`.
- **Apple ID / iMessage / FaceTime under KVM.** Shipped `config.plist`
  (base + all four `SOURCE/EFI-*` variants) now includes a kernel patch
  (`MinKernel=24.0.0`) that masks `kern.hv_vmm_present`, so Apple's
  attestation sees a physical machine — this was previously present as an
  unused patch file in `Artefacts/Patches/BCM94360.../patch-bcm-virtual.plist`
  and is now wired into the bundled configs. Ships with `RestrictEvents.kext`
  and a `revpatch=sbvmm` boot-arg so OTA system updates keep working once
  the VMM is masked.
- **WhateverGreen capped on Tahoe.** `WhateverGreen.kext` now has
  `MaxKernel=24.99.99` in all bundled configs — Dortania documents its AMD
  GPU connector patching as broken on Tahoe (Darwin 25+); `agdpmod=pikera`
  becomes an inert boot-arg there as a result.
- **NVMeFix.kext** (1.1.3) is now installed and enabled for NVMe
  passthrough disks.
- **OpenCore ISO self-update fix.** Menu 201 (`update_opencore_iso`)
  previously `rm -f`'d the existing ISO before downloading a replacement
  from *upstream's* repo (`luchina-gabriel/OSX-PROXMOX`), discarding this
  fork's OpenCore 1.0.7 build and stranding the host on any download
  failure. It now prefers the local repo checkout, otherwise downloads
  from this fork's URL to a temp file and moves it into place only on
  success, and offers to refresh existing per-VM ISOs from the updated
  base.
- `tools/build-opencore-iso.sh` gained an idempotent `config.plist`
  normalization pass (`tools/patch_config.py`) applied to the base config
  and all four `SOURCE/EFI-*` variants — installs RestrictEvents/NVMeFix,
  caps WhateverGreen, applies the VMM-mask patch, appends `revpatch=sbvmm`,
  and rewrites the stale "OC 1.0.4"/"1.0.2" header comment — plus an
  `ocvalidate` (OpenCore 1.0.7) validation step. Regenerated
  `EFI/opencore-osx-proxmox-vm.iso` accordingly.

#### 2026.04.21 – Tahoe refresh

- Rebuilt `EFI/opencore-osx-proxmox-vm.iso` with OpenCore **1.0.7** (first OC
  release with Tahoe `XhciPortLimit` + kext-injection fixes documented in
  Dortania's macOS 26 guide).
- Bumped bundled Acidanthera kexts: Lilu **1.7.2**, VirtualSMC **1.3.7**,
  WhateverGreen **1.7.0**. `AppleMCEReporterDisabler.kext` is preserved as-is.
- Normalised shipped `config.plist` to `SecureBootModel = Disabled`, which is
  the Dortania-recommended setting for Tahoe VM installs.
- Added `tools/build-opencore-iso.sh` — a reproducible, mtools-based builder
  that downloads pinned OpenCore + kext releases, stages the EFI tree,
  stamps a 96 MiB MBR/FAT32 image and replaces the shipped ISO in place.
  Users can re-run it at any time to pick up newer releases.
- **AMD CPU profile selection.** `setup` now detects the Ryzen (Zen)
  generation on AMD hosts from `/proc/cpuinfo` and offers a `conservative` /
  `aggressive` / `baseline` / `host` CPU profile choice when creating a VM,
  recommending `conservative` or `aggressive` for Tahoe depending on Zen
  generation and defaulting to the prior `baseline` behaviour everywhere
  else. Override non-interactively with `OSX_AMD_CPU_PROFILE`.
- `OCVERSION` in `setup` is now `1.0.7` and `HACKPXVERSION` = `2026.04.21`.

#### 2026.04.20 – macOS Tahoe menu support, AMD boot-freeze fix, installer reliability

- **macOS Tahoe (26) added to the setup menu** (option 9), routed through the
  same recovery download, USB controller, and AMD CPU-model paths already
  used for Sequoia/Sonoma.
- **Fixed a 100% CPU freeze at the Apple logo** on AMD hosts for
  Ventura/Sonoma/Sequoia VMs: the Cascadelake-Server `-cpu` string was
  missing `+hypervisor`, `+kvm_pv_unhalt`, and `+kvm_pv_eoi`, so the guest
  kernel busy-waited on halted vCPUs instead of yielding.
- **`install.sh` reliability fixes:** now clones this fork
  (`taylorelley/OSX-PROXMOX`) instead of upstream so `curl | bash` actually
  installs the fork's fixes; reattaches stdin to `/dev/tty` so piped
  (`curl | bash`) runs can still prompt interactively; and no longer deletes
  the current working directory when run from inside the target install
  directory.
- Selectively adopted upstream PR #51's UX polish (colorized
  `CHECK-IOMMU.sh`/`CREATE-ISO-macOS.command` output, `IOMMU-Groups.sh`
  cleanup, safer `macrecovery/build-image.sh` cleanup trap) without its
  regressions to this fork's installer safety fixes.

#### 2026.04.01 – Proxmox VE 9.1 support & non-destructive installer

- **Full Proxmox VE 9.1.x support**, replacing the prior "preliminary/BETA"
  9.0 support, including PVE-9-specific handling of the enterprise
  repository split (`pve-enterprise.sources`) via a new `PVE_MAJOR` check.
- **`setup` is now safe to run on a host with existing VMs/LXCs**, not just a
  fresh install:
  - A pre-flight check summarizes existing VMs/LXCs/PCI-passthrough configs
    and every change about to be made, and requires explicit `y/N`
    confirmation (or aborts outright in a non-interactive shell).
  - A new `--dry-run` flag previews all changes without applying them.
  - Every system file `setup` touches is backed up first to
    `/root/.osx-proxmox-backups` (configurable via `BACKUP_DIR`), with a
    matching restore path.
  - GPU/audio driver blacklisting, framebuffer disabling, unsafe VFIO
    interrupts, and enterprise/ceph repo removal are now opt-in prompts
    instead of unconditional; GRUB/IOMMU/VFIO changes are skipped when
    already configured; a forced reboot is replaced with a warning-and-ask
    when VMs/LXCs are running.

#### v3.2.0

- Open SOURCE CODE of BINARY \o/
- Alter function '201 - Update Opencore ISO file' to download .ISO directly from repository;
- Add script in tools - CHECK-IOMMU.sh - Check if your IOMMU are ENABLED;
- Update macrecovery tool for Opencore 0.7.7;
- Update README;
- Adjustments to copyright terms.

#### v3.1.0

- Add support to run macOS in Cloud using this solution with VultR Provider;
- Add option to 'Remove Proxmox Subscription Notice';

#### v3.0.0

- Upgrade Opencore to 0.7.7;
- Upgrade Lilu and WhateverGreen Kexts;
- Add function '201 - Update Opencore ISO file';
- Add function '202 - Clear all Recovery Images';
- Add option to choose Storage in create VM;
- Fix minor bugs.

#### v2.0.1

- Fixed Opencore ISO disk size which was making booting impossible to install new virtual machines;

#### v2.0.0

- Upgrade to Opencore 0.7.6 (December/2021);
- Update Lilu (kext);
- Update VirtualSMC (kext);
- Fully compatible with Intel 12th and activate of all cores (P+E) and HT (Hyper-Threading);

#### v1.5.1

- Fix Menu Option - # 200;
- Cleaning some codes unnecessary in setup;

#### v1.5.0

- Fix QEMU 6.1 Passthrough in PVE 7.1+;
- Add option to "only ENTER" for exit osx-setup;

#### v1.4.0

- Add option to skip download and create recovery image of macOS;

#### v1.3.0

- Add script ```IOMMU-Groups.sh``` in tools;
- Add option 'Fix issues to start macOS (stuck at Apple logo) for Proxmox VE v7.1.XX';
- Add option 'Add Proxmox VE NO Subscription repository - for beta/non production upgrades';
- Remove option 'Activate support for Windows 11 natively'.

#### v1.2.0

- Remove PVE/Kernel version from ```osx-setup``` menu;
- Add option to define disk size in creation virtual machine section of ```osx-setup```;
- Add script in tools, for create macOS Install ```ISO``` from genuine macOS Installer .app.

#### v1.1.1

- Fix logic of messages in 'Activate support for Windows 11 natively' option;
- Fix typo's;

#### v1.1.0

- Including support for Proxmox VE v7 family;
- Fix for remove tmp directory;
- Including git for apt install option in install;
- Optimize procedure in 'Download & Create Recovery Image';
- Add return code for apt update/install in prereqs section and condition to exit/abort;
- Add support to install Windows 11 with TPM and Secure Boot;
- Update EFI ISO for including support to install Nvidia Web Drivers for High Sierra;

#### v1.0.0

- Initial version of OSX-Proxmox Solution
