# k3s on Flatcar Linux

This project provides a reference implementation for installing [k3s](https://k3s.io/) (a lightweight Kubernetes distribution) on [Flatcar Linux](https://www.flatcar.org/). It automates the process of building and deploying the NVMe-TCP kernel module, and generates a ready-to-use ISO for VM or bare metal installation.

---

## Table of Contents

- [Project Overview](#project-overview)
- [Scripts](#scripts)
- [Building Kernel Modules](#building-kernel-modules)
- [Automated Workflows](#automated-workflows)
- [Installation & Usage](#installation--usage)
- [Troubleshooting](#troubleshooting)
- [License](#license)
- [Contributing](#contributing)

---

## Project Overview

This repository helps you:

- Build and deploy the NVMe-TCP kernel module for Flatcar Linux (required for storage solutions like OpenEBS or Rancher Longhorn).
- Generate an ISO image with pre-configured ignition files for Flatcar and k3s.
- Automate installation and setup using scripts and GitHub Actions workflows.

## Scripts

- [`scripts/convert-to-json-ignition.sh`](scripts/convert-to-json-ignition.sh): Converts YAML Butane config to JSON Ignition config.
- [`scripts/generate-config-iso.sh`](scripts/generate-config-iso.sh): Generates an ISO image with the ignition config for bare metal or VM setup.
- [`scripts/server-2-install.sh`](scripts/server-2-install.sh): Installs the second k3s server on a Flatcar Linux node.
- [`scripts/install-nvme-tcp/install-nvme-tcp-kernel-module.sh`](scripts/install-nvme-tcp/install-nvme-tcp-kernel-module.sh): Installs the NVMe-TCP kernel module.
- [`scripts/install-nvme-tcp/create-nvme-tcp-systemd-service.sh`](scripts/install-nvme-tcp/create-nvme-tcp-systemd-service.sh): Sets up a systemd service for automatic module installation.

---

## Building Kernel Modules

Some storage solutions (e.g., OpenEBS, Rancher Longhorn) require the NVMe-TCP kernel module, which is not included in Flatcar Linux by default. This project provides scripts and workflows to automate building and deploying this module.

### Manual Build Steps

1. Set up the [Flatcar SDK container](https://github.com/orgs/flatcar/packages/container/package/flatcar-sdk-all).
2. Modify kernel module settings as needed.
3. Build the kernel and the module. See also: [Guide to building custom Flatcar images from source](https://www.flatcar.org/docs/latest/reference/developer-guides/sdk-modifying-flatcar/#start-the-sdk)
4. Locate the built `nvme-tcp.ko.xz` file in the SDK container.

---

## Automated Workflows

GitHub Actions are used to automate building and deploying the NVMe-TCP kernel module:

- [`build-and-deploy-nvme-tcp.yml`](.github/workflows/build-and-deploy-nvme-tcp.yml): Builds the module and creates a release.
- [`poll-flatcar-scripts-tags.yml`](.github/workflows/poll-flatcar-scripts-tags.yml): Polls the Flatcar scripts repository for new releases and triggers builds.

---

## Installation & Usage

### 1. Generate the ISO

```sh
# Convert Butane YAML to Ignition JSON
./scripts/convert-to-json-ignition.sh <input.yaml> <output.json>

# Generate the ISO image
./scripts/generate-config-iso.sh <ignition.json>
```

The generated ISO can be used to install Flatcar and k3s on your target machine.

---

### 2. Install flatcar with k3s

Boot from the generated ISO and follow the flatcar documentation instructions to install Flatcar. The k3s installation will be handled automatically by the ignition file.

### 3. Install the NVMe-TCP Kernel Module

If flatcar was installed successfully, you can now install the NVMe-TCP kernel module.

```sh
# Download the install script
curl -o /opt/install-nvme-tcp-kernel-module.sh \
	https://raw.githubusercontent.com/csautter/k3s-flatcar/refs/heads/main/scripts/install-nvme-tcp/install-nvme-tcp-kernel-module.sh

# Make it executable
chmod +x /opt/install-nvme-tcp-kernel-module.sh

# Run the script (as root)
sudo /opt/install-nvme-tcp-kernel-module.sh
```

### 4. Set Up the Systemd Service

```sh
# Download the service setup script
curl -o /opt/create-nvme-tcp-systemd-service.sh \
    https://raw.githubusercontent.com/csautter/k3s-flatcar/refs/heads/main/scripts/install-nvme-tcp/create-nvme-tcp-systemd-service.sh

# Make it executable
chmod +x /opt/create-nvme-tcp-systemd-service.sh

# Run the setup script to create and enable the systemd service
sudo bash /opt/create-nvme-tcp-systemd-service.sh
```

This will ensure the NVMe-TCP kernel module is automatically installed on boot.

## Troubleshooting

- **Kernel module not loading?**
  - Check `dmesg` and `lsmod | grep nvme` for errors.
  - Ensure the kernel version matches the module version.
- **Systemd service not starting?**
  - Run `systemctl status nvme-tcp-install.service` for logs.
- **ISO not booting?**
  - Verify the ISO was generated correctly and matches your hardware requirements.
- **Overlay mount not working or writable?**
  - `mkdir: cannot create directory ‘/usr/lib/modules/6.6.100-flatcar/extra’: Read-only file system`
  - Check `dmesg` for errors related to the overlay filesystem.
  - Ensure the directories `/opt/modules` and `/opt/modules.wd` exist and are writable.
  - Run `bash create-nvme-tcp-systemd-service.sh` again to refresh the overlay mount. A restart of the system may be required afterwards.

---

## License

This project is licensed under the terms of the [MIT License](LICENSE).

---

## Contributing

Contributions are welcome! Please open issues or submit pull requests for improvements, bug fixes, or new features.
