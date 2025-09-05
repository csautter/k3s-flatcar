#!/bin/bash

#docker pull ghcr.io/flatcar/flatcar-sdk-all:4230.2.2
docker pull ghcr.io/flatcar/flatcar-sdk-all:4230.0.0
docker run -ti  --privileged -v /dev:/dev ghcr.io/flatcar/flatcar-sdk-all:4230.0.0

# commands run inside the container
../sdk_init_selfcontained.sh
git checkout stable-4230.2.2
echo "CONFIG_NVME_TARGET_TCP=m" >> ~/trunk/src/third_party/coreos-overlay/sys-kernel/coreos-modules/files/commonconfig-*
echo "CONFIG_NVME_TCP=m" >> ~/trunk/src/third_party/coreos-overlay/sys-kernel/coreos-modules/files/commonconfig-*
./build_packages
./build_image
# list all nvme kernel modules
find /build/amd64-usr/ -name "*nvme*ko*"

# command runs outside the container
# get container id
container_id=$(docker ps -l -q)
docker cp $container_id:/build/amd64-usr/usr/lib/modules/6.6.100-flatcar/kernel/drivers/nvme/ ./kernel-modules/

scp ./kernel-modules/nvme/host/nvme-tcp.ko.xz k3s-server-3:/tmp/
ssh k3s-server-3 sudo mv /tmp/nvme-tcp.ko.xz /usr/lib/modules/6.6.100-flatcar/kernel/drivers/nvme/host/nvme-tcp.ko.xz
ssh k3s-server-3 modprobe nvme_tcp