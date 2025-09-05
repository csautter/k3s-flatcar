#!/bin/bash
set -ex

#docker pull ghcr.io/flatcar/flatcar-sdk-all:4230.2.2
docker pull ghcr.io/flatcar/flatcar-sdk-all:4230.0.0
docker run --privileged -v /dev:/dev ghcr.io/flatcar/flatcar-sdk-all:4230.0.0 /bin/bash -c 'sleep 14400'
container_id=$(docker ps -l -q)

# commands run inside the container
docker exec $container_id bash -c '
    cd ~/trunk/src
    ./sdk_init_selfcontained.sh
    git checkout stable-4230.2.2
    echo "CONFIG_NVME_TARGET_TCP=m" >> ~/trunk/src/third_party/coreos-overlay/sys-kernel/coreos-modules/files/commonconfig-*
    echo "CONFIG_NVME_TCP=m" >> ~/trunk/src/third_party/coreos-overlay/sys-kernel/coreos-modules/files/commonconfig-*
    ./build_packages
    ./build_image
    find /build/amd64-usr/ -name "*nvme*ko*"
'

# command runs outside the container
mkdir -p ./kernel-modules
docker cp $container_id:/build/amd64-usr/usr/lib/modules/6.6.100-flatcar/kernel/drivers/nvme/ ./kernel-modules/

#scp ./kernel-modules/nvme/host/nvme-tcp.ko.xz k3s-server-3:/tmp/
#ssh k3s-server-3 sudo mv /tmp/nvme-tcp.ko.xz /usr/lib/modules/6.6.100-flatcar/kernel/drivers/nvme/host/nvme-tcp.ko.xz
#ssh k3s-server-3 modprobe nvme_tcp