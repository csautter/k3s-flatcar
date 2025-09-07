# k3s on flatcar linux

This project is intended as reference for a k3s installation on Flatcar Linux. The generated .iso file can be used to setup VMs or Bare Metal Machines.

## Scripts

- [scripts/convert-to-json-ignition.sh](scripts/convert-to-json-ignition.sh) - Converts the yaml butane config to json ignition config.
- [scripts/generate-config-iso.sh](scripts/generate-config-iso.sh) - Generates an ISO image with the ignition config. Can be used for setup on bare metal or when the common provision approach is not available.
- [scripts/server-2-install.sh](scripts/server-2-install.sh) - Installs the second k3s server on a Flatcar Linux node.

## Building Kernel Modules

For some storage solutions like OpenEBS or Rancher Longhorn the nvme tcp kernel module is required but not included with flatcar linux by default.
Therefore, it needs to be built and deployed separately. The flatcar linux documentation provides guidance on how to do this. Unfortunately for the nvme tcp kernel module, the process is not as straightforward as it could be. I was not able to find a clear step-by-step guide for this specific module.
In my experience the best way to build and deploy the nvme tcp kernel module is building flatcar linux from source with the flatcar SDK container. Kernel module settings can be changed before building the kernel and other dependencies. After a complete build the kernel module can be found in the default kernel module path within the SDK container.

### Building the Kernel Module

1. Set up the Flatcar SDK container.
2. Modify the kernel module settings as needed.
3. Build the kernel and the module.
4. Locate the built `nvme-tcp.ko.xz` file in the SDK container.

### Github Actions Workflow for NVMe-TCP Kernel Module

To make the process of building and deploying the nvme tcp kernel module easier, I have used a Github Actions workflow. This workflow automates the steps required to build the module and create a release.

Check the [build-and-deploy-nvme-tcp.yml](.github/workflows/build-and-deploy-nvme-tcp.yml) file for the workflow definition.
I have also created a [poll-flatcar-scripts-tags.yml](.github/workflows/poll-flatcar-scripts-tags.yml) workflow for polling the Flatcar scripts repository for new releases. All new releases are automatically built and deployed using the NVMe-TCP kernel module workflow.

### Setup flatcar to automatically download and install the NVMe-TCP kernel module

#### install script

1. Download the install script from [install-nvme-tcp-kernel-module.sh](scripts/install-nvme-tcp/install-nvme-tcp-kernel-module.sh) to /opt/install-nvme-tcp-kernel-module.sh.
2. Make the script executable: `chmod +x /opt/install-nvme-tcp-kernel-module.sh`
3. Run the script to download and install the NVMe-TCP kernel module: `sudo /opt/install-nvme-tcp-kernel-module.sh`

#### systemd service

1. Create a systemd service file for the NVMe-TCP kernel module.
2. Enable the service to start on boot.
3. The service will automatically download and install the module on system startup.

For simplicity, I have automated the setup of the systemd service in a bash script. Check the [create-nvme-tcp-systemd-service.sh](scripts/install-nvme-tcp/create-nvme-tcp-systemd-service.sh) script for details.
Run the script after downloading and installing the install script to set up the systemd service.

## The .iso file

The iso file is intended to be used for installation of flatcar and k3s. First you need to boot from the flatcar iso file.
The generated iso file contains ready to use configuration which can be used for easy configuration of flatcar and k3s.
