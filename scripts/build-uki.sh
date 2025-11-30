#!/bin/bash
# BitBoot UKI Assembly Script
# Builds unified kernel images (*.efi) for each boot profile, combining:
# - systemd-stub as UEFI loader
# - Custom initramfs with rd.systemd.pull support
# - Linux kernel with required drivers
# - Profile-specific embedded kernel command line
#
# Usage: ./build-uki.sh [options]
#
# Options:
#   --output DIR      Output directory (default: ./build)
#   --kernel PATH     Kernel image path (default: auto-detect)
#   --initrd PATH     Initramfs image path (default: auto-detect)
#   --profile NAME    Build only specific profile (default: all)
#   --profiles-dir    Directory with profile cmdline files (default: config/cmdline.d/profiles)
#   --osrel FILE      os-release file (default: /etc/os-release)
#   --sign            Sign the UKI for Secure Boot
#   --key PATH        Secure Boot signing key
#   --cert PATH       Secure Boot signing certificate
#   -h, --help        Show this help message

set -euo pipefail

# Default values
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${PROJECT_DIR}/build"
KERNEL=""
INITRD=""
PROFILE=""
PROFILES_DIR="${PROJECT_DIR}/config/cmdline.d/profiles"
OSREL="/etc/os-release"
SIGN=false
SIGN_KEY=""
SIGN_CERT=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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
    head -25 "$0" | grep '^#' | tail -n +2 | sed 's/^# \?//'
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --output)
            BUILD_DIR="$2"
            shift 2
            ;;
        --kernel)
            KERNEL="$2"
            shift 2
            ;;
        --initrd)
            INITRD="$2"
            shift 2
            ;;
        --profile)
            PROFILE="$2"
            shift 2
            ;;
        --profiles-dir)
            PROFILES_DIR="$2"
            shift 2
            ;;
        --osrel)
            OSREL="$2"
            shift 2
            ;;
        --sign)
            SIGN=true
            shift
            ;;
        --key)
            SIGN_KEY="$2"
            shift 2
            ;;
        --cert)
            SIGN_CERT="$2"
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

# Create build directory
mkdir -p "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}/efi"

