#!/bin/bash
set -e

# This script generates a Flatcar Config ISO for one Kubernetes distribution.
# It uses mkisofs to create an ISO image with the necessary configuration files.
# Usage: ./generate-config-iso.sh [k3s|rke2]   (default: k3s)

DISTRO="${1:-k3s}"

if [ ! -d "$DISTRO" ]; then
    echo "unknown distribution '$DISTRO': no such directory next to this script" >&2
    echo "usage: $0 [k3s|rke2]" >&2
    exit 1
fi

if ! compgen -G "$DISTRO/*.json" > /dev/null; then
    echo "no Ignition JSON in $DISTRO/, run ./convert-to-json-ignition.sh $DISTRO first" >&2
    exit 1
fi

ISO_NAME="${DISTRO}_flatcar_config.iso"
if [ -f "$ISO_NAME" ]; then
    echo "Removing existing ISO file: $ISO_NAME"
    rm "$ISO_NAME"
fi

# Graft the node configs in at the ISO root instead of under a $DISTRO/
# directory, so the paths below /mnt stay the same for every distribution.
graft=()
for f in "$DISTRO"/*.yaml "$DISTRO"/*.json; do
    graft+=("$(basename "$f")=$f")
done

mkisofs -output "$ISO_NAME" -volid "${DISTRO}-flatcar" -joliet -rock \
    -graft-points "${graft[@]}" {*.sh,.env*}
