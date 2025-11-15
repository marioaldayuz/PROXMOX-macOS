# Hackintoshster

> **Transform any computer into a macOS powerhouse**

Break free from hardware limitations. Hackintoshster delivers a seamless macOS virtualization experience on Proxmox VE, whether you're running AMD or Intel silicon. Perfect for developers, designers, and anyone who needs macOS without the Apple tax.

---

## 🎯 What is This?

Hackintoshster is an intelligent automation toolkit that handles the heavy lifting of modern macOS virtualization. With a single command, you'll have a production-ready virtual machine running the latest macOS releases: Sequoia (15) and Tahoe (26).

No kernel patching. No complicated guides. Just pure, vanilla macOS running in a hypervisor environment.

### Why Hackintoshster?

- **Universal Hardware Support**: Works with both AMD and Intel processors
- **Zero Manual Configuration**: Automated setup handles QEMU/KVM, OpenCore, and EFI configuration
- **Production Ready**: Includes proper SIP implementation and Apple-signed DMG support
- **Modern macOS Focus**: Optimized for macOS 15 (Sequoia) and 26 (Tahoe) with VirtIO drivers
- **Cloud Compatible**: Run your virtual Mac on VPS providers like Vultr
- **True Vanilla Experience**: No kernel modifications means system stability and update compatibility
- **Dynamic ISO Generation**: Creates custom OpenCore ISOs with pre-injected SMBIOS for each VM

---

## ⚡ Quick Start

### Step 1: Install on Proxmox

You'll need a fresh installation of Proxmox VE (versions 7.0.x through 9.0.x fully supported).

1. Open your Proxmox web interface
2. Navigate to: `Datacenter → [Your Node] → Shell`
3. Execute these commands:

```bash
cd /root && git clone https://github.com/marioaldayuz/hackintoshster-main.git
cd hackintoshster-main && chmod +x install.sh && ./install.sh
```

4. **System will reboot** to apply kernel changes
5. After reboot, you're ready to create VMs!

### What the Installer Does

**System Configuration:**
- Installs essential packages: `vim`, `git`, `jq`, `rsync`, `genisoimage`, `dosfstools`, `wget`, `curl`
- Configures UTF-8 locale for proper character encoding
- Creates `mac` command alias for quick access

**Kernel Optimization:**
- Enables IOMMU (AMD-Vi or Intel VT-d) for PCI passthrough
- Configures VFIO modules for GPU passthrough support
- Applies kernel parameter patches for specific Proxmox versions
- Blacklists conflicting GPU and audio drivers
- Suppresses KVM MSR warnings

**GRUB Configuration:**
- Sets boot timeout to 0 for faster startup
- Applies platform-specific IOMMU parameters (AMD or Intel)
- Enables nested virtualization support

### Step 2: Create Your First macOS VM

After the reboot, simply run:

```bash
mac
```

This launches the interactive menu. Choose your macOS version (Sequoia or Tahoe) and follow the wizard!

---

## 🚀 Creating macOS VMs

### Interactive Mode (Recommended for First-Time Users)

```bash
mac
```

The wizard will guide you through:
1. **macOS Version**: Choose Sequoia (15) or Tahoe (26)
2. **VM Configuration**: ID, name, disk size, CPU cores, RAM
3. **Storage & Network**: Select storage pool and network bridge
4. **SMBIOS Generation**: Automatic via API or offline GenSMBIOS
5. **Custom ISO Creation**: Builds OpenCore ISO with your unique serial
6. **Recovery Download**: Optional macOS installer download from Apple

### Non-Interactive Mode (Command Line)

For automation or scripting:

```bash
mac --version sequoia --vmid 100 --name MyMac --disk 120 --cores 8 --download-recovery
```

#### CLI Options

