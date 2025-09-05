#!/bin/bash
set -ex

#docker pull ghcr.io/flatcar/flatcar-sdk-all:4230.2.2
docker pull ghcr.io/flatcar/flatcar-sdk-all:4230.0.0
mkdir -p ./kernel-modules
cat <<'EOF' | docker run -i --privileged -v /dev:/dev -v ./kernel-modules:/opt/kernel-modules/ ghcr.io/flatcar/flatcar-sdk-all:4230.0.0 bash
cd ~/trunk/src/scripts
yes "" | ../sdk_init_selfcontained.sh
git checkout stable-4230.2.2
echo "CONFIG_NVME_TARGET_TCP=m" >> ~/trunk/src/third_party/coreos-overlay/sys-kernel/coreos-modules/files/commonconfig-*
echo "CONFIG_NVME_TCP=m" >> ~/trunk/src/third_party/coreos-overlay/sys-kernel/coreos-modules/files/commonconfig-*
./build_packages
./build_image
find /build/amd64-usr/ -name "*nvme*ko*"
cp -r /build/amd64-usr/usr/lib/modules/6.6.100-flatcar/kernel/drivers/nvme/ /opt/kernel-modules/
EOF
container_id=$(docker ps -l -q)
echo "Container ID: $container_id"
docker container stop $container_id

# command runs outside the container
#mkdir -p ./kernel-modules
#docker cp $container_id:/build/amd64-usr/usr/lib/modules/6.6.100-flatcar/kernel/drivers/nvme/ ./kernel-modules/

#scp ./kernel-modules/nvme/host/nvme-tcp.ko.xz k3s-server-3:/tmp/
#ssh k3s-server-3 sudo mv /tmp/nvme-tcp.ko.xz /usr/lib/modules/6.6.100-flatcar/kernel/drivers/nvme/host/nvme-tcp.ko.xz
#ssh k3s-server-3 modprobe nvme_tcp