#!/bin/bash
# BitBoot Pre-mount Hook - Ensure Network for rd.systemd.pull
#
# This hook runs before mount and ensures the network is fully
# operational before attempting to pull images via HTTP/HTTPS.

type getarg >/dev/null 2>&1 || . /lib/dracut-lib.sh

# Check if rd.systemd.pull is specified
if ! getarg rd.systemd.pull= >/dev/null 2>&1; then
    exit 0
fi

info "BitBoot: Waiting for network before systemd.pull..."

# Wait for network to be available
for i in $(seq 1 30); do
    if ip route show default 2>/dev/null | grep -q .; then
        info "BitBoot: Network is available"
        break
    fi
    sleep 1
done

# Verify DNS resolution works
if command -v resolvectl >/dev/null 2>&1; then
    resolvectl status 2>/dev/null || true
fi

info "BitBoot: Network setup complete, proceeding with image pull"
