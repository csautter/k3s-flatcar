# k3s on flatcar linux

This project is intended as reference for a k3s installation on Flatcar Linux.

## Scripts

- [scripts/convert-to-json-ignition.sh](scripts/convert-to-json-ignition.sh) - Converts the yaml butane config to json ignition config.
- [scripts/generate-config-iso.sh](scripts/generate-config-iso.sh) - Generates an ISO image with the ignition config. Can be used for setup on bare metal or when the common provision approach is not available.
- [scripts/server-2-install.sh](scripts/server-2-install.sh) - Installs the second k3s server on a Flatcar Linux node.

## The .iso file

The iso file is intended to be used for installation of flatcar and k3s. First you need to boot from the flatcar iso file.
The generated iso file contains ready to use configuration which can be used for easy configuration of flatcar and k3s.
