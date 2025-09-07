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

# consider architecture
if [ -n "${BOARD_ARCH}" ] && [ "${BOARD_ARCH}" = "arm64" ]; then
  ./build_packages --board=arm64
  ./build_image --board=arm64
  ARCHITECTURE=arm64
else
  ./build_packages
  ./build_image
  ARCHITECTURE=amd64
fi

sudo find /build/ -name "*nvme*ko*"
mkdir -p /opt/kernel-modules/${BOARD_ARCH:-amd64}
sudo cp -r /build/*-usr/usr/lib/modules/*-flatcar/kernel/drivers/nvme/ /opt/kernel-modules/${BOARD_ARCH:-amd64}/
EOF
container_id=$(docker ps -l -q)
echo "Container ID: $container_id"
docker container stop $container_id