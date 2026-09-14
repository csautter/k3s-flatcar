#!/bin/bash

# This script installs Flatcar on a server using the Flatcar Config ISO
# mount the Flatcar Config ISO first
# sudo mount /dev/sr1 /mnt
# Usage: ./server-2-install.sh [ignition-json] [disk]
CONFIG="${1:-server-2-ignite-boot.json}"
DISK="${2:-/dev/sda}"

cd /mnt || exit 1
flatcar-install -d "$DISK" -C stable -i "./$CONFIG"