```
--version <sequoia|tahoe>    macOS version to install (required)
--vmid <id>                  VM ID (default: next available)
--name <name>                VM name (default: macOS-SEQUOIA)
--disk <size>                Disk size in GB (default: 80)
--storage <storage>          Proxmox storage (default: auto-detect)
--bridge <bridge>            Network bridge (default: vmbr0)
--cores <count>              CPU cores, power of 2 (default: 4)
--ram <size>                 RAM in MiB (default: 4GB + 1GB/core)
--download-recovery          Download macOS recovery from Apple
--help                       Show help message
```

#### CLI Examples

**Minimal (uses all defaults):**
```bash
mac --version sequoia
```

**Custom resources:**
```bash
mac --version tahoe --vmid 105 --name DevMachine --disk 200 --cores 8 --ram 16384
```

**Cloud deployment:**
```bash
mac --version sequoia --bridge vmbr1 --storage local-lvm --download-recovery
```

---

## 🔧 Custom OpenCore ISO System

### What Makes This Special?

Hackintoshster **dynamically generates** a custom OpenCore ISO for each VM with:
- ✅ **Unique SMBIOS**: Pre-injected Serial, MLB, UUID, ROM values
- ✅ **Bootable BOOT.img**: RAW FAT16 image containing your EFI configuration
- ✅ **Supporting Tools**: GenSMBIOS, ProperTree, EFI utilities included
- ✅ **Setup Script**: One-click macOS post-installation automation

### The Build Process

When you create a VM, here's what happens automatically:

1. **SMBIOS Generation**
   - Attempts API fetch for Apple-validated serial
   - Falls back to GenSMBIOS if API unavailable
   - Generates: Serial, Board Serial, UUID, ROM

2. **EFI Configuration**
   - Copies base PROXMOX-EFI configuration
   - Injects SMBIOS values into `config.plist`
   - Includes all required kexts (Lilu, VMHide, VirtualSMC, WhateverGreen)

3. **BOOT.img Creation**
   - Creates RAW FAT16 filesystem image (no partition table)
   - Copies EFI directory with your custom configuration
   - Size: Auto-calculated based on EFI contents + 20% overhead
   - Format: Matches proven UEFI boot specifications

4. **ISO Assembly**
   - Packages BOOT.img, Supporting Tools, documentation
   - Creates bootable ISO using El Torito specification
   - Names it: `OpenCore-{YourSerial}.iso`

### What's in the Custom ISO?

```
OpenCore-C02YD3ZBHX87.iso
├── BOOT.img (bootable FAT16 image with your config)
├── EFI_NEW/
│   └── EFI/
│       └── OC/
│           ├── config.plist (with your serial)
│           ├── Kexts/ (Lilu, VMHide, VirtualSMC, etc.)
│           └── OpenCore.efi
├── Supporting_Tools/
│   ├── GenSMBIOS/
│   ├── ocvalidate/
│   └── Core_Tools/ (Lilu, VMHide releases)
├── macOS-Setup.command (one-click setup script)
├── README.md
├── BUILD_INFO.txt
└── COPYRIGHT.md
```

---

## 🍎 macOS Installation Process

### Step 1: Boot Your VM

After VM creation completes:

1. In Proxmox web UI, select your VM
2. Click **Start**
3. Click **Console** to open the VM display

The VM will boot to the OpenCore picker showing:
- **macOS Installer** (from recovery image)
- **EFI Internal Shell** (ignore this)

### Step 2: Format the Disk

The VM disk must be formatted before macOS can be installed.

1. Select **macOS Installer** from the OpenCore boot menu
2. Wait for macOS Recovery to load (Apple logo with progress bar)
3. When macOS Utilities appears, select **Disk Utility** → **Continue**

**Disk Utility Steps:**

4. In the top-left corner, click **View** → Select **Show All Devices**
   - This ensures you see the entire disk, not just volumes

5. In the left sidebar, select the **top-level disk** (not a partition)
   - Look for: **QEMU HARDDISK Media** or similar (the one without "disk0s" numbers)
   - Should show your disk size (e.g., "85.90 GB")

