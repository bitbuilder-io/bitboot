#!/bin/bash
# BitBoot Dependencies Fetcher
# Downloads ZFSBootMenu, netboot.xyz, and other required components
#
# Usage: ./fetch-deps.sh [options]
#
# Options:
#   --output DIR      Output directory (default: ./build/deps)
#   --zbm-version VER ZFSBootMenu version (default: latest)
#   --netboot-version Netboot.xyz version (default: latest)
#   --alpine-version  Alpine Linux version (default: edge)
#   --skip-zbm        Skip ZFSBootMenu download
#   --skip-netboot    Skip netboot.xyz download
#   --skip-alpine     Skip Alpine Linux download
#   -h, --help        Show this help message

set -euo pipefail

# Default values
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="${PROJECT_DIR}/build/deps"
ZBM_VERSION="latest"
NETBOOT_VERSION="latest"
ALPINE_VERSION="edge"
SKIP_ZBM=false
SKIP_NETBOOT=false
SKIP_ALPINE=false

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

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --zbm-version)
            ZBM_VERSION="$2"
            shift 2
            ;;
        --netboot-version)
            NETBOOT_VERSION="$2"
            shift 2
            ;;
        --alpine-version)
            ALPINE_VERSION="$2"
            shift 2
            ;;
        --skip-zbm)
            SKIP_ZBM=true
            shift
            ;;
        --skip-netboot)
            SKIP_NETBOOT=true
            shift
            ;;
        --skip-alpine)
            SKIP_ALPINE=true
            shift
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

# Create output directories
mkdir -p "${OUTPUT_DIR}/zbm"
mkdir -p "${OUTPUT_DIR}/netboot"
mkdir -p "${OUTPUT_DIR}/alpine"

# Function to download with retries
download_file() {
    local url="$1"
    local output="$2"
    local retries=3
    
    log_info "Downloading: ${url}"
    for ((i=1; i<=retries; i++)); do
        if curl -fsSL --connect-timeout 30 --max-time 300 -o "${output}" "${url}"; then
            log_info "Downloaded: ${output}"
            return 0
        else
            log_warn "Download attempt ${i}/${retries} failed"
            sleep 2
        fi
    done
    log_error "Failed to download: ${url}"
    return 1
}

# Fetch ZFSBootMenu
fetch_zfsbootmenu() {
    log_info "Fetching ZFSBootMenu..."
    
    local zbm_api="https://api.github.com/repos/zbm-dev/zfsbootmenu/releases"
    local zbm_url
    
    if [[ "${ZBM_VERSION}" == "latest" ]]; then
        zbm_url=$(curl -fsSL "${zbm_api}/latest" | grep -oP '"browser_download_url":\s*"\K[^"]+\.EFI' | head -1)
    else
        zbm_url=$(curl -fsSL "${zbm_api}/tags/${ZBM_VERSION}" | grep -oP '"browser_download_url":\s*"\K[^"]+\.EFI' | head -1)
    fi
    
    if [[ -z "${zbm_url}" ]]; then
        log_error "Could not find ZFSBootMenu EFI download URL"
        return 1
    fi
    
    download_file "${zbm_url}" "${OUTPUT_DIR}/zbm/zfsbootmenu.efi"
    
    # Also download the recovery image if available
    local zbm_recovery_url
    if [[ "${ZBM_VERSION}" == "latest" ]]; then
        zbm_recovery_url=$(curl -fsSL "${zbm_api}/latest" | grep -oP '"browser_download_url":\s*"\K[^"]+recovery[^"]+\.EFI' | head -1 || true)
    else
        zbm_recovery_url=$(curl -fsSL "${zbm_api}/tags/${ZBM_VERSION}" | grep -oP '"browser_download_url":\s*"\K[^"]+recovery[^"]+\.EFI' | head -1 || true)
    fi
    if [[ -n "${zbm_recovery_url}" ]]; then
        download_file "${zbm_recovery_url}" "${OUTPUT_DIR}/zbm/zfsbootmenu-recovery.efi" || true
    fi
}

# Fetch netboot.xyz
fetch_netboot() {
    log_info "Fetching netboot.xyz..."
    
    local netboot_api="https://api.github.com/repos/netbootxyz/netboot.xyz/releases"
    local netboot_url
    
    if [[ "${NETBOOT_VERSION}" == "latest" ]]; then
        netboot_url=$(curl -fsSL "${netboot_api}/latest" | grep -oP '"browser_download_url":\s*"\K[^"]+netboot\.xyz\.efi"' | tr -d '"' | head -1)
        if [[ -z "${netboot_url}" ]]; then
            # Fallback to direct URL
            netboot_url="https://boot.netboot.xyz/ipxe/netboot.xyz.efi"
        fi
    else
        netboot_url="https://github.com/netbootxyz/netboot.xyz/releases/download/${NETBOOT_VERSION}/netboot.xyz.efi"
    fi
    
    download_file "${netboot_url}" "${OUTPUT_DIR}/netboot/netboot.xyz.efi"
    
    # Also download the SNPONLY version for broader hardware support
    local netboot_snp_url="https://boot.netboot.xyz/ipxe/netboot.xyz-snponly.efi"
    download_file "${netboot_snp_url}" "${OUTPUT_DIR}/netboot/netboot.xyz-snponly.efi" || true
}

# Fetch Alpine Linux netboot files
fetch_alpine() {
    log_info "Fetching Alpine Linux netboot files..."
    
    local alpine_base="https://dl-cdn.alpinelinux.org/alpine/${ALPINE_VERSION}/releases/x86_64/netboot"
    
    # Download kernel
    download_file "${alpine_base}/vmlinuz-lts" "${OUTPUT_DIR}/alpine/vmlinuz-lts"
    
    # Download initramfs
    download_file "${alpine_base}/initramfs-lts" "${OUTPUT_DIR}/alpine/initramfs-lts"
    
    # Download modloop (for ZFS and other modules)
    download_file "${alpine_base}/modloop-lts" "${OUTPUT_DIR}/alpine/modloop-lts"
    
}

# Main execution
log_info "Starting dependency fetch..."
log_info "Output directory: ${OUTPUT_DIR}"

if [[ "${SKIP_ZBM}" != "true" ]]; then
    fetch_zfsbootmenu || log_warn "ZFSBootMenu fetch failed, continuing..."
fi

if [[ "${SKIP_NETBOOT}" != "true" ]]; then
    fetch_netboot || log_warn "netboot.xyz fetch failed, continuing..."
fi

if [[ "${SKIP_ALPINE}" != "true" ]]; then
    fetch_alpine || log_warn "Alpine Linux fetch failed, continuing..."
fi

# List downloaded files
log_info "Downloaded dependencies:"
find "${OUTPUT_DIR}" -type f -exec ls -lh {} \; 2>/dev/null || true

log_info "Dependency fetch complete!"
