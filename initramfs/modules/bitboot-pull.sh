#!/bin/bash
# BitBoot Module - rd.systemd.pull handler
#
# This module provides support for the rd.systemd.pull kernel command line
# parameter introduced in systemd v258. It enables downloading and booting
# from raw disk images over HTTP/HTTPS at boot time.
#
# Usage in kernel cmdline:
#   rd.systemd.pull=raw,machine,verify=no,blockdev:<name>:<url>
#
# Example:
#   rd.systemd.pull=raw,machine,verify=no,blockdev:rootdisk:https://example.com/image.raw.xz

# Module metadata
DRACUT_MODULE_NAME="bitboot-pull"
DRACUT_MODULE_VERSION="1.0.0"
DRACUT_MODULE_DESCRIPTION="BitBoot rd.systemd.pull support module"

# Check if this module should be included
check() {
    # Check for systemd v258+ with import-generator support
    if [[ -x /usr/lib/systemd/system-generators/systemd-import-generator ]]; then
        return 0
    fi
    return 1
}

# Module dependencies
depends() {
    echo systemd systemd-initrd network-manager
}

# Install files into initramfs
install() {
    # Core systemd-import binaries
    inst_multiple -o \
        /usr/lib/systemd/systemd-importd \
        /usr/lib/systemd/systemd-import \
        /usr/lib/systemd/systemd-pull \
        /usr/lib/systemd/system-generators/systemd-import-generator
    
    # Compression tools for decompressing pulled images
    inst_multiple -o \
        xz xzcat unxz \
        zstd zstdcat unzstd \
        gzip gunzip zcat \
        bzip2 bunzip2 bzcat \
        lz4 lz4cat unlz4
    
    # Network utilities for HTTP/HTTPS downloads
    inst_multiple -o \
        curl wget
    
    # Block device utilities
    inst_multiple -o \
        losetup blockdev
    
    # CA certificates for HTTPS
    inst_simple /etc/ssl/certs/ca-certificates.crt
    inst_dir /etc/ssl/certs
    inst_dir /etc/pki/tls/certs
    
    # systemd units for importd
    for unit in \
        systemd-importd.service \
        systemd-importd.socket \
        dbus-org.freedesktop.import1.service
    do
        inst_simple "/usr/lib/systemd/system/${unit}" 2>/dev/null || true
    done
    
    # D-Bus configuration
    inst_simple /usr/share/dbus-1/system-services/org.freedesktop.import1.service 2>/dev/null || true
    inst_simple /usr/share/dbus-1/system.d/org.freedesktop.import1.conf 2>/dev/null || true
    inst_simple /etc/dbus-1/system.d/org.freedesktop.import1.conf 2>/dev/null || true
    
    # Create necessary directories
    mkdir -p "${initdir}/var/lib/machines"
    mkdir -p "${initdir}/run/machines"
    mkdir -p "${initdir}/run/systemd/machines"
    
    # Enable socket activation for importd
    systemctl -q --root "$initdir" enable systemd-importd.socket 2>/dev/null || true
    
    # Install a hook script to ensure network is up before pulling
    inst_hook pre-mount 10 "$moddir/bitboot-pull-premount.sh"
}

# Install kernel modules
installkernel() {
    # Loop device for attaching downloaded images
    instmods loop
    
    # Filesystem modules for mounted images
    instmods ext4 xfs btrfs squashfs overlay
    
    # GPT partition support for auto-discovery
    instmods nls_cp437 nls_iso8859_1 vfat
}