# Auto-detect kernel if not specified
if [[ -z "${KERNEL}" ]]; then
    # Try common kernel paths
    for kpath in \
        /boot/vmlinuz-linux-lts \
        /boot/vmlinuz-linux \
        /lib/modules/*/vmlinuz \
        /boot/vmlinuz
    do
        if [[ -f "${kpath}" ]]; then
            KERNEL="${kpath}"
            break
        fi
    done
    
    if [[ -z "${KERNEL}" ]]; then
        log_error "Could not find kernel image. Use --kernel to specify."
        exit 1
    fi
fi
log_info "Using kernel: ${KERNEL}"

# Auto-detect initramfs if not specified
if [[ -z "${INITRD}" ]]; then
    # Try common initramfs paths
    for ipath in \
        "${BUILD_DIR}/initramfs-bitboot.img" \
        /boot/initramfs-linux-lts.img \
        /boot/initramfs-linux.img \
        /boot/initrd.img
    do
        if [[ -f "${ipath}" ]]; then
            INITRD="${ipath}"
            break
        fi
    done
    
    if [[ -z "${INITRD}" ]]; then
        log_warn "No initramfs found. Building one..."
        "${SCRIPT_DIR}/build-initramfs.sh" --output "${BUILD_DIR}/initramfs-bitboot.img"
        INITRD="${BUILD_DIR}/initramfs-bitboot.img"
    fi
fi
log_info "Using initramfs: ${INITRD}"

# Find systemd-stub
STUB=""
for stub_path in \
    /usr/lib/systemd/boot/efi/linuxx64.efi.stub \
    /usr/lib/systemd/boot/efi/linuxia32.efi.stub \
    /lib/systemd/boot/efi/linuxx64.efi.stub \
    /usr/share/systemd/bootctl/linuxx64.efi.stub
do
    if [[ -f "${stub_path}" ]]; then
        STUB="${stub_path}"
        break
    fi
done

if [[ -z "${STUB}" ]]; then
    log_error "Could not find systemd-stub. Install systemd-boot."
    exit 1
fi
log_info "Using systemd-stub: ${STUB}"

# Function to build a single UKI
build_uki() {
    local profile_name="$1"
    local cmdline_file="$2"
    local output_file="${BUILD_DIR}/efi/${profile_name}.efi"
    
    log_info "Building UKI for profile: ${profile_name}"
    
    # Create cmdline from profile file
    local cmdline_temp="${BUILD_DIR}/${profile_name}-cmdline.txt"
    grep -v '^\s*#' "${cmdline_file}" | grep -v '^\s*$' | tr '\n' ' ' > "${cmdline_temp}"
    echo "" >> "${cmdline_temp}"
    
    log_info "  Cmdline: $(cat ${cmdline_temp})"
    
    if command -v ukify >/dev/null 2>&1; then
        local ukify_args=(
            build
            --linux="${KERNEL}"
            --initrd="${INITRD}"
            --cmdline="@${cmdline_temp}"
            --os-release="@${OSREL}"
            --output="${output_file}"
        )
        
        # Add splash image if available
        if [[ -f "${PROJECT_DIR}/assets/splash.bmp" ]]; then
            ukify_args+=(--splash="${PROJECT_DIR}/assets/splash.bmp")
        fi
        
        # Add signing if requested
        if [[ "${SIGN}" == "true" ]] && [[ -n "${SIGN_KEY}" ]] && [[ -n "${SIGN_CERT}" ]]; then
            ukify_args+=(
                --secureboot-private-key="${SIGN_KEY}"
                --secureboot-certificate="${SIGN_CERT}"
            )
        fi
        
        ukify "${ukify_args[@]}"
        
    elif command -v objcopy >/dev/null 2>&1; then
        # Calculate section offsets
        local align=4096
        
        local osrel_size cmdline_size kernel_size
        osrel_size=$(stat -c%s "${OSREL}")
        cmdline_size=$(stat -c%s "${cmdline_temp}")
        kernel_size=$(stat -c%s "${KERNEL}")
        
        # Calculate offsets (must be aligned)
        local osrel_offs=0x10000
        local cmdline_offs linux_offs initrd_offs
        cmdline_offs=$(printf "0x%x" $(( (osrel_offs + osrel_size + align - 1) / align * align )))
        linux_offs=$(printf "0x%x" $(( ($(printf "%d" "${cmdline_offs}") + cmdline_size + align - 1) / align * align )))
        initrd_offs=$(printf "0x%x" $(( ($(printf "%d" "${linux_offs}") + kernel_size + align - 1) / align * align )))
        
        objcopy \
            --add-section .osrel="${OSREL}" --change-section-vma .osrel="${osrel_offs}" \
            --add-section .cmdline="${cmdline_temp}" --change-section-vma .cmdline="${cmdline_offs}" \
            --add-section .linux="${KERNEL}" --change-section-vma .linux="${linux_offs}" \
            --add-section .initrd="${INITRD}" --change-section-vma .initrd="${initrd_offs}" \
            "${STUB}" "${output_file}"
        
        # Sign if requested
        if [[ "${SIGN}" == "true" ]] && [[ -n "${SIGN_KEY}" ]] && [[ -n "${SIGN_CERT}" ]]; then
            if command -v sbsign >/dev/null 2>&1; then
                sbsign --key "${SIGN_KEY}" --cert "${SIGN_CERT}" --output "${output_file}" "${output_file}"
            else
                log_warn "sbsign not found. UKI will not be signed."
            fi
        fi
    else
        log_error "Neither ukify nor objcopy found. Cannot build UKI."
        return 1
    fi
    
    # Cleanup temp file
    rm -f "${cmdline_temp}"
    
    # Verify the output
    if [[ -f "${output_file}" ]]; then
        log_info "  Built: ${output_file} ($(du -h "${output_file}" | cut -f1))"
    else
        log_error "  Failed to build UKI: ${output_file}"
        return 1
    fi
}

# Build UKIs for profiles
log_info "Building UKIs from profiles in: ${PROFILES_DIR}"

if [[ -n "${PROFILE}" ]]; then
    # Build single profile
    profile_file="${PROFILES_DIR}/${PROFILE}.conf"
    if [[ -f "${profile_file}" ]]; then
        build_uki "${PROFILE}" "${profile_file}"
    else
        log_error "Profile not found: ${profile_file}"
        exit 1
    fi
else
    # Build all profiles
    if [[ -d "${PROFILES_DIR}" ]]; then
        for profile_file in "${PROFILES_DIR}"/*.conf; do
            if [[ -f "${profile_file}" ]]; then
                profile_name=$(basename "${profile_file}" .conf)
                build_uki "${profile_name}" "${profile_file}"
            fi
        done
    else
        log_error "Profiles directory not found: ${PROFILES_DIR}"
        exit 1
    fi
fi

# List all built UKIs
log_info "Built UKIs:"
find "${BUILD_DIR}/efi" -name "*.efi" -exec ls -lh {} \; 2>/dev/null || true

log_info "UKI build complete!"
