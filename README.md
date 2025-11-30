# BitBoot

**Multiboot USB System with Network Image Pull Support**

BitBoot is a revolutionary boot system that creates unified kernel images (UKIs) capable of booting raw disk images directly from HTTP/HTTPS sources. Built on systemd v258's `rd.systemd.pull` functionality, it combines ZFSBootMenu, netboot.xyz, and systemd-boot into a single portable USB drive.

## Features

- 🌐 **Network Boot**: Pull and boot raw disk images from HTTP/HTTPS at boot time
- 📀 **Multiple Profiles**: Pre-configured entries for Fedora CoreOS, Flatcar, Alpine, NixOS, VyOS
- 🔧 **ZFSBootMenu Integration**: Full ZFS recovery and boot environment management
- 🖧 **netboot.xyz**: Access to dozens of network-bootable operating systems
- 🔒 **Secure Boot Ready**: Optional signing for Secure Boot compatibility
- 📦 **Unified Kernel Images**: Single EFI files with embedded kernel, initramfs, and cmdline

## Quick Start

### Download Pre-built Image

```bash
# Download latest release
wget https://github.com/bitbuilder-io/bitboot/releases/latest/download/bitboot-x86_64.img.xz

# Write to USB (replace /dev/sdX with your USB device)
xzcat bitboot-x86_64.img.xz | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
```

### Build from Source

```bash
# Clone repository
git clone https://github.com/bitbuilder-io/bitboot.git
cd bitboot

# Build everything
make all

# Or build in container (recommended)
make container
```

## Boot Profiles

BitBoot includes pre-configured profiles for various operating systems:

### Tier 1: Network Pull (rd.systemd.pull)

| Profile | Description |
|---------|-------------|
| **Fedora CoreOS** | Container-optimized OS with GPT auto-discovery |
| **Flatcar Container Linux** | Production-ready container host |

### Tier 2: Network Boot

| Profile | Description |
|---------|-------------|
| **Alpine Linux ZFS Installer** | ZFS-capable installation environment |
| **Alpine Linux Netboot** | Lightweight RAM-based Linux |
| **NixOS Kexec Installer** | Declarative Linux installer |
| **VyOS 1.5 Rolling** | Network router OS |

### Tier 3: Chainload

| Profile | Description |
|---------|-------------|
| **ZFSBootMenu** | ZFS boot environment manager |
| **netboot.xyz** | iPXE network boot menu |
| **BitBoot Recovery** | Emergency shell with ZFS tools |

## How It Works

### Boot Flow

```
UEFI → systemd-boot → Select Profile → Load UKI → Network Setup → 
  → rd.systemd.pull (download image) → Loopback Mount → Pivot Root → Boot OS
```

### Key Technology: rd.systemd.pull

Introduced in systemd v258, `rd.systemd.pull` enables downloading and booting from raw disk images:

```
rd.systemd.pull=raw,machine,verify=no,blockdev:<name>:<url>
```

- Downloads image to `/run/machines/`
- Attaches to loopback device
- Supports xz, zstd, gzip, bzip2 compression
- GPT auto-discovery for partition detection

## Repository Structure

```
bitboot/
├── .github/workflows/        # CI/CD pipelines
│   ├── build.yml            # Build on push/PR
│   └── release.yml          # Tagged releases
├── config/
│   ├── cmdline.d/           # Kernel command line
│   │   ├── base.conf        # Common options
│   │   ├── network.conf     # Network prerequisites
│   │   └── profiles/        # Per-profile cmdlines
│   └── loader/
│       ├── loader.conf      # systemd-boot config
│       └── entries/         # Boot menu entries
├── initramfs/
│   ├── config.yaml          # Initramfs configuration
│   ├── hooks/               # Dracut hooks
│   └── modules/             # Custom modules
├── scripts/
│   ├── build-uki.sh         # UKI assembly
│   ├── build-initramfs.sh   # Initramfs generation
│   ├── fetch-deps.sh        # Download dependencies
│   └── create-usb.sh        # USB image creation
├── Containerfile            # Build environment
├── Makefile                 # Build orchestration
├── CLAUDE.md               # AI assistant instructions
└── README.md               # This file
```

## USB Image Layout

