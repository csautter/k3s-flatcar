#!/bin/bash
set -ex

if [ -z "$VERSION" ]; then
    VERSION=stable-4230.2.2
fi
echo "Full version: $VERSION"
VERSION_MAJOR=$(echo $VERSION | sed -E 's/^.*?-//' | cut -d. -f1)
echo "Major version: $VERSION_MAJOR -> reduced for container image tag"
CONTAINER_NAME=ghcr.io/flatcar/flatcar-sdk-all:$VERSION_MAJOR.0.0

docker pull $CONTAINER_NAME
mkdir -p ./deployments/kernel/nvme/modules
cat <<EOF | docker run -i --privileged -v /dev:/dev -v ./deployments/kernel/nvme/modules:/opt/kernel-modules/ $CONTAINER_NAME bash
cd ~/trunk/src/scripts
yes "" | ../sdk_init_selfcontained.sh
git checkout $VERSION
echo "CONFIG_NVME_TARGET_TCP=m" >> ~/trunk/src/third_party/coreos-overlay/sys-kernel/coreos-modules/files/commonconfig-*
echo "CONFIG_NVME_TCP=m" >> ~/trunk/src/third_party/coreos-overlay/sys-kernel/coreos-modules/files/commonconfig-*

# crates.io rejects distfile downloads made with wget's bare default
# User-Agent (403), which portage hits whenever a package falls back to
# crates.io after its mirrors are missing a crate (e.g. coreos-base/afterburn's
# hostname-0.4.2.crate). A descriptive User-Agent avoids that block.
sudo sh -c 'echo "user_agent = Mozilla/5.0 (X11; Linux x86_64) Flatcar-SDK-Build" >> /etc/wgetrc'

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
EOF
container_id=$(docker ps -l -q)
echo "Container ID: $container_id"
docker container stop $container_id