6. Click **Erase** button at the top

7. Configure the disk:
   - **Name**: `Macintosh HD` (or your preferred name)
   - **Format**: **APFS**
   - **Scheme**: **GUID Partition Map**
   
   ⚠️ **Critical**: Make sure "Scheme" says "GUID Partition Map" - if you don't see this option, you didn't select the top-level disk

8. Click **Erase** button in the dialog

9. Wait for the format to complete (usually 10-30 seconds)

10. You should now see:
    - **Macintosh HD** (APFS Volume)
    - **Macintosh HD - Data** (APFS Volume - auto-created)

11. Click **Done**, then close Disk Utility (Cmd+Q or Disk Utility → Quit)

### Step 3: Install macOS

1. From macOS Utilities, choose **Install macOS [Sequoia/Tahoe]**

2. Click **Continue** through the introduction screens

3. **Accept** the license agreement

4. **Select Disk**: Choose **Macintosh HD** (the disk you just formatted)

5. Click **Install**

6. Installation begins:
   - Progress bar will show (takes 20-40 minutes depending on host speed)
   - VM will **reboot automatically** several times - this is normal
   - Each reboot shows the OpenCore picker - select **Macintosh HD** if it doesn't auto-select

7. After the final reboot, you'll see the **macOS Setup Assistant**

### Step 4: Complete macOS Setup Assistant

The macOS Setup Assistant will guide you through initial configuration:

1. **Select Country/Region**: Choose your country → Continue

2. **Written and Spoken Languages**: Select your language → Continue

3. **Accessibility**: Skip unless needed → Continue

4. **Data & Privacy**: Read and click Continue

5. **Migration Assistant**: Select **Not Now** (fresh installation)

