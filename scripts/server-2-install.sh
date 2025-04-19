#!/bin/bash

# This script installs Flatcar on a server using the Flatcar Config ISO
# mount the Flatcar Config ISO first
# sudo mount /dev/sr1 /mnt
cd /mnt || exit 1
flatcar-install -d /dev/sda -C stable -i ./server-2-ignite-boot.json