#!/bin/bash
set -ex

if [ -z "$VERSION" ]; then
    VERSION=stable-4230.2.2
fi
echo "Full version: $VERSION"
VERSION_MAJOR=$(echo $VERSION | sed -E 's/^.*?-//' | cut -d. -f1)
echo "Major version: $VERSION_MAJOR -> reduced for container image tag"
CONTAINER_NAME=ghcr.io/flatcar/flatcar-sdk-all:$VERSION_MAJOR.0.0

# BOARD_ARCH is a host variable, so resolve the architecture and board here and
# bake the values into the container script below. The board sysroot is then
# addressed explicitly instead of via a /build/*-usr glob: the SDK image can
# hold more than one board root, and a glob would copy every match into the
# same destination, letting one architecture's modules overwrite another's.
ARCH=${BOARD_ARCH:-amd64}
BOARD=$ARCH-usr

docker pull $CONTAINER_NAME
mkdir -p ./deployments/kernel/nvme/modules
cat <<EOF | docker run -i --privileged -v /dev:/dev -v ./deployments/kernel/nvme/modules:/opt/kernel-modules/ $CONTAINER_NAME bash
set -x
echo "Building $ARCH (board $BOARD) for Flatcar $VERSION"

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

# Repair a distfile digest that upstream has since corrected.
#
# sys-kernel/dracut-109 fetches a GitHub *auto-generated* tag tarball. The
# dracut-ng/dracut-ng repository was renamed to dracut-ng/dracut, so codeload
# regenerates that archive and it is now 556060 bytes instead of the 556054
# recorded in the Manifest; every distfile mirror 404s for it, so the original
# bytes are gone and the fetch can never verify. Flatcar fixed this in
# stable-4593.2.2 (Manifest bump plus dracut-109 -> dracut-109-r1); the values
# below are copied verbatim from that tag, so portage still verifies the
# download against Flatcar-published hashes rather than trusting whatever
# GitHub happens to serve.
#
# Only the full-build fallback path below reaches dracut at all. Guarded on the
# stale size, so this is a no-op on stable-4593.2.2 and newer. Drop it once no
# Flatcar release in the poll window still pins the stale digest.
dracut_manifest=~/trunk/src/third_party/portage-stable/sys-kernel/dracut/Manifest
if [ -f "\$dracut_manifest" ] && grep -q '^DIST dracut-109.tar.gz 556054 ' "\$dracut_manifest"; then
  echo "Repairing stale dracut-109.tar.gz digest in \$dracut_manifest"
  sudo sed -i \
    's|^DIST dracut-109.tar.gz 556054 .*|DIST dracut-109.tar.gz 556060 BLAKE2B b1f456182bd79e213d30751822c6d284a29e7b2f8c43bd59dad84e22520dbd461c872e44e4bc35c27d76faf35ed8b6a525f72ef8289b419f75ed68988e9937f0 SHA512 4bd846fb67a0af698a34f02b6b5594e547257d9904b2173e23298623a47295e589fe6b2dcd83f32b8721b50b94e8f7a0cf41d19d17b847238d7bfd9195c3061d|' \
    "\$dracut_manifest"
else
  echo "No stale dracut-109.tar.gz digest to repair"
fi

# The artifact only ever comes out of the board sysroot at
# /build/$BOARD/usr/lib/modules/<kver>-flatcar/kernel/drivers/nvme/, which is
# written by sys-kernel/coreos-modules' modules_install -- already xz
# compressed, because commonconfig sets CONFIG_MODULE_COMPRESS_XZ=y. build_image
# only assembles an image out of that sysroot and contributes nothing here, and
# a full build_packages additionally builds @system, coreos-devel/board-packages
# and every extra sysext (nvidia-drivers, zfs, podman, python, incus,
# overlaybd) -- hundreds of packages whose distfiles are a recurring source of
# unrelated build failures. So emerge just the kernel modules.
nvme_module_dir() {
  local dir
  for dir in /build/$BOARD/usr/lib/modules/*-flatcar/kernel/drivers/nvme; do
    if [ -d "\$dir" ] && [ -n "\$(sudo find "\$dir" -name 'nvme-tcp.ko*' -print -quit)" ]; then
      echo "\$dir"
      return 0
    fi
  done
  return 1
}

# Same setup_board invocation and kernel build identity that build_packages
# would have used, so the board root and the resulting module are configured
# exactly as before; only the set of emerged packages is narrowed.
./setup_board --board=$BOARD --regen_configs --usepkg --nousepkgonly --getbinpkg
export KBUILD_BUILD_USER="\${BUILD_USER:-build}"
export KBUILD_BUILD_HOST="\${BUILD_HOST:-pony-truck.infra.kinvolk.io}"

# --usepkg-exclude is load-bearing: the CONFIG_NVME_TCP=m appended above only
# takes effect if coreos-modules is built from source, never reused as a binpkg.
emerge-$BOARD --update --deep --newuse --verbose --backtrack=30 --select \
  --jobs="\$(nproc)" --usepkg --getbinpkg --with-bdeps y \
  --usepkg-exclude=sys-kernel/coreos-modules \
  sys-kernel/coreos-modules

if nvme_module_dir > /dev/null; then
  echo "NVMe modules built by the targeted coreos-modules emerge"
else
  # Safety net: if the narrow emerge did not produce the modules, fall back to
  # the full build this script used to do.
  echo "WARNING: targeted emerge produced no NVMe modules, falling back to a full build"
  ./build_packages --board=$BOARD
  ./build_image --board=$BOARD
fi

sudo find /build/$BOARD/ -name "*nvme*ko*"

src=\$(nvme_module_dir) || {
  echo "ERROR: no nvme-tcp module under /build/$BOARD/usr/lib/modules/*-flatcar/kernel/drivers/nvme/"
  exit 1
}
echo "Copying NVMe modules from \$src"
sudo mkdir -p /opt/kernel-modules/$ARCH
sudo cp -r "\$src" /opt/kernel-modules/$ARCH/
EOF
container_id=$(docker ps -l -q)
echo "Container ID: $container_id"
docker container stop $container_id