6. **Sign In with Apple ID**: 
   - ⚠️ **Select "Set Up Later"** (don't sign in yet!)
   - Reason: iCloud requires proper SMBIOS - wait until after post-install script

7. **Terms and Conditions**: Agree to continue

8. **Create Computer Account**:
   - Full Name: Your name
   - Account Name: Your username (lowercase, no spaces)
   - Password: Create a strong password
   - Hint: Optional
   - Click **Continue**

9. **Express Set Up**: Choose **Customize Settings** for more control, or **Continue** for defaults

10. **Analytics**: Choose whether to share analytics with Apple

11. **Screen Time**: Choose **Set Up Later**

12. **Siri**: Enable or disable based on preference

13. **Choose Your Look**: Select **Light**, **Dark**, or **Auto**

14. Wait for macOS to finalize setup (1-2 minutes)

15. **Welcome to macOS!** You'll now see the desktop

### Step 5: Run Post-Installation Script

Once you reach the macOS desktop:

1. Mount the OpenCore ISO:
   - In Proxmox, ensure the custom ISO is still attached to the VM
   - In macOS Finder, you'll see the ISO mounted automatically
   - Or double-click the ISO file if it's on your desktop

2. Open the mounted ISO and locate `macOS-Setup.command`

3. **Double-click** `macOS-Setup.command`

4. The script will:
   - ✅ **Disable GateKeeper** (allows unsigned apps)
   - ✅ **Mount EFI partition** on your boot disk
   - ✅ **Install OpenCore to boot disk** (copies EFI from BOOT.img)
   - ✅ **Install Homebrew** (package manager)
   - ✅ **Install Python 3** (for utilities)
   - ✅ **Copy Supporting Tools** to Desktop
   - ✅ **Verify system** (kexts, SMBIOS, CPU)

5. **Reboot** when prompted

### Step 6: Remove Installation Media

After successful boot from the internal disk:

1. In Proxmox web UI: **Hardware → CD/DVD Drive → Remove**
2. Optionally delete the custom ISO to free space:
   ```bash
   rm /var/lib/vz/template/iso/OpenCore-{YourSerial}.iso
   rm /var/lib/vz/template/iso/sequoia.iso  # or tahoe.iso
   ```

**Done! Your macOS VM is now fully configured and boots independently.**

---

## 🎛️ Automatic VM Configuration

The script configures your VM with optimal settings:

### CPU Configuration
- **Model**: Skylake-Client-v4 with CPUID 165 (Comet Lake compatibility)
- **Performance**: ~30-44% better than host passthrough
- **Platform Detection**: Automatically adjusts for AMD vs Intel hosts
  - **AMD**: Disables pcid, spec-ctrl; sets GenuineIntel vendor
  - **Intel**: Enables invtsc, kvm_pv_unhalt, kvm_pv_eoi

### Storage
- **Type**: VirtIO block device (fastest)
- **Cache**: None (safe for power loss)
- **Discard**: Enabled (TRIM support)
- **Size**: 80GB default (customizable)

### Network
- **Adapter**: VirtIO (required for macOS 15+)
- **Bridge**: vmbr0 default (customizable)
- **Performance**: Near-native speeds

### Boot Configuration
- **BIOS**: OVMF (UEFI)
- **EFI Disk**: 4MB EFI storage
- **Boot Order**: OpenCore ISO → Internal Disk
- **Media Type**: disk (not cdrom - macOS requirement)

### Hardware Emulation
- **USB**: XHCI controller with keyboard and tablet
- **Graphics**: VMware compatible (800x600 initial)
- **Machine**: Q35 chipset
- **QEMU Args**: Apple SMC device, ICH9-LPC hotplug workaround

---

## 📦 Included Kernel Extensions

All essential kexts are pre-loaded by OpenCore (no manual installation needed):

- **Lilu.kext**: Kernel extension patching framework
- **VMHide.kext**: Hides VM signatures from macOS
- **VirtualSMC.kext**: Emulates Apple SMC for hardware monitoring
- **WhateverGreen.kext**: Graphics card patches for compatibility
- **VoodooPS2Controller.kext**: PS/2 keyboard/mouse support
- **QemuUSBTablet.kext**: QEMU USB tablet support
- **AppleIntelE1000.kext**: Intel E1000 network adapter

All kexts are loaded at boot - **no System/Library/Extensions installation required**.

---

## 🔍 Technical Details

### BOOT.img Format

The custom ISOs use a special boot image format:

- **Type**: RAW FAT16 filesystem (no partition table, no MBR)
- **Size**: Dynamically calculated (EFI size + 20% overhead)
- **Contents**: Complete EFI directory with injected SMBIOS
- **Bootable**: Yes - uses El Torito no-emulation boot specification
- **Mountable**: Yes - can be opened on macOS by double-clicking

This format ensures:
- ✅ UEFI firmware can read and boot from it
- ✅ macOS can mount it for inspection
- ✅ Contains your unique serial configuration

### EFI Structure

```
EFI_NEW/
└── EFI/
    ├── BOOT/
    │   └── BOOTx64.efi (UEFI boot entry)
    └── OC/
        ├── OpenCore.efi
        ├── config.plist (with your serial)
        ├── ACPI/ (SSDT patches)
        ├── Drivers/ (HfsPlus, OpenRuntime, etc.)
        ├── Kexts/ (all essential kexts)
        └── Resources/ (boot UI assets)
```

### Recovery Image Format

Recovery images are simplified:
- **Naming**: `sequoia.iso`, `tahoe.iso` (not recovery-sequoia.iso)
- **Format**: FAT32 disk image
- **Source**: Official Apple recovery servers
- **Size**: ~1.4GB
- **Reusable**: Can be used for multiple VMs

---

## 🔧 Post-Installation Automation

### The macOS-Setup.command Script

Each custom ISO includes an automated setup script. When you double-click it, here's what happens:

**Step 1: Disable GateKeeper**
- Allows running unsigned applications and scripts
- Required for many developer tools and utilities
- Command: `sudo spctl --master-disable`

**Step 2: Mount EFI Partition**
- Mounts `/dev/disk0s1` (EFI partition) to `/Volumes/EFI`
- Creates mount point if needed
- Check if already mounted to avoid conflicts

**Step 3: Install Custom EFI Configuration**
- Mounts the BOOT.img from the ISO
- Backs up any existing EFI configuration (timestamped)
- Copies your custom OpenCore config to the boot disk
- **This is critical**: Transfers the EFI with your unique serial to the internal disk

**Step 4: Install Homebrew**
- macOS package manager
- Required for developer tools
- Auto-detects Apple Silicon vs Intel

**Step 5: Install Python 3**
- Via Homebrew for simplicity
- Needed for various macOS utilities

**Step 6: Copy Supporting Tools**
- Copies to `~/Desktop/Supporting_Tools`
- Includes: GenSMBIOS, ProperTree, ocvalidate, etc.

**Step 7: System Verification**
- Checks all kexts are loaded (Lilu, VMHide, VirtualSMC, WhateverGreen)
- Verifies GateKeeper status
- Confirms EFI installation
- Displays SMBIOS information
- Shows CPU details

**All done automatically** - just enter your password when prompted!

---

## 📋 System Requirements

### Proxmox Host

**Minimum:**
- Proxmox VE 7.0 or later
- 2 CPU cores available
- 8GB RAM
- 100GB free storage
- Stable TSC (Timestamp Counter)

**Recommended:**
- Proxmox VE 8.x or 9.x
- 8+ CPU cores
- 32GB+ RAM
- NVMe SSD storage
- Hardware supporting IOMMU/VT-d

### macOS VM Resources

**Minimum:**
- 2 CPU cores
- 4GB RAM
- 80GB disk

**Recommended:**
- 4-8 CPU cores (power of 2: 2, 4, 8, 16)
- 8-16GB RAM (auto-calculated: 4GB + 1GB per core)
- 120-200GB disk (APFS benefits from extra space)
- VirtIO storage and network adapters

---

## 🚨 Important: TSC Requirement

Modern macOS (15+) requires a **stable Timestamp Counter (TSC)**. If your system has an unstable TSC, VMs may crash.

### Check Your TSC

In Proxmox shell:

```bash
dmesg | grep -i -e tsc -e clocksource
```

**Good (what you want):**
```
clocksource: Switched to clocksource tsc
```

**Problem:**
```
tsc: Marking TSC unstable due to check_tsc_sync_source failed
clocksource: Switched to clocksource hpet
```

### Fix TSC Issues

**Option 1: BIOS Settings (Recommended)**
1. Disable ErP mode
2. Disable all C-state power management
3. Perform complete power cycle (unplug, wait 30s, replug)

**Option 2: Force TSC in GRUB (Less Stable)**
1. Edit `/etc/default/grub`
2. Add to `GRUB_CMDLINE_LINUX_DEFAULT`: `clocksource=tsc tsc=reliable`
3. Run `update-grub` and reboot

**Verify:**
```bash
cat /sys/devices/system/clocksource/clocksource0/current_clocksource
```
Must return: `tsc`

---

## 🛠️ Advanced Features

### Menu System

Run `mac` to access:

**VM Management:**
- **SEQ / TAH**: Create Sequoia or Tahoe VMs
- **CCP**: Customize OpenCore config.plist (boot-args, SIP, SMBIOS, timeout)
- **CRI**: Clear recovery images to free disk space

**System Utilities:**
- **NVE**: Add Proxmox no-subscription repository
- **RPS**: Remove Proxmox subscription notice
- **NBR**: Create new network bridges for VMs

### Custom ISO Building (Manual)

Advanced users can build ISOs manually:

```bash
# Generate SMBIOS first
cd /root/hackintoshster-main
./Supporting_Tools/Misc_Tools/GenSMBIOS/GenSMBIOS.command

# Build custom ISO
./scripts/build-custom-iso.sh \
  --efi-source "Builder_EFIs/PROXMOX-EFI" \
  --smbios-json "/path/to/smbios.json" \
  --output-dir "/var/lib/vz/template/iso" \
  --script-dir "/root/hackintoshster-main"
```

### Network Bridge Creation

Create isolated networks for your VMs:

```bash
mac  # Enter menu
# Select "NBR - New Bridge"
```

Configure:
- Bridge name (vmbr1, vmbr2, etc.)
- Subnet (e.g., 10.10.10.0/24)
- Gateway IP
- Optional DHCP server

---

## 🐛 Troubleshooting

### macOS 26 (Tahoe) Cursor Freeze

**Symptom**: Cursor randomly freezes in Tahoe VMs

**Fix**: Use virtio-tablet-pci device

```bash
# In Proxmox shell (replace 100 with your VM ID)
qm set 100 -args "$(qm config 100 --current | grep ^args: | cut -d' ' -f2-) -device virtio-tablet"
```

Then in Proxmox web UI: VM Options → Disable "Use tablet for pointer"

**Note**: With virtio-tablet, middle-click acts as right-click.

### VM Boots to UEFI Shell

**Causes:**
1. BOOT.img not properly created
2. ISO not attached to VM
3. Boot order incorrect

**Solutions:**
1. Verify ISO is attached: Proxmox → VM Hardware → CD/DVD Drive
2. Check boot order: Should show OpenCore ISO first
3. Rebuild custom ISO
4. In UEFI Shell, manually run: `fs0:\EFI_NEW\EFI\BOOT\BOOTx64.efi`

### OpenCore "Failed to parse configuration"

**Cause**: Corrupted config.plist XML

**Fix**: The base config has been fixed. Rebuild your custom ISO.

### Can't Mount BOOT.img on Mac

**Cause**: BOOT.img format issue

**Fix**: Ensure `dosfstools` is installed on Proxmox:
```bash
apt install dosfstools
```

Then rebuild the ISO. BOOT.img should be RAW FAT16 (no partition table).

### EFI Not Copied to Boot Disk

**Symptom**: VM won't boot after removing ISO

**Fix**: Re-run `macOS-Setup.command` from the mounted ISO. It will:
1. Mount BOOT.img
2. Copy EFI directory to `/Volumes/EFI/EFI/`
3. Verify installation

---

## 💡 Best Practices

### Resource Allocation

**CPU Cores**: Use power-of-2 counts (2, 4, 8, 16) for optimal scheduling
- Minimum: 2 cores
- Recommended: 4-8 cores
- Maximum: Don't exceed 50% of host cores

**RAM**: More is better for modern macOS
- Minimum: 4GB
- Recommended: 8-16GB
- Formula: 4GB base + 1GB per CPU core

**Storage**: SSD strongly recommended
- Minimum: 80GB
- Recommended: 120-200GB
- Format: VirtIO for performance
- TRIM: Enabled for SSD longevity

### Security

**macOS Side:**
- Keep GateKeeper disabled only if needed
- Enable FileVault for encryption
- Configure iCloud services after SMBIOS setup

**Proxmox Side:**
- Use unique SMBIOS for each VM
- Don't share serial numbers between VMs
- Keep OpenCore updated
- Regular VM backups

### Performance Optimization

1. **Use VirtIO everywhere**: Storage and network
2. **Disable memory ballooning**: Set balloon to 0
3. **SSD storage**: NVMe if possible
4. **Dedicated cores**: Consider CPU pinning for production VMs
5. **GPU passthrough**: For graphics-intensive work

---

## 🔄 Updates and Maintenance

### Update Hackintoshster

```bash
cd /root/hackintoshster-main
git pull origin main
```

### Update OpenCore (via menu)

```bash
mac
# Select: OCI - Update OpenCore ISO
```

This downloads the latest generic OpenCore ISO. Your custom ISOs remain unchanged.

### Clear Recovery Images

Free up disk space by removing cached recovery images:

```bash
mac
# Select: CRI - Clear all macOS recovery images
```

This deletes `sequoia.iso` and `tahoe.iso` from your ISO storage. They'll be re-downloaded when needed.

---

## 📚 Project Structure

```
hackintoshster-main/
├── setup (main script - aliased as 'mac')
├── install.sh (one-time Proxmox configuration)
├── Builder_EFIs/
│   └── PROXMOX-EFI/ (base OpenCore configuration)
│       ├── BOOT.img (reference boot image)
│       ├── boot.catalog (El Torito catalog)
│       ├── EFI_NEW/EFI/ (OpenCore with config.plist)
│       ├── Mount_EFI.command
│       ├── Disable_GateKeeper.command
│       └── Install_Python3.command
├── scripts/
│   ├── build-custom-iso.sh (ISO builder)
│   ├── create-boot-img.sh (BOOT.img generator)
│   ├── inject-smbios.sh (config.plist injector)
│   ├── generate-macos-setup.sh (post-install script generator)
│   └── detect-processor.sh (deprecated)
├── Supporting_Tools/
│   ├── Misc_Tools/
│   │   ├── GenSMBIOS/ (SMBIOS generator)
│   │   ├── macrecovery/ (recovery downloader)
│   │   └── ocvalidate/ (config validator)
│   └── Core_Tools/
│       ├── Lilu-1.7.1-RELEASE/
│       └── VMHide-2.0.0-RELEASE/
└── logs/ (operation logs for troubleshooting)
```

---

## 🌐 Cloud Deployment

### Tested VPS Providers

- **Vultr**: Full support with nested virtualization
- Requires "Bare Metal" or dedicated CPU instances
- Enable virtualization in Proxmox: `qm set VMID -cpu host,hidden=1`

### Cloud Best Practices

1. **Storage**: Use high-performance storage (NVMe)
2. **Network**: Create custom bridges for isolation
3. **Security**: Configure firewall rules
4. **Backups**: Regular snapshots recommended

---

## 🛡️ Legal & Compliance

**This tool is provided for development, educational, and testing purposes only.**

- You are responsible for ensuring compliance with Apple's EULA
- Intended for learning about virtualization and operating systems
- The author assumes no liability for misuse or damages
- Always maintain backups before system modifications

**OpenCore License**: BSD 3-Clause
**Hackintoshster**: MIT License (see COPYRIGHT.md)

---

## 🎓 Learning Resources

**Included Documentation:**
- Supporting_Tools/OpenCore_Docs/ (ACPI tables, configuration guides)
- BUILD_INFO.txt (in each custom ISO)
- Verbose logging (all operations logged to `logs/`)

**External Resources:**
- [OpenCore Documentation](https://github.com/acidanthera/OpenCorePkg)
- [Dortania's OpenCore Guide](https://dortania.github.io/)
- QEMU CPU optimization for macOS guests

---

## 🤝 Contributing

Found a bug? Have a suggestion? Contributions are welcome!

1. Fork the repository
2. Create a feature branch
3. Make your changes with clear commit messages
4. Test thoroughly
5. Submit a pull request

---

## 📬 About

**Created by Mario Aldayuz (thenotoriousllama)**

More projects: [aldayuz.com](https://aldayuz.com)

**Version**: 2025.11.23
**OpenCore**: 1.0.6

---

## 🎉 Credits

This project builds upon the excellent work of:
- **Acidanthera** - OpenCore bootloader and kernel extensions
- **Dortania** - Comprehensive OpenCore guides
- **OpenCore Community** - Continuous improvements and support

Special thanks to the Hackintosh and Proxmox communities for making this possible.

---

Built with ❤️ for the Hackintosh community. May your kernels panic infrequently and your boot times be swift.
