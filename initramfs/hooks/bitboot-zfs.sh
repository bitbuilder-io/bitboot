#!/bin/bash
# BitBoot Dracut Hook - ZFS Support
#
# This hook ensures ZFS kernel modules and userspace tools
# are properly included in the initramfs
#
# Place in /usr/lib/dracut/modules.d/99bitboot-zfs/module-setup.sh

check() {
    require_binaries zpool zfs || return 1
    return 0
}

depends() {
    echo systemd
}

install() {
    # Install ZFS userspace tools
    inst_multiple -o \
        zpool \
        zfs \
        zdb \
        zstream \
        zinject \
        zstreamdump \
        zhack \
        ztest
    
    # Install ZFS libraries
    inst_libdir_file "libzfs*.so*"
    inst_libdir_file "libnvpair*.so*"
    inst_libdir_file "libuutil*.so*"
    inst_libdir_file "libzpool*.so*"
    
    # Install ZFS udev rules
    inst_rules 60-zvol.rules 69-vdev.rules 90-zfs.rules
    
    # Install ZFS systemd units
    inst_simple /usr/lib/systemd/system/zfs-import-cache.service
    inst_simple /usr/lib/systemd/system/zfs-import-scan.service
    inst_simple /usr/lib/systemd/system/zfs-mount.service
    inst_simple /usr/lib/systemd/system/zfs-share.service
    inst_simple /usr/lib/systemd/system/zfs-zed.service
    inst_simple /usr/lib/systemd/system/zfs.target
    
    # Install ZFS configuration
    inst_simple /etc/zfs/zpool.cache 2>/dev/null || true
    inst_dir /etc/zfs
    inst_dir /etc/zfs/zpool.d
    
    # Install hostid for ZFS pool import
    inst_simple /etc/hostid 2>/dev/null || true
    
    # Create necessary directories
    mkdir -p "${initdir}/var/lib/zfs"
    mkdir -p "${initdir}/run/zfs"
}

installkernel() {
    # Install ZFS kernel modules
    instmods zfs
    instmods spl
    instmods znvpair
    instmods zcommon
    instmods zlua
    instmods zavl
    instmods zunicode
    instmods zzstd
    instmods icp
}
