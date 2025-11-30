# BitBoot Makefile
# Build orchestration for the BitBoot multiboot USB system
#
# Usage:
#   make all       - Build everything (deps, initramfs, uki, usb image)
#   make deps      - Fetch external dependencies
#   make initramfs - Build custom initramfs
#   make uki       - Build unified kernel image
#   make usb       - Create bootable USB image
#   make clean     - Clean build artifacts
#   make container - Build using container
#
# Variables:
#   BUILD_DIR     - Build output directory (default: build)
#   SIGN          - Enable Secure Boot signing (default: false)
#   SIGN_KEY      - Secure Boot private key path
#   SIGN_CERT     - Secure Boot certificate path

.PHONY: all deps initramfs uki usb clean container help

# Configuration
BUILD_DIR ?= build
SIGN ?= false
SIGN_KEY ?=
SIGN_CERT ?=
CONTAINER_IMAGE ?= bitboot-builder

# Script paths
SCRIPTS_DIR := scripts
FETCH_DEPS := $(SCRIPTS_DIR)/fetch-deps.sh
BUILD_INITRAMFS := $(SCRIPTS_DIR)/build-initramfs.sh
BUILD_UKI := $(SCRIPTS_DIR)/build-uki.sh
CREATE_USB := $(SCRIPTS_DIR)/create-usb.sh

# Output paths
DEPS_DIR := $(BUILD_DIR)/deps
INITRAMFS := $(BUILD_DIR)/initramfs-bitboot.img
UKI_DIR := $(BUILD_DIR)/efi
UKI := $(UKI_DIR)/bitboot.efi
USB_IMG := $(BUILD_DIR)/bitboot-x86_64.img

# Default target
all: deps initramfs uki usb

# Help target
help:
	@echo "BitBoot Build System"
	@echo ""
	@echo "Targets:"
	@echo "  all        - Build everything (default)"
	@echo "  deps       - Fetch external dependencies (ZFSBootMenu, netboot.xyz, Alpine)"
	@echo "  initramfs  - Build custom initramfs with rd.systemd.pull support"
	@echo "  uki        - Build unified kernel image (bitboot.efi)"
	@echo "  usb        - Create bootable USB image"
	@echo "  clean      - Clean build artifacts"
	@echo "  container  - Build using container (requires podman/docker)"
	@echo "  help       - Show this help message"
	@echo ""
	@echo "Variables:"
	@echo "  BUILD_DIR=$(BUILD_DIR)"
	@echo "  SIGN=$(SIGN)"
	@echo "  SIGN_KEY=$(SIGN_KEY)"
	@echo "  SIGN_CERT=$(SIGN_CERT)"

# Create build directory
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# Fetch dependencies
deps: $(BUILD_DIR)
	@echo "==> Fetching dependencies..."
	bash $(FETCH_DEPS) --output $(DEPS_DIR)

$(DEPS_DIR)/zbm/zfsbootmenu.efi: deps

$(DEPS_DIR)/netboot/netboot.xyz.efi: deps

$(DEPS_DIR)/alpine/vmlinuz-lts: deps

# Build initramfs
initramfs: $(BUILD_DIR)
	@echo "==> Building initramfs..."
	bash $(BUILD_INITRAMFS) --output $(INITRAMFS)

$(INITRAMFS): initramfs

# Build UKI
uki: $(INITRAMFS)
	@echo "==> Building unified kernel image..."
ifeq ($(SIGN),true)
	bash $(BUILD_UKI) --output $(BUILD_DIR) --initrd $(INITRAMFS) --sign --key $(SIGN_KEY) --cert $(SIGN_CERT)
else
	bash $(BUILD_UKI) --output $(BUILD_DIR) --initrd $(INITRAMFS)
endif

$(UKI): uki

# Create USB image
usb: $(UKI) deps
	@echo "==> Creating USB image..."
	bash $(CREATE_USB) --output $(USB_IMG) --uki $(UKI) --deps $(DEPS_DIR)

$(USB_IMG): usb

# Build using container
container:
	@echo "==> Building container image..."
	podman build -t $(CONTAINER_IMAGE) . || docker build -t $(CONTAINER_IMAGE) .
	@echo "==> Running build in container..."
	podman run --rm --privileged -v $(PWD):/workspace:Z $(CONTAINER_IMAGE) make all || \
	docker run --rm --privileged -v $(PWD):/workspace $(CONTAINER_IMAGE) make all

# Clean build artifacts
clean:
	@echo "==> Cleaning build artifacts..."
	rm -rf $(BUILD_DIR)

# Development targets
.PHONY: lint check

lint:
	@echo "==> Checking shell scripts..."
	shellcheck $(SCRIPTS_DIR)/*.sh || true

check:
	@echo "==> Verifying build outputs..."
	@test -d $(UKI_DIR) && echo "UKI Directory: OK" || echo "UKI Directory: MISSING"
	@test -f $(UKI) && echo "BitBoot UKI: OK" || echo "BitBoot UKI: MISSING"
	@test -f $(USB_IMG) && echo "USB Image: OK" || echo "USB Image: MISSING"
	@test -f $(DEPS_DIR)/zbm/zfsbootmenu.efi && echo "ZFSBootMenu: OK" || echo "ZFSBootMenu: MISSING"
	@test -f $(DEPS_DIR)/netboot/netboot.xyz.efi && echo "netboot.xyz: OK" || echo "netboot.xyz: MISSING"
	@echo "==> All UKIs:"
	@ls -la $(UKI_DIR)/*.efi 2>/dev/null || echo "No UKIs found"
