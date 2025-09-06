#!/bin/bash
set -euo pipefail

# this script rebuilds the nvme-tcp.ko module for the current kernel on a Flatcar system

KVER=$(uname -r)
MODPATH="/usr/lib/modules/${KVER}/extra/nvme-tcp.ko"

if [ -f "${MODPATH}" ]; then
  echo "nvme-tcp.ko already present for ${KVER}"
  exit 0
fi

echo "Rebuilding nvme-tcp.ko for ${KVER}..."

# Load Flatcar release vars
. /usr/share/flatcar/release
. /usr/share/flatcar/update.conf

url="https://${GROUP:-stable}.release.flatcar-linux.net/${FLATCAR_RELEASE_BOARD}/${FLATCAR_RELEASE_VERSION}/flatcar_developer_container.bin.bz2"

# Download developer container (if not cached)
img="/opt/flatcar_developer_container.bin"
if [ ! -f "$img" ]; then
  curl -L "$url" -o "$img.bz2"
  bzip2 -d "$img.bz2"
fi

# Run the build inside the container
cat <<'INNERSCRIPT' | systemd-nspawn --bind=/usr/lib/modules --capability=CAP_NET_ADMIN --image="$img" --pipe bash -eux
  emerge-gitclone
  emerge -gKv coreos-sources
  gzip -cd /proc/config.gz > /usr/src/linux/.config
  make -C /usr/src/linux olddefconfig
  echo "CONFIG_NVME_TCP=m" >> /usr/src/linux/.config
  echo "CONFIG_NVME_TARGET_TCP=m" >> /usr/src/linux/.config
  echo "CONFIG_NVME_CORE=m" >> /usr/src/linux/.config
  echo "CONFIG_BLK_DEV_NVME=m" >> /usr/src/linux/.config
  grep NVME_TCP /usr/src/linux/.config
  grep NVME_TARGET_TCP /usr/src/linux/.config
  # read -p "Press enter to continue"
  make -C /usr/src/linux modules_prepare
  # make -C /usr/src/linux modules
  # Build and install nvme-tcp.ko (host)
  #cd /usr/src/linux/drivers/nvme/host
  #make -C /usr/src/linux M=$(pwd) modules
  cd /usr/src/linux
  make -j$(nproc)
  make M=drivers/nvme/host
  mkdir -p /usr/lib/modules/$(uname -r)/extra
  cp -v nvme-tcp.ko /usr/lib/modules/$(uname -r)/extra/

  # Build and install nvmet-tcp.ko (target)
  cd /usr/src/linux/drivers/nvme/target
  make -C /usr/src/linux M=$(pwd) modules
  cp -v nvmet-tcp.ko /usr/lib/modules/$(uname -r)/extra/

  depmod -a
INNERSCRIPT

echo "nvme-tcp.ko built and installed for ${KVER}"
