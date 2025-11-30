#!/bin/bash
# BitBoot Initramfs Builder
# Builds the custom initramfs with systemd v258+ and rd.systemd.pull support
#
# Usage: ./build-initramfs.sh [options]
#
# Options:
#   --output FILE     Output initramfs file (default: ./build/initramfs-bitboot.img)
#   --kernel VERSION  Kernel version to build for (default: running kernel)
#   --config FILE     Configuration file (default: ./initramfs/config.yaml)
#   --modules DIR     Custom modules directory (default: ./initramfs/modules)
#   --hooks DIR       Custom hooks directory (default: ./initramfs/hooks)
#   -h, --help        Show this help message

set -euo pipefail

# Default values
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_FILE="${PROJECT_DIR}/build/initramfs-bitboot.img"
KERNEL_VERSION=""
CONFIG_FILE="${PROJECT_DIR}/initramfs/config.yaml"
MODULES_DIR="${PROJECT_DIR}/initramfs/modules"
HOOKS_DIR="${PROJECT_DIR}/initramfs/hooks"

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
    head -18 "$0" | grep '^#' | tail -n +2 | sed 's/^# \?//'
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --kernel)
            KERNEL_VERSION="$2"
            shift 2
            ;;
        --config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --modules)
            MODULES_DIR="$2"
            shift 2
            ;;
        --hooks)
            HOOKS_DIR="$2"
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

# Create output directory
mkdir -p "$(dirname "${OUTPUT_FILE}")"

# Detect kernel version
if [[ -z "${KERNEL_VERSION}" ]]; then
    KERNEL_VERSION=$(uname -r)
fi
log_info "Building initramfs for kernel: ${KERNEL_VERSION}"

# Check for dracut
if ! command -v dracut >/dev/null 2>&1; then
    log_error "dracut not found. Please install dracut."
    exit 1
fi

# Check systemd version
SYSTEMD_VERSION=$(systemctl --version | head -1 | awk '{print $2}')
if [[ "${SYSTEMD_VERSION}" -lt 258 ]]; then
    log_warn "systemd version ${SYSTEMD_VERSION} detected. rd.systemd.pull requires v258+."
    log_warn "Some features may not work correctly."
fi

# Install custom modules to dracut modules directory
DRACUT_MODULES_DIR="/usr/lib/dracut/modules.d"
BITBOOT_MODULE_DIR="${DRACUT_MODULES_DIR}/99bitboot"

log_info "Installing BitBoot dracut modules..."
mkdir -p "${BITBOOT_MODULE_DIR}"

# Copy module files
if [[ -d "${MODULES_DIR}" ]]; then
    for module in "${MODULES_DIR}"/*.sh; do
        if [[ -f "${module}" ]]; then
            install -m 755 "${module}" "${BITBOOT_MODULE_DIR}/"
        fi
    done
fi

# Copy hook files
if [[ -d "${HOOKS_DIR}" ]]; then
    for hook in "${HOOKS_DIR}"/*.sh; do
        if [[ -f "${hook}" ]]; then
            install -m 755 "${hook}" "${BITBOOT_MODULE_DIR}/"
        fi
    done
fi

# Create module-setup.sh if not exists
if [[ ! -f "${BITBOOT_MODULE_DIR}/module-setup.sh" ]]; then
    cat > "${BITBOOT_MODULE_DIR}/module-setup.sh" << 'MODSETUP'
#!/bin/bash
# BitBoot Dracut Module

check() {
    return 0
}

depends() {
    echo systemd systemd-initrd network
}

install() {
    # Install bitboot scripts
    for script in "${moddir}"/*.sh; do
        [[ -f "${script}" ]] && [[ "$(basename "${script}")" != "module-setup.sh" ]] && \
            inst_simple "${script}" "/usr/lib/bitboot/$(basename "${script}")"
    done
    
    # Install compression tools
    inst_multiple -o xz zstd gzip bzip2 lz4
    
    # Install network tools
    inst_multiple -o curl wget
    
    # Install block device tools
    inst_multiple -o losetup blockdev
    
    # Create necessary directories
    mkdir -p "${initdir}/var/lib/machines"
    mkdir -p "${initdir}/run/machines"
}

installkernel() {
    instmods loop overlay squashfs
    instmods =drivers/net/ethernet
}
MODSETUP
    chmod 755 "${BITBOOT_MODULE_DIR}/module-setup.sh"
fi

# Build dracut command line arguments
DRACUT_ARGS=(
    --force
    --kver "${KERNEL_VERSION}"
    --add "systemd systemd-initrd network-manager"
    --add "bitboot"
    --install "curl wget xz zstd gzip bzip2 losetup"
    --include "/etc/ssl/certs" "/etc/ssl/certs"
)

# Add ZFS if available
if modinfo zfs >/dev/null 2>&1; then
    DRACUT_ARGS+=(--add "zfs")
fi

# Add additional modules based on config (simple parsing)
if [[ -f "${CONFIG_FILE}" ]]; then
    log_info "Reading configuration from ${CONFIG_FILE}"
fi

log_info "Building initramfs with dracut..."
log_info "Command: dracut ${DRACUT_ARGS[*]} ${OUTPUT_FILE}"

dracut "${DRACUT_ARGS[@]}" "${OUTPUT_FILE}"

# Verify output
if [[ -f "${OUTPUT_FILE}" ]]; then
    log_info "Successfully built initramfs: ${OUTPUT_FILE}"
    log_info "Size: $(du -h "${OUTPUT_FILE}" | cut -f1)"
    
    # List contents summary
    if command -v lsinitrd >/dev/null 2>&1; then
        log_info "Initramfs contents summary:"
        lsinitrd "${OUTPUT_FILE}" 2>/dev/null | head -20 || true
    fi
else
    log_error "Failed to build initramfs"
    exit 1
fi

log_info "Initramfs build complete!"
