<div align="center">
  
# 🚀 OSX-PROXMOX - Run macOS on ANY Computer (AMD & Intel)

![GitHub stars](https://img.shields.io/github/stars/taylorelley/osx-proxmox?style=flat-square)
![GitHub forks](https://img.shields.io/github/forks/taylorelley/OSX-PROXMOX?style=flat-square)
![GitHub license](https://img.shields.io/github/license/taylorelley/osx-proxmox?style=flat-square)
![GitHub issues](https://img.shields.io/github/issues/taylorelley/osx-proxmox?style=flat-square)

> This is a fork of [luchina-gabriel/OSX-PROXMOX](https://github.com/luchina-gabriel/OSX-PROXMOX) with additional Proxmox VE 9.1 support, a non-destructive installer for hosts with existing VMs/LXCs, macOS Tahoe support, AMD CPU profile detection, and per-VM OpenCore ISOs. See [CHANGELOG.md](CHANGELOG.md) for details.

</div>

![v15 - Sequoia](https://github.com/user-attachments/assets/4efd8874-dbc8-48b6-a485-73f7c38a5e06)
Easily install macOS on Proxmox VE with just a few steps! This guide provides the simplest and most effective way to set up macOS on Proxmox, whether you're using AMD or Intel hardware.

---

## 🛠 Installation Guide

1. Install a **FRESH/CLEAN** version of Proxmox VE (v7.0.XX ~ 9.1.XX) - just follow the Next, Next & Finish (NNF) approach.
2. Open the **Proxmox Web Console** → Navigate to `Datacenter > YOUR_HOST_NAME > Shell`.
3. Copy, paste, and execute the command below:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/taylorelley/OSX-PROXMOX/main/install.sh)"
```

> ⚠️ The upstream `https://install.osx-proxmox.com` shortlink clones
> [luchina-gabriel/OSX-PROXMOX](https://github.com/luchina-gabriel/OSX-PROXMOX), **not** this fork.
> Use the raw GitHub URL above (which is what `install.sh` itself now clones — see
> [CHANGELOG.md](CHANGELOG.md)) to get this fork's Proxmox 9.1, Tahoe, and safety fixes.

🎉 Voilà! You can now install macOS!
![osx-terminal](https://github.com/user-attachments/assets/ea81b920-f3e2-422e-b1ff-0d9045adc55e)
---

## 🛡 Running on an Existing Proxmox Host

`setup` no longer assumes a fresh install. On an existing host it:

- **Runs a pre-flight check** listing any existing VMs, LXCs, PCI passthrough
  configs, and pre-existing `/etc/modprobe.d/kvm.conf`, plus a summary of what
  it's about to change (GRUB/IOMMU, VFIO modules, KVM modprobe configs,
  packages), and asks for `y/N` confirmation before touching anything.
- **Backs up every file it modifies** (`/etc/default/grub`, `/etc/modules`,
  `/etc/modprobe.d/`, `/etc/apt/sources.list[.d]`, `/etc/environment`,
  the Proxmox subscription-nag JS) to a timestamped directory under
  `/root/.osx-proxmox-backups` (override with `BACKUP_DIR=<path> ./setup`)
  before making changes.
- **Makes disruptive steps opt-in** rather than automatic: blacklisting
  GPU/audio drivers, disabling the framebuffer, allowing unsafe VFIO
  interrupts, and removing the enterprise/ceph APT repositories all prompt
  first. GRUB/IOMMU changes and VFIO module loading are skipped if already
  configured, and it warns before enabling IOMMU when it finds existing PCI
  passthrough configs (group assignments can shift after the reboot).
- **Never force-reboots.** If running VMs or LXCs are detected, `setup` asks
  before rebooting instead of doing it automatically.
- **Refuses to run unattended.** Piping `setup` into a non-interactive shell
  aborts at the pre-flight check rather than silently applying changes.

Preview what would change without touching the system:

```bash
./setup --dry-run
```

---

## 🔧 Additional Configuration

### Install EFI Package in macOS (Disable Gatekeeper First)

```bash
sudo spctl --master-disable
```

---

## 🍏 macOS Versions Supported
✅ macOS High Sierra - 10.13  
✅ macOS Mojave - 10.14  
✅ macOS Catalina - 10.15  
✅ macOS Big Sur - 11  
✅ macOS Monterey - 12  
✅ macOS Ventura - 13  
✅ macOS Sonoma - 14  
✅ macOS Sequoia - 15  
✅ macOS Tahoe - 26  

> **macOS Tahoe (26) notes.** Each VM gets its own OpenCore ISO
> (`opencore-vm<ID>.iso`) generated at creation time, with a SMBIOS model
> chosen for the target macOS version. Tahoe defaults to `MacPro7,1`
> (Apple's Tahoe allow-list rejects `iMacPro1,1`, the default for every
> other supported release); MacPro7,1's "memory modules misconfigured" nag
> is silenced by the bundled `RestrictEvents.kext`. Override the model with
> `OSX_SMBIOS_MODEL=<model> ./setup` or the per-VM prompt. Items from the
> Dortania Tahoe guide that are **bare-metal only** (analog audio via
> AppleHDA/AppleALC, Broadcom Wi-Fi, Intel Bluetooth) do not apply to QEMU
> VMs. `WhateverGreen.kext` is capped at `MaxKernel=24.99.99` (disabled on
> Tahoe/Darwin 25+) since Dortania documents its AMD GPU connector patching
> as broken there — `agdpmod=pikera` becomes an inert boot-arg on Tahoe as a
> result; GPU-passthrough users on Tahoe need to manage connector patching
> themselves. `NVMeFix.kext` ships enabled for NVMe passthrough disks.
>
> **Apple ID / iMessage / FaceTime under KVM.** The shipped `config.plist`
> includes a kernel patch (`MinKernel=24.0.0`, i.e. Sonoma and newer) that
> masks `kern.hv_vmm_present` so Apple's attestation sees a physical
> machine — this is what makes Apple ID and iMessage work inside a KVM
> guest on Sequoia and Tahoe. `RestrictEvents.kext` and the `revpatch=sbvmm`
> boot-arg ship alongside it so OTA system updates keep working once the
> VMM is masked; no manual EFI edits needed.

---

## 🖥 Proxmox VE Versions Supported
✅ v7.0.XX ~ 9.1.XX

### 🔄 OpenCore Version
- **April/2026 - 1.0.7** → Tahoe-capable kext injection (≥ 1.0.5) and XhciPortLimit fixes; ships Lilu 1.7.2, VirtualSMC 1.3.7, WhateverGreen 1.7.0 (capped `MaxKernel=24.99.99`), RestrictEvents 1.1.6, NVMeFix 1.1.3. SIP enabled, DMG signed by Apple. Rebuild locally with `sudo tools/build-opencore-iso.sh` (requires `mtools`, `dosfstools`, `xmlstarlet`, `curl`, `unzip`, `python3` on the build host — not required on the Proxmox host itself).

### 💿 Per-VM OpenCore ISOs
Each VM created by `setup` gets its own OpenCore ISO (`opencore-vm<VMID>.iso`) copied from the shared base image, with a freshly generated SMBIOS serial (`.smbios-vm<VMID>.json`) and a ROM derived from the VM's network MAC address — instead of every VM sharing one image, one config, and one hardcoded serial. If SMBIOS generation fails (GenSMBIOS needs network access), VM creation still succeeds using the shared ISO's defaults. Menu option **205** now lets you pick which ISO (base or per-VM) to customize, and **206** cleans up per-VM ISOs left behind after a VM is deleted (Proxmox doesn't remove ISO-storage volumes on VM destroy).

---

## ☁️ Cloud Support (Run Hackintosh in the Cloud!)
- [🌍 VultR](https://www.vultr.com/?ref=9035565-8H)
- [📺 Video Tutorial](https://youtu.be/8QsMyL-PNrM) (Enable captions for better understanding)
- Now has configurable bridges, and can add as many bridges and specify the subnet for them.

---

## ⚠️ Disclaimer

🚨 **FOR DEVELOPMENT, STUDENT, AND TESTING PURPOSES ONLY.**

I am **not responsible** for any issues, damage, or data loss. Always back up your system before making any changes.

---

## 📌 Requirements

Since macOS Monterey, your host must have a **working TSC (timestamp counter)**. Otherwise, if you assign multiple cores to the VM, macOS may **crash due to time inconsistencies**. To check if your host is compatible, run the following command in Proxmox:

```bash
dmesg | grep -i -e tsc -e clocksource
```

### ✅ Expected Output (for working hosts):
```
clocksource: Switched to clocksource tsc
```

### ❌ Problematic Output (for broken hosts):
```
tsc: Marking TSC unstable due to check_tsc_sync_source failed
clocksource: Switched to clocksource hpet
```

### 🛠 Possible Fixes
1. Disable "ErP mode" and **all C-state power-saving modes** in your BIOS. Then power off your machine completely and restart.
2. Try forcing TSC in GRUB:
   - Edit `/etc/default/grub` and add:
     ```bash
     clocksource=tsc tsc=reliable
     ```
   - Run `update-grub` and reboot (This may cause instability).
3. Verify the TSC clock source:
   ```bash
   cat /sys/devices/system/clocksource/clocksource0/current_clocksource
   ```
   The output **must be `tsc`**.

[Read More](https://www.nicksherlock.com/2022/10/installing-macos-13-ventura-on-proxmox/comment-page-1/#comment-55532)

---

## 🔍 Troubleshooting

### ❌ High Sierra & Below - *Recovery Server Could Not Be Contacted*

If you encounter this error, you need to switch from **HTTPS** to **HTTP** in the installation URL:

1. When the error appears, leave the window open.
2. Open **Installer Log** (`Window > Installer Log`).
3. Search for "Failed to load catalog" → Copy the log entry.
4. Close the error message and return to `macOS Utilities`.
5. Open **Terminal**, paste the copied data, and **remove everything except the URL** (e.g., `https://example.sucatalog`).
6. Change `https://` to `http://`.
7. Run the command:

   ```bash
   nvram IASUCatalogURL="http://your-http-url.sucatalog"
   ```

8. Quit Terminal and restart the installation.

[Reference & More Details](https://mrmacintosh.com/how-to-fix-the-recovery-server-could-not-be-contacted-error-high-sierra-recovery-is-still-online-but-broken/)

### ❌ Problem for GPU Passthrough

If you see an Apple logo and the bar doesn’t move on your external display, you need to disable “above 4g decoding” in the motherboard’s BIOS.

In some environments it is necessary to segment the IOMMU Groups to be able to pass the GPU to the VM.

1. Add the content `pcie_acs_override=downstream,multifunction pci=nommconf` in the file `/etc/default/grub` at the end of the line `GRUB_CMDLINE_LINUX_DEFAULT`;
2. After changing the grub file, run the command `update-grub` and reboot your PVE.

### ❌ AMD CPU profiles

When creating any macOS VM on an AMD host, `setup` detects your Ryzen generation from `/proc/cpuinfo` flags and prompts you to pick a CPU profile. Pressing Enter accepts the recommended default — which for Ventura, Sonoma, Sequoia, and all pre-Ventura macOS releases is `baseline`, i.e. the same `-cpu` string the script used before this change (no behaviour change unless you explicitly pick a different profile).

For Tahoe (macOS 26) the recommended default depends on Ryzen generation:

| Zen gen        | Recommended profile | Rationale |
|----------------|---------------------|-----------|
| Zen 1 / Zen+   | `conservative`      | PKU/CLWB/CLFLUSHOPT absent; soft TSC sync |
| Zen 2          | `conservative`      | CLWB still absent; TSC sync variable |
| Zen 3          | `aggressive`        | Cascadelake-compatible feature set |
| Zen 4 / Zen 5  | `aggressive`        | Full modern feature set |

#### Profile definitions

Available profiles for Ventura and newer:

| Profile        | Base CPU model                         | Notes |
|----------------|----------------------------------------|-------|
| `conservative` | Haswell-noTSX-IBRS, strict negation    | Narrow feature set, safest on older Ryzens |
| `aggressive`   | Cascadelake-Server + positive flags    | No vmware-cpuid-freq |
| `baseline`     | Cascadelake-Server + vmware-cpuid-freq | Pre-2026.04 behaviour |
| `host`         | host pass-through, vendor spoofed      | Diagnostic only |

Available profiles for pre-Ventura macOS:

| Profile    | Base CPU model                    | Notes |
|------------|-----------------------------------|-------|
| `baseline` | Penryn                            | Current stable behaviour |
| `host`     | host pass-through, vendor spoofed | Diagnostic only |

#### Overriding the profile non-interactively

```bash
OSX_AMD_CPU_PROFILE=conservative ./setup
OSX_AMD_CPU_PROFILE=aggressive   ./setup
OSX_AMD_CPU_PROFILE=baseline     ./setup
OSX_AMD_CPU_PROFILE=host         ./setup
```

The chosen profile, detected Zen generation, and recommended default are logged to the per-VM log (`crt-vm-amd-<osname>.log`).

### SMBIOS model override

Each VM gets a per-VM OpenCore ISO with its own generated SMBIOS (see "Per-VM OpenCore ISOs" above). The default model is `MacPro7,1` for Tahoe and `iMacPro1,1` for every other release; override it non-interactively with:

```bash
OSX_SMBIOS_MODEL=iMac20,1 ./setup
```

or leave it unset to be prompted per-VM (Enter accepts the default).

#### If every profile still freezes at the Apple logo

The bundled OpenCore EFI (`EFI/opencore-osx-proxmox-vm.iso`) ships pre-built and may be missing AMD vanilla kernel patches matching your target Darwin version. This script cannot regenerate the EFI. Rebuild it from [AMD-OSX/AMD_Vanilla](https://github.com/AMD-OSX/AMD_Vanilla) against the appropriate Darwin kernel and replace `EFI/opencore-osx-proxmox-vm.iso` with the result.

#### Diagnostic data is auto-captured

Every VM creation appends the VM config, `lscpu`, `dmesg | grep clocksource`, `kvm_amd` module parameters, and QEMU version to the per-VM log. Attach that log when filing an issue.

---

## 🎥 Demonstration (in Portuguese)

📽️ [Watch on YouTube](https://youtu.be/dil6iRWiun0)  
*(Enable auto-translate captions for English subtitles!)*

---

## 🎖 Credits

- **OpenCore/Acidanthera Team** - Open-source bootloader
- **Corpnewt** - Tools (ProperTree, GenSMBIOS, etc.)
- **Apple** - macOS
- **Proxmox** - Fantastic virtualization platform & documentation

---

## 🌎 Join Our Community - Universo Hackintosh Discord

💬 [**Join Here!**](https://discord.universohackintosh.com.br)