```
ESP (FAT32)/
├── EFI/
│   ├── BOOT/
│   │   └── BOOTX64.EFI     # Default boot (bitboot.efi)
│   ├── bitboot/
│   │   ├── bitboot.efi     # Recovery shell
│   │   ├── fedora-coreos.efi
│   │   ├── flatcar.efi
│   │   ├── alpine-zfs-installer.efi
│   │   └── ...
│   ├── zbm/
│   │   └── zfsbootmenu.efi
│   └── netboot/
│       └── netboot.xyz.efi
├── loader/
│   ├── loader.conf
│   └── entries/
│       ├── fedora-coreos.conf
│       ├── zfsbootmenu.conf
│       └── ...
└── alpine/                  # Alpine netboot files
```

## Building

### Prerequisites

- Linux system with systemd v258+
- `ukify` or `objcopy` for UKI creation
- `dracut` for initramfs generation
- `parted`, `gdisk`, `dosfstools` for USB image
- `curl` or `wget` for downloading dependencies

### Make Targets

```bash
make all        # Build everything
make deps       # Fetch ZFSBootMenu, netboot.xyz, Alpine
make initramfs  # Build custom initramfs
make uki        # Build all profile UKIs
make usb        # Create bootable USB image
make clean      # Remove build artifacts
make container  # Build using container
make check      # Verify build outputs
```

### Environment Variables

```bash
BUILD_DIR=build     # Output directory
SIGN=false          # Enable Secure Boot signing
SIGN_KEY=           # Signing key path
SIGN_CERT=          # Signing certificate path
```

### Single Profile Build

```bash
./scripts/build-uki.sh --profile fedora-coreos
```

## Customization

### Adding a New Profile

1. Create cmdline file:
   ```bash
   cat > config/cmdline.d/profiles/myprofile.conf << 'EOF'
   # My custom profile cmdline
   rd.systemd.pull=raw,machine,verify=no,blockdev:myimage:https://example.com/image.raw.xz
   root=gpt-auto
   ip=dhcp
   EOF
   ```

2. Create boot entry:
   ```bash
   cat > config/loader/entries/myprofile.conf << 'EOF'
   title     My Custom Profile
   efi       /EFI/bitboot/myprofile.efi
   EOF
   ```

3. Build:
   ```bash
   make uki
   ```

### Secure Boot Signing

```bash
make uki SIGN=true SIGN_KEY=/path/to/key.pem SIGN_CERT=/path/to/cert.pem
```

## ZFS Installation Support

BitBoot is designed for Root-on-ZFS installations. The Alpine ZFS Installer profile provides:

- Pre-loaded ZFS kernel modules
- Full ZFS userspace tools (zpool, zfs, zdb)
- Partition tools (parted, gdisk, cryptsetup)
- Writable tmpfs overlay for installing packages
- Network tools for downloading additional components

Follow the [OpenZFS Root on ZFS guide](https://openzfs.github.io/openzfs-docs/Getting%20Started/Arch%20Linux/Root%20on%20ZFS.html) directly from the BitBoot USB.

## Requirements

### Build System
- systemd v258+ (for rd.systemd.pull support)
- Fedora 41+ or equivalent (recommended)
- 4GB+ disk space for build

### Target System
- UEFI-capable x86_64 system
- 512MB+ USB drive
- 4GB+ RAM (for network boot profiles)
- Network connection (for rd.systemd.pull profiles)

## Troubleshooting

### Boot Menu Not Showing
- Press Space or any key during boot
- Check `timeout` setting in `loader.conf`

### Network Pull Fails
- Verify network connectivity (`ip=dhcp` in cmdline)
- Check image URL is accessible
- Ensure sufficient RAM for image download

### ZFS Not Available
- Use Alpine ZFS Installer profile
- Or ZFSBootMenu for existing ZFS systems

## References

- [systemd-import-generator(8)](https://man7.org/linux/man-pages/man8/systemd-import-generator.8.html)
- [systemd v258 Release Notes](https://github.com/systemd/systemd/releases/tag/v258)
- [ZFSBootMenu Documentation](https://docs.zfsbootmenu.org/)
- [netboot.xyz](https://netboot.xyz/)
- [UAPI Group UKI Specification](https://uapi-group.org/specifications/specs/unified_kernel_image/)
- [OpenZFS Root on ZFS](https://openzfs.github.io/openzfs-docs/Getting%20Started/Arch%20Linux/Root%20on%20ZFS.html)

## License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## Acknowledgments

- [ZFSBootMenu](https://github.com/zbm-dev/zfsbootmenu) team
- [netboot.xyz](https://github.com/netbootxyz/netboot.xyz) project
- systemd developers for rd.systemd.pull functionality