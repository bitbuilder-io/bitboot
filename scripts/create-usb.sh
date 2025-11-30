#!/bin/bash
# BitBoot USB Image Creator
# Creates a bootable USB image with BitBoot UKI and boot configurations
#
# Usage: ./create-usb.sh [options]
#
# Options:
#   --output FILE     Output image file (default: ./build/bitboot-x86_64.img)
#   --size SIZE       Image size in MB (default: 512)
#   --uki PATH        Path to bitboot.efi (default: ./build/bitboot.efi)
#   --deps DIR        Dependencies directory (default: ./build/deps)
#   --config DIR      Config directory (default: ./config)
#   --label LABEL     ESP partition label (default: BITBOOT)
#   -h, --help        Show this help message
#
# The resulting image can be written to USB with:
#   dd if=bitboot-x86_64.img of=/dev/sdX bs=4M status=progress

set -euo pipefail

# Default values
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_IMG="${PROJECT_DIR}/build/bitboot-x86_64.img"
IMG_SIZE_MB=512
UKI_PATH="${PROJECT_DIR}/build/bitboot.efi"
DEPS_DIR="${PROJECT_DIR}/build/deps"
CONFIG_DIR="${PROJECT_DIR}/config"
ESP_LABEL="BITBOOT"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

usage() {
    head -20 "$0" | grep '^#' | tail -n +2 | sed 's/^# \?//'
    exit 0
}

cleanup() {
    if [[ -n "${MOUNT_POINT:-}" ]] && mountpoint -q "${MOUNT_POINT}" 2>/dev/null; then
        umount "${MOUNT_POINT}" || true
    fi
    if [[ -n "${LOOP_DEV:-}" ]]; then
        losetup -d "${LOOP_DEV}" 2>/dev/null || true
    fi
    if [[ -n "${MOUNT_POINT:-}" ]]; then
        rmdir "${MOUNT_POINT}" 2>/dev/null || true
    fi
}

trap cleanup EXIT

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --output)
            OUTPUT_IMG="$2"
            shift 2
            ;;
        --size)
            IMG_SIZE_MB="$2"
            shift 2
            ;;
        --uki)
            UKI_PATH="$2"
            shift 2
            ;;
        --deps)
            DEPS_DIR="$2"
            shift 2
            ;;
        --config)
            CONFIG_DIR="$2"
            shift 2
            ;;
        --label)
            ESP_LABEL="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            ;;
    esac
done

# Check for root privileges (needed for loop devices and mounting)
if [[ $EUID -ne 0 ]]; then
    log_warn "This script typically requires root privileges for loop devices."
    log_warn "Attempting to continue, but may fail..."
fi

# Create output directory
mkdir -p "$(dirname "${OUTPUT_IMG}")"

log_info "Creating BitBoot USB image..."
log_info "Output: ${OUTPUT_IMG}"
log_info "Size: ${IMG_SIZE_MB}MB"

# Create empty image file
log_info "Creating empty image file..."
dd if=/dev/zero of="${OUTPUT_IMG}" bs=1M count="${IMG_SIZE_MB}" status=progress 2>/dev/null || \
    truncate -s "${IMG_SIZE_MB}M" "${OUTPUT_IMG}"

# Create GPT partition table with EFI System Partition
log_info "Creating GPT partition table..."
if command -v sgdisk >/dev/null 2>&1; then
    sgdisk --zap-all "${OUTPUT_IMG}" >/dev/null 2>&1 || true
    sgdisk --new=1:2048:0 --typecode=1:EF00 --change-name=1:"${ESP_LABEL}" "${OUTPUT_IMG}"
elif command -v parted >/dev/null 2>&1; then
    parted -s "${OUTPUT_IMG}" mklabel gpt
    parted -s "${OUTPUT_IMG}" mkpart "${ESP_LABEL}" fat32 1MiB 100%
    parted -s "${OUTPUT_IMG}" set 1 esp on
else
    log_error "Neither sgdisk nor parted found. Cannot create partition table."
    exit 1
fi

# Set up loop device
log_info "Setting up loop device..."
LOOP_DEV=$(losetup --find --show --partscan "${OUTPUT_IMG}")
log_info "Loop device: ${LOOP_DEV}"

# Wait for partition device to appear
sleep 1
PART_DEV="${LOOP_DEV}p1"
if [[ ! -b "${PART_DEV}" ]]; then
    # Try alternative naming
    PART_DEV="${LOOP_DEV}1"
fi
if [[ ! -b "${PART_DEV}" ]]; then
    log_error "Partition device not found: ${PART_DEV}"
    exit 1
fi

# Format ESP as FAT32
log_info "Formatting ESP as FAT32..."
mkfs.vfat -F 32 -n "${ESP_LABEL}" "${PART_DEV}"

