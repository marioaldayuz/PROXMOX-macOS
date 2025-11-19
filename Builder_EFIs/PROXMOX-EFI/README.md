# 🍏 Hackintosher EFI for macOS 15 & 26

**Maintained by Mario Aldayuz (thenotoriousllama)**  
**Email:** [mario@aldayuz.com](mailto:mario@aldayuz.com)

---

## 💡 Overview

**Hackintosher** is an EFI and configuration resource designed to simplify the setup of macOS **Sequoia (15)** and **Tahoe (26)** in Proxmox or on bare-metal Hackintosh systems.  
Built for reliability, minimalism, and educational use, it provides a reference implementation for OpenCore-based macOS installations.

This repository includes:  
- Tested EFI build for Proxmox VE systems  
- Configurations for virtualization and direct hardware deployment  
- Comprehensive documentation on BIOS, ACPI, and driver (kext) setup

---

## 📚 Technical References

This project draws from established Hackintosh community resources and documentation, including:

- [**Dortania OpenCore Guide**](https://dortania.github.io/)
- [**OpenCore Post-Install Guide**](https://dortania.github.io/OpenCore-Post-Install/)
- [**OpenCore Project on GitHub**](https://github.com/acidanthera)
- [**ProperTree Project on GitHub**](https://github.com/corpnewt/ProperTree)
- [**Lilu Project on GitHub**](https://github.com/acidanthera/Lilu)
- [**VMHide Project on GitHub**](https://github.com/Carnations-Botanica/VMHide)
- [**LongQT-sea OpenCore-ISO Guide for Proxmox**](https://github.com/LongQT-sea/OpenCore-ISO)

---

## ⚙️ Versioning

- **EFI Version:** 1.0.0  
- **OpenCore Base:** 1.0.6  
- **Supported macOS Versions:** 15 (Sequoia) and 26 (Tahoe)  
- **Last Updated:** November 2025

---

## 💻 Directory Layout

```bash
/EFI
├── BOOT/
├── OC/
│   ├── ACPI/
│   ├── Drivers/
│   ├── Kexts/
│   ├── Tools/
│   └── config.plist
/Docs/
└── Scripts/
```

---

## 🧩 Supported Hardware

| Component          | Model / Example Details      |
| ------------------ | ---------------------------- |
| **Motherboard**    | N/A - Virtualized q35        |
| **CPU**            | Intel Skylake                |
| **GPU**            | Untested GPUs                |
| **Bootloader**     | OpenCore 1.0.6               |
| **Virtualization** | Proxmox VE 8.1–9.0           |

---

## 🧠 BIOS Configuration

**Disable:**
- Fast Boot
- Secure Boot
- CSM (Compatibility Support Module)
- Serial/COM and Parallel Ports

**Enable:**
- Above 4G Decoding
- EHCI/XHCI Hand-Off
- SATA Mode: AHCI
- OS Type: Windows 8.1/10 UEFI Mode

---

## 🔧 macOS Compatibility

| macOS Version | Configuration Notes |
| -------------- | ------------------- |
| **15 Sequoia** | Requires `SecureBootModel` disabled during install |
| **26 Tahoe** | Ensure proper TSC stability; see [Hackintoshster documentation](https://github.com/marioaldayuz/PROXMOX-macOS) |

After installation, you may re-enable `SecureBootModel` and SIP as desired.

---

## 🧰 Essential Tools

| Tool | Purpose |
|------|----------|
| **ProperTree** | Edit `config.plist` |
| **GenSMBIOS** | Generate valid SMBIOS serials |
| **MountEFI** | Mount EFI partitions from macOS |
| **ocvalidate** | Validate OpenCore configuration integrity |

---

## 📦 Core Kexts Included

| Kext | Purpose |
|------|----------|
| [**Lilu.kext**](https://github.com/acidanthera/Lilu) | Core patching framework |
| [**VirtualSMC.kext**](https://github.com/acidanthera/VirtualSMC) | Emulates SMC chip |
| [**WhateverGreen.kext**](https://github.com/acidanthera/WhateverGreen) | Graphics fixes & framebuffer patches |
| [**AppleMCEReporterDisabler.kext**](https://github.com/acidanthera/bugtracker/files/3703498/AppleMCEReporterDisabler.kext.zip) | Prevents kernel panics on AMD systems |
| [**NVMeFix.kext**](https://github.com/acidanthera/NVMeFix) | Fixes NVMe drive power management |
| [**RestrictEvents.kext**](https://github.com/acidanthera/RestrictEvents) | Improves CPU and system compatibility |

---

## ⚡ ACPI & Core Patches

ACPI tables included under `/EFI/OC/ACPI` ensure full hardware compatibility. Reference Dortania’s guide for manual patching.  
For AMD users, adjust the `Force cpuid_cores_per_package` patch to match your CPU core count.

| Core Count | Hexadecimal |
|-------------|-------------|
| 2 | 02 |
| 4 | 04 |
| 6 | 06 |
| 8 | 08 |
| 12 | 0C |
| 16 | 10 |
| 24 | 18 |
| 32 | 20 |

---

## 🔒 Legal Notice

This repository is for **educational and research purposes only**.  
Running macOS on non-Apple hardware may violate Apple’s End User License Agreement (EULA).  
You assume all responsibility for compliance with applicable **United States laws**.

---

## 📄 License

### BSD-3-Clause License

**Copyright (c) 2025, Mario Aldayuz (thenotoriousllama)**  
**All rights reserved.**

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this list of conditions, and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions, and the following disclaimer in the documentation and/or other materials provided with the distribution.
3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

**Disclaimer:**  
THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS “AS IS” AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

---

## ☕ Support This Project

If this repository or its resources have been useful, consider supporting future development:

[**Buy Me a Bourbon**](https://aldayuz.com/buy-me-bourbon) 🥃

Your contribution helps maintain open documentation and continued EFI support for macOS virtualization and Hackintosh environments.

---

### 📬 Contact

For partnership inquiries, technical questions, or licensing requests:  
**Email:** [mario@aldayuz.com](mailto:mario@aldayuz.com)

---

**Crafted with precision and purpose for macOS enthusiasts and virtualization professionals.**

