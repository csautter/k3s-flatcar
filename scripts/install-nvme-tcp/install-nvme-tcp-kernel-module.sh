#!/bin/bash
# install-nvme-tcp-kernel-module.sh
# Installs the nvme-tcp kernel module matching the current Flatcar release.

set -euox pipefail

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
# Cache each download under its release tag. A fixed filename would be kept
# across Flatcar updates, and the stale module, built for the previous kernel,
# fails to load with a vermagic mismatch.
MODULE_PATH="${MODULE_DIR}/${TAG}/${MODULE_NAME}.ko.xz"

# Create directory for the module
mkdir -p "$(dirname "${MODULE_PATH}")"

# Download the kernel module if not already cached for this release
if [ ! -f "${MODULE_PATH}" ]; then
    echo "Downloading nvme-tcp kernel module for Flatcar ${FLATCAR_VERSION}-${FLATCAR_BUILD_ID}..."
    # Download to a temporary file first, so an interrupted transfer cannot be
    # cached as a truncated module and reused on the next run.
    curl -fsSL -o "${MODULE_PATH}.part" "${MODULE_URL}"
    mv -f "${MODULE_PATH}.part" "${MODULE_PATH}"
fi

# Drop caches left over from previous Flatcar releases, including the module
# that older versions of this script cached directly as ${MODULE_DIR}/*.ko.xz
find "${MODULE_DIR}" -mindepth 1 -maxdepth 1 ! -name "${TAG}" -exec rm -rf {} +

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