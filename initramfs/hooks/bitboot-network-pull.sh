#!/bin/bash
# BitBoot Dracut Hook - Network Pull Support
#
# This hook ensures systemd-import-generator and related services
# are properly configured for rd.systemd.pull functionality
#
# Place in /usr/lib/dracut/modules.d/99bitboot/module-setup.sh

check() {
    require_binaries systemd-importd || return 1
    return 0
}

depends() {
    echo systemd systemd-initrd network
}

install() {
    # Install systemd-importd and related binaries
    inst_multiple -o \
        systemd-importd \
        systemd-import \
        systemd-pull \
        /usr/lib/systemd/systemd-importd \
        /usr/lib/systemd/system-generators/systemd-import-generator
    
    # Install compression tools for image decompression
    inst_multiple -o \
        xz \
        zstd \
        gzip \
        bzip2
    
    # Install network utilities
    inst_multiple -o \
        curl \
        wget
    
    # Install losetup for block device creation
    inst_multiple -o \
        losetup
    
    # Install systemd units for importd
    inst_simple /usr/lib/systemd/system/systemd-importd.service
    inst_simple /usr/lib/systemd/system/dbus-org.freedesktop.import1.service
    
    # Enable systemd-importd socket activation
    inst_simple /usr/lib/systemd/system/systemd-importd.socket
    
    # D-Bus configuration for importd
    inst_simple /usr/share/dbus-1/system-services/org.freedesktop.import1.service
    inst_simple /usr/share/dbus-1/system.d/org.freedesktop.import1.conf
    
    # Create machines directory for downloaded images
    mkdir -p "${initdir}/var/lib/machines"
    mkdir -p "${initdir}/run/machines"
    
    # Enable the services
    systemctl -q --root "$initdir" enable systemd-importd.socket 2>/dev/null || true
}

installkernel() {
    # Install loop device driver
    instmods loop
    
    # Install filesystem modules
    instmods ext4 xfs btrfs squashfs overlay
    
    # Install network drivers
    instmods =drivers/net/ethernet
    instmods virtio_net
}
