#!/bin/bash
# install-nvme-tcp-kernel-module.sh
# Installs the nvme-tcp kernel module matching the current Flatcar release.

set -euo pipefail

REPO="csautter/k3s-flatcar"
MODULE_NAME="nvme-tcp"
ARCH="$(uname -m)"
if [ "$ARCH" = "x86_64" ]; then
    ARCH="amd64"
elif [ "$ARCH" = "aarch64" ]; then
    ARCH="arm64"
fi

# Get current Flatcar version
FLATCAR_VERSION=$(cat /etc/os-release | grep VERSION | cut -d= -f2 | tr -d '"')
FLATCAR_BUILD_ID=$(cat /etc/os-release | grep BUILD_ID | cut -d= -f2 | tr -d '"')
echo "Current Flatcar version: $FLATCAR_VERSION-$FLATCAR_BUILD_ID"

TAG="${MODULE_NAME}-${ARCH}-stable-${FLATCAR_VERSION}"

# Download URL for the kernel module
MODULE_URL="https://github.com/${REPO}/releases/download/${TAG}/${MODULE_NAME}.ko.xz"

MODULE_DIR="/opt/nvme-tcp"
MODULE_PATH="${MODULE_DIR}/${MODULE_NAME}.ko.xz"

# Create directory for the module
mkdir -p "${MODULE_DIR}"

# Download the kernel module if not present or outdated
if [ ! -f "${MODULE_PATH}" ]; then
    echo "Downloading nvme-tcp kernel module for Flatcar ${FLATCAR_VERSION}-${FLATCAR_BUILD_ID}..."
    curl -fsSL -o "${MODULE_PATH}" "${MODULE_URL}"
fi

# Install the module to /lib/modules/$(uname -r)/extra
INSTALL_DIR="/usr/lib/modules/$(uname -r)/extra"
mkdir -p "${INSTALL_DIR}"
cp -f "${MODULE_PATH}" "${INSTALL_DIR}/"

# Update module dependencies
depmod

# Load the module
modprobe nvme-tcp

# Enable module to load at boot
echo "nvme-tcp" > /etc/modules-load.d/nvme-tcp.conf

echo "nvme-tcp kernel module installed and loaded."