# Mount ESP
MOUNT_POINT=$(mktemp -d)
log_info "Mounting ESP at ${MOUNT_POINT}..."
mount "${PART_DEV}" "${MOUNT_POINT}"

# Create directory structure
log_info "Creating directory structure..."
mkdir -p "${MOUNT_POINT}/EFI/BOOT"
mkdir -p "${MOUNT_POINT}/EFI/bitboot"
mkdir -p "${MOUNT_POINT}/EFI/zbm"
mkdir -p "${MOUNT_POINT}/EFI/netboot"
mkdir -p "${MOUNT_POINT}/loader/entries"
mkdir -p "${MOUNT_POINT}/alpine"
mkdir -p "${MOUNT_POINT}/nixos"
mkdir -p "${MOUNT_POINT}/vyos"

# Copy BitBoot UKIs
if [[ -d "${BUILD_DIR}/efi" ]]; then
    log_info "Installing BitBoot UKIs..."
    mkdir -p "${MOUNT_POINT}/EFI/bitboot"
    cp "${BUILD_DIR}/efi/"*.efi "${MOUNT_POINT}/EFI/bitboot/" 2>/dev/null || true
    
    # Use bitboot.efi as the default UEFI boot entry
    if [[ -f "${BUILD_DIR}/efi/bitboot.efi" ]]; then
        cp "${BUILD_DIR}/efi/bitboot.efi" "${MOUNT_POINT}/EFI/BOOT/BOOTX64.EFI"
    fi
elif [[ -f "${UKI_PATH}" ]]; then
    log_info "Installing BitBoot UKI (legacy single-file mode)..."
    mkdir -p "${MOUNT_POINT}/EFI/bitboot"
    cp "${UKI_PATH}" "${MOUNT_POINT}/EFI/BOOT/BOOTX64.EFI"
    cp "${UKI_PATH}" "${MOUNT_POINT}/EFI/bitboot/bitboot.efi"
else
    log_warn "No BitBoot UKI found"
fi

# Copy ZFSBootMenu
if [[ -f "${DEPS_DIR}/zbm/zfsbootmenu.efi" ]]; then
    log_info "Installing ZFSBootMenu..."
    cp "${DEPS_DIR}/zbm/zfsbootmenu.efi" "${MOUNT_POINT}/EFI/zbm/"
fi

# Copy netboot.xyz
if [[ -f "${DEPS_DIR}/netboot/netboot.xyz.efi" ]]; then
    log_info "Installing netboot.xyz..."
    cp "${DEPS_DIR}/netboot/netboot.xyz.efi" "${MOUNT_POINT}/EFI/netboot/"
fi
if [[ -f "${DEPS_DIR}/netboot/netboot.xyz-snponly.efi" ]]; then
    cp "${DEPS_DIR}/netboot/netboot.xyz-snponly.efi" "${MOUNT_POINT}/EFI/netboot/"
fi

# Copy Alpine Linux files
if [[ -d "${DEPS_DIR}/alpine" ]]; then
    log_info "Installing Alpine Linux files..."
    cp -r "${DEPS_DIR}/alpine/"* "${MOUNT_POINT}/alpine/" 2>/dev/null || true
fi

# Copy loader configuration
if [[ -f "${CONFIG_DIR}/loader/loader.conf" ]]; then
    log_info "Installing boot loader configuration..."
    cp "${CONFIG_DIR}/loader/loader.conf" "${MOUNT_POINT}/loader/"
fi

# Copy boot entries
if [[ -d "${CONFIG_DIR}/loader/entries" ]]; then
    log_info "Installing boot entries..."
    cp "${CONFIG_DIR}/loader/entries/"*.conf "${MOUNT_POINT}/loader/entries/" 2>/dev/null || true
fi

# Create a startup.nsh for UEFI shell fallback
cat > "${MOUNT_POINT}/startup.nsh" << 'EOF'
@echo -off
echo BitBoot - Multiboot USB System
echo.
echo Starting BitBoot...
\EFI\BOOT\BOOTX64.EFI
EOF

# Sync and unmount
log_info "Syncing and unmounting..."
sync
umount "${MOUNT_POINT}"
losetup -d "${LOOP_DEV}"
LOOP_DEV=""
rmdir "${MOUNT_POINT}"
MOUNT_POINT=""

# Show result
log_info "USB image created successfully!"
log_info "Image: ${OUTPUT_IMG}"
log_info "Size: $(du -h "${OUTPUT_IMG}" | cut -f1)"
echo ""
log_info "To write to USB drive:"
echo "  sudo dd if=${OUTPUT_IMG} of=/dev/sdX bs=4M status=progress conv=fsync"
echo ""
log_info "Or use a GUI tool like:"
echo "  - balenaEtcher"
echo "  - Rufus (Windows)"
echo "  - GNOME Disks"
