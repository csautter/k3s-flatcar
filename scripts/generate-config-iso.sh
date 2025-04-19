#!/bin/bash

# This script generates a Flatcar Config ISO for K3s
# It uses mkisofs to create an ISO image with the necessary configuration files
ISO_NAME="k3s_flatcar_config.iso"
rm $ISO_NAME
mkisofs -output $ISO_NAME -volid k3s-flatcar -joliet -rock {*.yaml,*.json,*.sh,*.env}