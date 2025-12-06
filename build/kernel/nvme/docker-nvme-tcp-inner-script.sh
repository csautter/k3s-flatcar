#!/bin/bash
set -ex

if [ -z "$VERSION" ]; then
    VERSION=stable-4230.2.2
fi

cd ~/trunk/src/scripts
yes "" | ../sdk_init_selfcontained.sh
git checkout $VERSION
echo "CONFIG_NVME_TARGET_TCP=m" >> ~/trunk/src/third_party/coreos-overlay/sys-kernel/coreos-modules/files/commonconfig-*
echo "CONFIG_NVME_TCP=m" >> ~/trunk/src/third_party/coreos-overlay/sys-kernel/coreos-modules/files/commonconfig-*

# consider architecture
if [ -n "${BOARD_ARCH}" ] && [ "${BOARD_ARCH}" = "arm64" ]; then
  ./build_packages --board=arm64-usr
  ./build_image --board=arm64-usr
  ARCHITECTURE=arm64
else
  ./build_packages
  ./build_image
  ARCHITECTURE=amd64
fi

sudo find /build/ -name "*nvme*ko*"
sudo mkdir -p /opt/kernel-modules/${BOARD_ARCH:-amd64}
sudo cp -r /build/*-usr/usr/lib/modules/*-flatcar/kernel/drivers/nvme/ /opt/kernel-modules/${BOARD_ARCH:-amd64}/