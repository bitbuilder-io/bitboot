# BitBoot Build Container
# Provides a reproducible build environment with systemd v258+ and all required tools
#
# Build: podman build -t bitboot-builder .
# Run:   podman run --rm -v $(pwd):/workspace:Z bitboot-builder make all

FROM registry.fedoraproject.org/fedora:41

LABEL maintainer="BitBoot Project"
LABEL description="Build environment for BitBoot multiboot USB system"

# Install build dependencies
RUN dnf install -y \
    # Core build tools
    make \
    gcc \
    binutils \
    # UEFI/UKI tools
    systemd-boot-unsigned \
    systemd-ukify \
    sbsigntools \
    # Initramfs tools
    dracut \
    # Disk/partition tools
    parted \
    gdisk \
    dosfstools \
    e2fsprogs \
    xfsprogs \
    # Compression tools
    xz \
    zstd \
    gzip \
    bzip2 \
    lz4 \
    # Network tools
    curl \
    wget \
    # ZFS (from RPM Fusion)
    && dnf install -y \
        https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-41.noarch.rpm \
    && dnf install -y zfs || true \
    # Kernel and firmware
    && dnf install -y \
        kernel \
        kernel-devel \
        linux-firmware \
    # Utilities
    && dnf install -y \
        util-linux \
        coreutils \
        findutils \
        grep \
        sed \
        gawk \
        file \
        tree \
    # Cleanup
    && dnf clean all \
    && rm -rf /var/cache/dnf

# Verify systemd version is 258+
RUN systemctl --version | head -1

# Set working directory
WORKDIR /workspace

# Default command
CMD ["make", "all"]
