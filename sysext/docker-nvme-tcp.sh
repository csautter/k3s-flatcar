#!/bin/bash
set -ex

if [ -z "$VERSION" ]; then
    VERSION=4230.2.2
fi
echo "Full version: $VERSION"
VERSION_MAJOR=$(echo $VERSION | cut -d. -f1)
echo "Major version: $VERSION_MAJOR -> reduced for container image tag"
CONTAINER_NAME=ghcr.io/flatcar/flatcar-sdk-all:$VERSION_MAJOR.0.0

docker pull $CONTAINER_NAME
mkdir -p ./kernel-modules
cat <<'EOF' | docker run -i --privileged -v /dev:/dev -v ./kernel-modules:/opt/kernel-modules/ $CONTAINER_NAME bash
cd ~/trunk/src/scripts
yes "" | ../sdk_init_selfcontained.sh
git checkout stable-4230.2.2
echo "CONFIG_NVME_TARGET_TCP=m" >> ~/trunk/src/third_party/coreos-overlay/sys-kernel/coreos-modules/files/commonconfig-*
echo "CONFIG_NVME_TCP=m" >> ~/trunk/src/third_party/coreos-overlay/sys-kernel/coreos-modules/files/commonconfig-*
./build_packages
./build_image
sudo find /build/amd64-usr/ -name "*nvme*ko*"
sudo cp -r /build/amd64-usr/usr/lib/modules/*-flatcar/kernel/drivers/nvme/ /opt/kernel-modules/
EOF
container_id=$(docker ps -l -q)
echo "Container ID: $container_id"
docker container stop $container_id