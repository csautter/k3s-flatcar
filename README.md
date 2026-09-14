# k3s on Flatcar Linux

This project provides a reference implementation for installing [k3s](https://k3s.io/) (a lightweight Kubernetes distribution) on [Flatcar Linux](https://www.flatcar.org/). It automates the process of building and deploying the NVMe-TCP kernel module, and generates a ready-to-use config ISO for VM or bare metal installation.

---

## Table of Contents

- [Project Overview](#project-overview)
- [Cluster Topology](#cluster-topology)
- [Scripts](#scripts)
- [Prerequisites](#prerequisites)
- [Installation & Usage](#installation--usage)
  - [1. Configure your cluster](#1-configure-your-cluster)
  - [2. Adjust the node templates](#2-adjust-the-node-templates)
  - [3. Generate the config ISO](#3-generate-the-config-iso)
  - [4. Install the first server node](#4-install-the-first-server-node)
  - [5. Verify the first node](#5-verify-the-first-node)
  - [6. Add the remaining server nodes](#6-add-the-remaining-server-nodes)
  - [7. Add agent (worker) nodes](#7-add-agent-worker-nodes)
  - [8. Verify the cluster](#8-verify-the-cluster)
- [NVMe-TCP Kernel Module](#nvme-tcp-kernel-module)
- [Building Kernel Modules](#building-kernel-modules)
- [Automated Workflows](#automated-workflows)
- [Security Notes](#security-notes)
- [Known Limitations](#known-limitations)
- [Troubleshooting](#troubleshooting)
- [License](#license)
- [Contributing](#contributing)

---

## Project Overview

This repository helps you:

- Provision k3s server (control-plane) and agent (worker) nodes on Flatcar Linux via Ignition.
- Generate a config ISO carrying the Ignition files for Flatcar and k3s.
- Build and deploy the NVMe-TCP kernel module for Flatcar Linux (required for storage solutions like OpenEBS or Rancher Longhorn).
- Automate module builds and dependency updates using GitHub Actions.

## Cluster Topology

Every node is described by one Butane template in `scripts/`. The templates differ only in
hostname and in how k3s is told to start.

| Template | Role | k3s mode | Notes |
| --- | --- | --- | --- |
| `server-1-ignite-boot.yaml` | First server | `--cluster-init` | Bootstraps the cluster and the embedded etcd. Install this node first. |
| `server-2-ignite-boot.yaml` | Additional server | `server --server $SERVER_REGISTER_URL` | Joins the control plane. |
| `server-3-ignite-boot.yaml` | Additional server | `server --server $SERVER_REGISTER_URL` | Joins the control plane. |
| `agent-1-ignite-boot.yaml` | Agent (worker) | `agent` + `K3S_URL` | Runs workloads only, no control plane, no etcd. |

Servers run the Kubernetes control plane and the embedded etcd, and they also schedule
workloads. Agents only run workloads. Because etcd needs a quorum, use an **odd number of
servers** — one for a test cluster, three for high availability. Add as many agents as you
need capacity for.

A single-server cluster is perfectly valid: install `server-1` only, then add agents.

## Scripts

Node templates (Butane YAML, converted to Ignition JSON):

- [`scripts/server-1-ignite-boot.yaml`](scripts/server-1-ignite-boot.yaml): First k3s server, initializes the cluster.
- [`scripts/server-2-ignite-boot.yaml`](scripts/server-2-ignite-boot.yaml): Additional k3s server joining the cluster.
- [`scripts/server-3-ignite-boot.yaml`](scripts/server-3-ignite-boot.yaml): Additional k3s server joining the cluster.
- [`scripts/agent-1-ignite-boot.yaml`](scripts/agent-1-ignite-boot.yaml): k3s agent (worker) node joining the cluster.
- [`scripts/.env.example`](scripts/.env.example): Template for the `.env` file that fills in the placeholders above.

Tooling:

- [`scripts/convert-to-json-ignition.sh`](scripts/convert-to-json-ignition.sh): Substitutes the `.env` variables into **every** `*-ignite-boot.yaml` and converts each one to Ignition JSON. Takes no arguments.
- [`scripts/generate-config-iso.sh`](scripts/generate-config-iso.sh): Packs the configs into `k3s_flatcar_config.iso`. Takes no arguments.
- [`scripts/server-2-install.sh`](scripts/server-2-install.sh): Convenience wrapper that runs `flatcar-install` on the node. It is hardcoded to `server-2-ignite-boot.json` and `/dev/sda` — edit it, or run `flatcar-install` directly, for any other node or disk.
- [`scripts/install-nvme-tcp/install-nvme-tcp-kernel-module.sh`](scripts/install-nvme-tcp/install-nvme-tcp-kernel-module.sh): Installs the NVMe-TCP kernel module.
- [`scripts/install-nvme-tcp/create-nvme-tcp-systemd-service.sh`](scripts/install-nvme-tcp/create-nvme-tcp-systemd-service.sh): Sets up the writable overlay and a systemd service for automatic module installation.

---

## Prerequisites

On your **workstation** (where you build the ISO):

- `docker` — runs the Butane container that converts YAML to Ignition JSON.
- `envsubst` — from the `gettext` package (`apt install gettext-base`, `dnf install gettext`).
- `mkisofs` — from `cdrtools`, or install `genisoimage` which provides a compatible binary.

On the **target machine**:

- The official Flatcar Linux **live ISO**, downloaded from the
  [Flatcar release page](https://www.flatcar.org/releases). The ISO produced by this repo is a
  *data* ISO containing configuration only — it is not bootable. You boot the Flatcar live
  ISO and read the config ISO from a second drive.
- A target disk (the scripts assume `/dev/sda`) and network connectivity, since the Ignition
  config downloads the k3s installer from `https://get.k3s.io` on first boot.

---

## Installation & Usage

### 1. Configure your cluster

```sh
cp scripts/.env.example scripts/.env
```

Edit `scripts/.env`:

| Variable | Description |
| --- | --- |
| `SSH_PUB_KEY_1` | SSH public key authorized for the `core` user. |
| `SSH_PUB_KEY_2` | A second SSH public key. If you only need one key, remove the `${SSH_PUB_KEY_2}` line from the templates — leaving it empty renders an empty entry. |
| `K3S_TOKEN` | Shared cluster secret, identical on every node. Generate one with `openssl rand -hex 32`. |
| `K3S_VERSION` | k3s version to pin, e.g. `v1.30.1+k3s1`. |
| `SERVER_REGISTER_URL` | API endpoint of the first server, e.g. `https://192.168.1.102:6443`. |

`SERVER_REGISTER_URL` is only read by the joining nodes (servers 2/3 pass it as `--server`,
agents as `K3S_URL`), so it may point at an IP that does not exist yet — just make sure
`server-1` really ends up on that address before you boot any other node. Give `server-1` a
static IP or a DHCP reservation.

### 2. Adjust the node templates

Each template hardcodes its hostname in `/etc/hostname`. Edit the templates if you want
different names, delete the ones you do not need, and copy an existing one to add more nodes:

```sh
# a second worker
cp scripts/agent-1-ignite-boot.yaml scripts/agent-2-ignite-boot.yaml
# then change the /etc/hostname inline value to agent-2
```

`convert-to-json-ignition.sh` converts every `*-ignite-boot.yaml` it finds, so new templates
are picked up automatically.

### 3. Generate the config ISO

Both scripts read files relative to the current directory, so run them from `scripts/`:

```sh
cd scripts
./convert-to-json-ignition.sh   # renders .env into every template, emits *-ignite-boot.json
./generate-config-iso.sh        # packs them into k3s_flatcar_config.iso
```

The result is `scripts/k3s_flatcar_config.iso`. It contains one Ignition JSON per node plus
the helper scripts, so the **same ISO is used for every node** — you pick the node's role by
choosing which JSON file you pass to `flatcar-install`.

### 4. Install the first server node

1. Boot the machine from the official Flatcar **live** ISO.
2. Attach `k3s_flatcar_config.iso` as a second optical drive and mount it:

   ```sh
   sudo mount /dev/sr1 /mnt
   ```

   If `/dev/sr1` does not exist, check `lsblk` — the live ISO is usually `/dev/sr0` and the
   config ISO the next device.
3. Install Flatcar with the matching Ignition config:

   ```sh
   sudo flatcar-install -d /dev/sda -C stable -i /mnt/server-1-ignite-boot.json
   ```

4. Reboot and remove the installation media.

On first boot, Ignition writes the hostname and the SSH keys, then `k3s-install.service`
downloads and runs the k3s installer. This takes a minute or two and needs internet access.

### 5. Verify the first node

SSH in as `core` and check that k3s came up before installing any other node:

```sh
systemctl status k3s-install.service   # the one-shot installer
systemctl status k3s                   # the k3s server itself
sudo /opt/bin/k3s kubectl get nodes
```

k3s is installed to `/opt/bin` rather than `/usr/local/bin`, because `/usr` is read-only on
Flatcar.

### 6. Add the remaining server nodes

Only if you want a highly available control plane. Repeat step 4 on each additional machine,
pointing at that node's config:

```sh
sudo flatcar-install -d /dev/sda -C stable -i /mnt/server-2-ignite-boot.json
# and on the third machine
sudo flatcar-install -d /dev/sda -C stable -i /mnt/server-3-ignite-boot.json
```

These nodes join the cluster at `SERVER_REGISTER_URL` using `K3S_TOKEN`, so `server-1` must
be running and reachable first.

### 7. Add agent (worker) nodes

Agents are installed exactly the same way, using an agent config:

```sh
sudo flatcar-install -d /dev/sda -C stable -i /mnt/agent-1-ignite-boot.json
```

The agent template sets `K3S_URL=${SERVER_REGISTER_URL}` and `INSTALL_K3S_EXEC=agent`, so the
k3s installer starts `k3s-agent` instead of a server and registers the node against the
existing control plane with the shared `K3S_TOKEN`.

To add more workers, create `agent-2-ignite-boot.yaml`, `agent-3-ignite-boot.yaml`, … as shown
in step 2, regenerate the ISO (step 3), and repeat this step. A worker needs nothing else —
no changes on the server side.

Check an agent with:

```sh
systemctl status k3s-agent
journalctl -u k3s-agent -f
```

Note that `kubectl` is not usable on agent nodes: there is no kubeconfig there. Run cluster
queries from a server node.

### 8. Verify the cluster

On any server node:

```sh
sudo /opt/bin/k3s kubectl get nodes -o wide
```

Servers appear with roles `control-plane,etcd,master`; agents show `<none>` in the ROLES
column, which is normal. All nodes should be `Ready`.

To use `kubectl` from your workstation, copy `/etc/rancher/k3s/k3s.yaml` from a server node
and replace the `127.0.0.1` in `clusters[].cluster.server` with the node's IP address:

```sh
scp core@<server-1-ip>:/etc/rancher/k3s/k3s.yaml ~/.kube/k3s-flatcar.yaml
sed -i 's#https://127.0.0.1:6443#https://<server-1-ip>:6443#' ~/.kube/k3s-flatcar.yaml
export KUBECONFIG=~/.kube/k3s-flatcar.yaml
kubectl get nodes
```

If a node does not show up, check `journalctl -u k3s-install.service` on that node — a wrong
`K3S_TOKEN` or an unreachable `SERVER_REGISTER_URL` is the usual cause.

---

## NVMe-TCP Kernel Module

Storage solutions such as OpenEBS Mayastor or Rancher Longhorn need the NVMe-TCP kernel
module, which Flatcar does not ship. Run these steps **on every node that should run storage
workloads**, after the node has joined the cluster.

`/usr/lib/modules` is read-only on Flatcar, so the module cannot simply be copied in. The
setup script solves this by mounting a writable overlay over `/usr/lib/modules` and creating a
systemd service that installs the module on every boot. Download both scripts first, then run
only the setup script — it starts the service, and the service runs the installer for you.

### 1. Download both scripts

```sh
BASE=https://raw.githubusercontent.com/csautter/k3s-flatcar/refs/heads/main/scripts/install-nvme-tcp

curl -o /opt/install-nvme-tcp-kernel-module.sh  "$BASE/install-nvme-tcp-kernel-module.sh"
curl -o /opt/create-nvme-tcp-systemd-service.sh "$BASE/create-nvme-tcp-systemd-service.sh"

chmod +x /opt/install-nvme-tcp-kernel-module.sh /opt/create-nvme-tcp-systemd-service.sh
```

`/opt/install-nvme-tcp-kernel-module.sh` must be in place before the next step — the setup
script aborts if it cannot find it there.

### 2. Run the setup script

```sh
sudo bash /opt/create-nvme-tcp-systemd-service.sh
```

This does three things:

1. Creates and enables the `usr-lib-modules.mount` overlay unit, backed by `/opt/modules` and
   `/opt/modules.wd`, which makes `/usr/lib/modules` writable.
2. Creates and enables `install-nvme-tcp-kernel-module.service`.
3. Starts that service, which runs `/opt/install-nvme-tcp-kernel-module.sh`.

The installer detects the architecture and the running Flatcar version, downloads the matching
`nvme-tcp.ko.xz` from this repository's releases, copies it into
`/usr/lib/modules/$(uname -r)/extra`, runs `depmod`, loads it, and writes
`/etc/modules-load.d/nvme-tcp.conf` so it is loaded on boot.

The download is cached under `/opt/nvme-tcp/<release-tag>/`. Because the cache is keyed by
Flatcar release, the service picks up a matching module automatically after an OS update
instead of reusing one built for the previous kernel; caches for older releases are pruned on
each run.

### 3. Verify

```sh
systemctl status install-nvme-tcp-kernel-module.service
lsmod | grep nvme
```

You should see `nvme_tcp` listed. To reinstall the module by hand later, run
`sudo /opt/install-nvme-tcp-kernel-module.sh` directly — the overlay is already in place at
that point.

---

## Building Kernel Modules

Prebuilt modules are published as GitHub releases of this repository, so you normally do not
need to build anything yourself. To build one manually:

1. Set up the [Flatcar SDK container](https://github.com/orgs/flatcar/packages/container/package/flatcar-sdk-all).
2. Modify kernel module settings as needed.
3. Build the kernel and the module. See also: [Guide to building custom Flatcar images from source](https://www.flatcar.org/docs/latest/reference/developer-guides/sdk-modifying-flatcar/#start-the-sdk)
4. Locate the built `nvme-tcp.ko.xz` file in the SDK container.

[`build/kernel/nvme/docker-nvme-tcp.sh`](build/kernel/nvme/docker-nvme-tcp.sh) automates all
of this; it is also what the CI workflow runs.

---

## Automated Workflows

GitHub Actions are used to automate building and deploying the NVMe-TCP kernel module:

- [`build-and-deploy-nvme-tcp.yml`](.github/workflows/build-and-deploy-nvme-tcp.yml): Builds the module and creates a release.
- [`poll-flatcar-scripts-tags.yml`](.github/workflows/poll-flatcar-scripts-tags.yml): Polls the Flatcar scripts repository for new releases and triggers builds.
- [`renovate.yml`](.github/workflows/renovate.yml): Runs [Renovate](https://docs.renovatebot.com/) on a weekly schedule to keep the Flatcar SDK version, k3s version, and Butane image tag up to date via pull requests.

Dependency updates are automated:

- **[Dependabot](.github/dependabot.yml)** keeps the GitHub Actions used in these workflows up to date.
- **[Renovate](renovate.json)** tracks the Flatcar SDK/scripts version, the k3s version, and the Butane Docker image tag, which aren't covered by Dependabot's built-in ecosystems.

---

## Security Notes

- `generate-config-iso.sh` packs `.env*` into the ISO, so **`k3s_flatcar_config.iso` contains
  your `K3S_TOKEN` and SSH public keys in clear text.** Anyone holding the ISO can join a node
  to your cluster. Do not share it, and wipe it from shared storage when you are done.
- The generated Ignition JSON files embed the same token. `.gitignore` already excludes
  `.env`, `scripts/*.json` and `*.iso`, so none of this is committed — keep it that way.
- The Ignition configs fetch the k3s installer from `https://get.k3s.io` at first boot without
  checksum verification. If that is not acceptable in your environment, bake a pinned, verified
  installer into the Ignition config instead.

---

## Known Limitations

- The hostname in `server-1-ignite-boot.yaml` is `node-1`, not `server-1`.
- `server-2-install.sh` is hardcoded to `server-2-ignite-boot.json` and `/dev/sda`. There is no
  equivalent wrapper for the other nodes — call `flatcar-install` directly as shown above.
- The install script for the NVMe-TCP module hardcodes the `stable` Flatcar channel, so
  `lts-*` releases are not covered.

---

## Troubleshooting

- **Node does not join the cluster?**
  - `journalctl -u k3s-install.service` on the node shows the installer output.
  - Check that `K3S_TOKEN` is identical everywhere and that `SERVER_REGISTER_URL` is reachable:
    `curl -k https://<server-1-ip>:6443/ping`.
  - Servers use `systemctl status k3s`, agents use `systemctl status k3s-agent`.
- **`k3s-install.service` did nothing?**
  - The unit has `ConditionPathExists=!/opt/bin/k3s`, so it is skipped once k3s is installed.
    That is expected on reboots.
- **Kernel module not loading?**
  - Check `dmesg` and `lsmod | grep nvme` for errors.
  - `modprobe: ERROR: could not insert 'nvme_tcp': Exec format error` together with an
    `version magic ... should be ...` line in `dmesg` means the module does not match the
    running kernel. Check that a release exists for your Flatcar version — the installer only
    covers the `stable` channel — then clear `/opt/nvme-tcp` and re-run the installer.
- **Systemd service not starting?**
  - Run `systemctl status install-nvme-tcp-kernel-module.service` for logs.
- **ISO not booting?**
  - The ISO generated by this repo is a data ISO and is **not bootable** by design. Boot the
    official Flatcar live ISO and mount this one as a second drive, as described in step 4.
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
