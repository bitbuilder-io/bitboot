# CLAUDE.md - AI Assistant Instructions for BitBoot

This document provides context and guidance for AI assistants working with the BitBoot repository.

## Project Overview

BitBoot is a multiboot USB system that produces unified kernel images (UKIs) serving as meta-bootloaders. It combines ZFSBootMenu, netboot.xyz, and systemd-boot into portable EFI binaries with the capability to pull and boot raw disk images directly from HTTP/HTTPS sources at boot time using systemd v258's `rd.systemd.pull` functionality.

## Key Concepts

### Unified Kernel Images (UKI)
- Each boot profile has its own `.efi` file in `/EFI/bitboot/`
- UKIs embed: kernel, initramfs, command line, and OS release info
- Built using `ukify` (preferred) or `objcopy` (fallback)
- Boot entries reference UKIs with `efi` directive, NOT `linux`/`initrd`/`options`

### rd.systemd.pull
- Core innovation leveraging systemd v258's import generator
- Downloads raw disk images over HTTP/HTTPS at boot time
- Format: `rd.systemd.pull=raw,machine,verify=no,blockdev:<name>:<url>`
- Images are loopback-mounted before pivot root

### Boot Flow
1. UEFI loads systemd-boot from ESP
2. User selects boot entry from menu
3. Selected UKI is executed
4. Embedded initramfs sets up network
5. `rd.systemd.pull` downloads image (if configured)
6. Root filesystem mounted (from download or local)
7. Pivot root to target OS

## Repository Structure

```
bitboot/
├── .github/workflows/     # CI/CD pipelines
├── config/
│   ├── cmdline.d/         # Base kernel cmdline fragments
│   │   └── profiles/      # Per-profile cmdline (embedded in UKIs)
│   └── loader/            # systemd-boot configuration
│       ├── loader.conf
│       └── entries/       # Boot menu entries (reference UKIs)
├── initramfs/             # Initramfs configuration and hooks
├── scripts/               # Build scripts
├── Containerfile          # Build environment
└── Makefile              # Build orchestration
```

## Important Patterns

### Boot Entry Format (CORRECT)
```ini
title     Profile Name
efi       /EFI/bitboot/profile-name.efi
```

### Boot Entry Format (WRONG - Do NOT use)
```ini
title     Profile Name
linux     /vmlinuz-...
initrd    /initramfs-...
options   ...
```

### Profile Command Lines
- Located in `config/cmdline.d/profiles/<profile>.conf`
- One parameter per line (easier to read/edit)
- Comments with `#` are stripped during build
- Embedded into corresponding UKI at build time

## Build System

### Local Build
```bash
make all          # Build everything
make deps         # Fetch ZFSBootMenu, netboot.xyz, Alpine
make initramfs    # Build custom initramfs
make uki          # Build all profile UKIs
make usb          # Create bootable USB image
```

### Container Build
```bash
make container    # Build in Fedora 41 container
```

### Single Profile Build
```bash
./scripts/build-uki.sh --profile fedora-coreos
```

## Supported Profiles

| Profile | Type | Notes |
|---------|------|-------|
| fedora-coreos | rd.systemd.pull | DDI raw image |
| flatcar | rd.systemd.pull | Container Linux |
| alpine-zfs-installer | Netboot | ZFS installation environment |
| alpine-netboot | Netboot | Lightweight RAM-based |
| nixos-kexec | Kexec | Unique boot model |
| vyos | Netboot+squashfs | Router OS |
| zfsbootmenu | Chainload | ZFS BE management |
| netboot | Chainload | iPXE network boot |
| bitboot | Recovery | Shell with ZFS support |

## Common Tasks

### Adding a New Profile
1. Create cmdline file: `config/cmdline.d/profiles/<name>.conf`
2. Create boot entry: `config/loader/entries/<name>.conf`
3. Run `make uki` to build the new UKI

### Updating Image URLs
1. Edit the profile's cmdline file in `config/cmdline.d/profiles/`
2. Rebuild with `make uki`

### Testing Locally
1. Build USB image: `make usb`
2. Write to USB: `dd if=build/bitboot-x86_64.img of=/dev/sdX bs=4M`
3. Boot from USB on test machine

## Dependencies

- systemd v258+ (for rd.systemd.pull)
- ukify or objcopy (for UKI creation)
- dracut (for initramfs)
- parted, gdisk, dosfstools (for USB image)
- curl/wget (for fetching deps)

## Testing Notes

- UKIs can be tested in QEMU with OVMF
- Network boot profiles require internet connectivity
- ZFS profiles require ZFS kernel modules

## Security Considerations

- Default profiles use `verify=no` for simplicity
- Production deployments should use `verify=signature` with proper GPG keys
- Secure Boot signing available via `--sign` option
