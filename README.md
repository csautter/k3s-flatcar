# k3s and RKE2 on Flatcar Linux

This project provides a reference implementation for installing [k3s](https://k3s.io/) or
[RKE2](https://docs.rke2.io/) on [Flatcar Linux](https://www.flatcar.org/). It automates the
process of building and deploying the NVMe-TCP kernel module, and generates a ready-to-use
config ISO for VM or bare metal installation.

---

## Table of Contents

- [Project Overview](#project-overview)
- [Choosing a Distribution](#choosing-a-distribution)
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
- [Optional Hardening](#optional-hardening)
  - [CIS profile (RKE2)](#cis-profile-rke2)
  - [Reboot coordination](#reboot-coordination)
- [NVMe-TCP Kernel Module](#nvme-tcp-kernel-module)
- [Building Kernel Modules](#building-kernel-modules)
- [Automated Workflows](#automated-workflows)
- [Tests](#tests)
- [Security Notes](#security-notes)
- [Known Limitations](#known-limitations)
- [Troubleshooting](#troubleshooting)
- [License](#license)
- [Contributing](#contributing)

---

## Project Overview

This repository helps you:

- Provision k3s **or** RKE2 server (control-plane) and agent (worker) nodes on Flatcar Linux
  via Ignition.
- Generate a config ISO carrying the Ignition files for Flatcar and the chosen distribution.
- Build and deploy the NVMe-TCP kernel module for Flatcar Linux (required for storage
  solutions like OpenEBS or Rancher Longhorn).
- Automate module builds and dependency updates using GitHub Actions.

## Choosing a Distribution

Both distributions are supported by the same tooling and the same workflow. You pick one when
you generate the ISO; the templates live side by side in `scripts/k3s/` and `scripts/rke2/`.

| | k3s | RKE2 |
| --- | --- | --- |
| Footprint | Smallest. Single binary, SQLite or embedded etcd. | Larger. Control plane runs as static pods. |
| Focus | Edge, IoT, small clusters, development. | Security and compliance: CIS benchmarks, FIPS-capable builds. |
| Configured by | Env vars in the systemd unit (`K3S_TOKEN`, `INSTALL_K3S_EXEC`). | `/etc/rancher/rke2/config.yaml`. |
| Node registration port | `6443` (same as the API server). | **`9345`** (separate supervisor port). |
| Binary | `/opt/bin/k3s` | `/opt/rke2/bin/rke2` |
| `kubectl` | `/opt/bin/k3s kubectl` | `/var/lib/rancher/rke2/bin/kubectl` |
| Kubeconfig | `/etc/rancher/k3s/k3s.yaml` | `/etc/rancher/rke2/rke2.yaml` |
| systemd units | `k3s`, `k3s-agent` | `rke2-server`, `rke2-agent` |

If you have no specific requirement, start with k3s. Choose RKE2 if you need a CIS-attestable
or FIPS-capable control plane — see [CIS profile (RKE2)](#cis-profile-rke2).

Both install to `/opt` rather than `/usr/local`, because `/usr` is read-only on Flatcar.

## Cluster Topology

Every node is described by one Butane template. Within a distribution the templates differ
only in hostname and in how the node is told to start.

| Template | Role | k3s mode | RKE2 mode |
| --- | --- | --- | --- |
| `server-1-ignite-boot.yaml` | First server | `--cluster-init` | no `server:` key, bootstraps etcd |
| `server-2-ignite-boot.yaml` | Additional server | `server --server $SERVER_REGISTER_URL` | `server: $RKE2_SERVER_REGISTER_URL` |
| `server-3-ignite-boot.yaml` | Additional server | `server --server $SERVER_REGISTER_URL` | `server: $RKE2_SERVER_REGISTER_URL` |
| `agent-1-ignite-boot.yaml` | Agent (worker) | `agent` + `K3S_URL` | `INSTALL_RKE2_TYPE=agent` + `server:` |

Servers run the Kubernetes control plane and the embedded etcd, and they also schedule
workloads. Agents only run workloads. Because etcd needs a quorum, use an **odd number of
servers** — one for a test cluster, three for high availability. Add as many agents as you
need capacity for.

A single-server cluster is perfectly valid: install `server-1` only, then add agents.

## Scripts

Node templates (Butane YAML, converted to Ignition JSON):

- [`scripts/k3s/`](scripts/k3s/): `server-1`, `server-2`, `server-3` and `agent-1` templates for k3s.
- [`scripts/rke2/`](scripts/rke2/): the same four node roles for RKE2.
- [`scripts/.env.example`](scripts/.env.example): Template for the `.env` file that fills in the placeholders in both sets.

Tooling (run from `scripts/`, each takes the distribution as its only argument, default `k3s`):

- [`scripts/convert-to-json-ignition.sh`](scripts/convert-to-json-ignition.sh): Substitutes the `.env` variables into every `*-ignite-boot.yaml` of the chosen distribution and converts each one to Ignition JSON.
- [`scripts/generate-config-iso.sh`](scripts/generate-config-iso.sh): Packs those configs into `<distro>_flatcar_config.iso`.
- [`scripts/server-2-install.sh`](scripts/server-2-install.sh): Convenience wrapper that runs `flatcar-install` on the node. Defaults to `server-2-ignite-boot.json` and `/dev/sda`; both can be overridden as arguments.
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
  config downloads the installer from `https://get.k3s.io` or `https://get.rke2.io` on first
  boot.

---

## Installation & Usage

### 1. Configure your cluster

```sh
cp scripts/.env.example scripts/.env
```

Edit `scripts/.env`. The SSH keys are shared; the rest is per distribution, and you only need
to fill in the block for the distribution you intend to build.

| Variable | Description |
| --- | --- |
| `SSH_PUB_KEY_1` | SSH public key authorized for the `core` user. |
| `SSH_PUB_KEY_2` | A second SSH public key. If you only need one key, remove the `${SSH_PUB_KEY_2}` line from the templates — leaving it empty renders an empty entry. |
| `K3S_TOKEN` / `RKE2_TOKEN` | Shared cluster secret, identical on every node. Generate one with `openssl rand -hex 32`. |
| `K3S_VERSION` / `RKE2_VERSION` | Version to pin, e.g. `v1.30.1+k3s1` or `v1.34.10+rke2r1`. |
| `SERVER_REGISTER_URL` | k3s: API endpoint of the first server, port **6443**. |
| `RKE2_SERVER_REGISTER_URL` | RKE2: supervisor endpoint of the first server, port **9345**. |

The register URL is only read by the joining nodes, so it may point at an IP that does not
exist yet — just make sure `server-1` really ends up on that address before you boot any other
node. Give `server-1` a static IP or a DHCP reservation.

> **The port differs between the two.** k3s joins on 6443, the same port as the API server.
> RKE2 runs a separate supervisor on **9345** for node registration. Pointing an RKE2 node at
> 6443 will not join.

### 2. Adjust the node templates

Each template hardcodes its hostname in `/etc/hostname`. Edit the templates if you want
different names, delete the ones you do not need, and copy an existing one to add more nodes:

```sh
# a second RKE2 worker
cp scripts/rke2/agent-1-ignite-boot.yaml scripts/rke2/agent-2-ignite-boot.yaml
# then change the /etc/hostname inline value to rke2-agent-2
```

`convert-to-json-ignition.sh` converts every `*-ignite-boot.yaml` in the distribution's
directory, so new templates are picked up automatically.

For an HA control plane behind a fixed address or VIP, add a `tls-san` entry to the RKE2
`config.yaml` block so the API server certificate covers it:

```yaml
          tls-san:
            - cluster.example.com
```

### 3. Generate the config ISO

Both scripts read files relative to the current directory, so run them from `scripts/`:

```sh
cd scripts
./convert-to-json-ignition.sh rke2   # or k3s; renders .env into that distro's templates
./generate-config-iso.sh rke2        # packs them into rke2_flatcar_config.iso
```

Omitting the argument defaults to `k3s`, so the original two-command flow still works.

The result is `scripts/rke2_flatcar_config.iso` (or `k3s_flatcar_config.iso`). It contains one
Ignition JSON per node plus the helper scripts, so the **same ISO is used for every node of
that cluster** — you pick the node's role by choosing which JSON file you pass to
`flatcar-install`. The node configs sit at the root of the ISO regardless of distribution, so
the paths below `/mnt` are the same either way.

### 4. Install the first server node

1. Boot the machine from the official Flatcar **live** ISO.
2. Attach the config ISO as a second optical drive and mount it:

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

On first boot, Ignition writes the hostname, the SSH keys and the installer script, then the
one-shot install unit runs. This takes a minute or two and needs internet access.

### 5. Verify the first node

SSH in as `core` and check that the control plane came up before installing any other node.

**k3s:**

```sh
systemctl status k3s-install.service   # the one-shot installer
systemctl status k3s                   # the k3s server itself
sudo /opt/bin/k3s kubectl get nodes
```

**RKE2:**

```sh
systemctl status rke2-install.service  # the one-shot installer
systemctl status rke2-server           # the RKE2 server itself
sudo journalctl -u rke2-server -f      # first start pulls the control plane images
sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get nodes
```

RKE2's first start is noticeably slower than k3s: it pulls and starts the control plane
components as static pods. Give it a few minutes before concluding something is wrong.

Logging in as `core` also sources `/etc/profile.d/rke2.sh`, which puts `rke2` and `kubectl` on
your `PATH` and sets `KUBECONFIG`, so after a fresh login this is enough:

```sh
sudo -i
kubectl get nodes
```

### 6. Add the remaining server nodes

Only if you want a highly available control plane. Repeat step 4 on each additional machine,
pointing at that node's config:

```sh
sudo flatcar-install -d /dev/sda -C stable -i /mnt/server-2-ignite-boot.json
# and on the third machine
sudo flatcar-install -d /dev/sda -C stable -i /mnt/server-3-ignite-boot.json
```

These nodes join the cluster at the register URL using the shared token, so `server-1` must be
running and reachable first.

### 7. Add agent (worker) nodes

Agents are installed exactly the same way, using an agent config:

```sh
sudo flatcar-install -d /dev/sda -C stable -i /mnt/agent-1-ignite-boot.json
```

For k3s the agent template sets `K3S_URL` and `INSTALL_K3S_EXEC=agent`. For RKE2 it sets
`INSTALL_RKE2_TYPE=agent`, which makes the installer lay down `rke2-agent.service` instead of
`rke2-server.service`, and the node registers against the existing control plane with the
shared token.

To add more workers, create `agent-2-ignite-boot.yaml`, `agent-3-ignite-boot.yaml`, … as shown
in step 2, regenerate the ISO (step 3), and repeat this step. A worker needs nothing else —
no changes on the server side.

Check an agent with:

```sh
systemctl status k3s-agent    # k3s
systemctl status rke2-agent   # RKE2
journalctl -u rke2-agent -f
```

Note that `kubectl` is not usable on agent nodes: there is no kubeconfig there. Run cluster
queries from a server node.

### 8. Verify the cluster

On any server node:

```sh
sudo /opt/bin/k3s kubectl get nodes -o wide                                   # k3s
sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get nodes -o wide   # RKE2
```

Servers appear with roles `control-plane,etcd,master`; agents show `<none>` in the ROLES
column, which is normal. All nodes should be `Ready`.

To use `kubectl` from your workstation, copy the kubeconfig from a server node and replace the
`127.0.0.1` in `clusters[].cluster.server` with the node's IP address:

```sh
# k3s
scp core@<server-1-ip>:/etc/rancher/k3s/k3s.yaml ~/.kube/k3s-flatcar.yaml
# RKE2
scp core@<server-1-ip>:/etc/rancher/rke2/rke2.yaml ~/.kube/rke2-flatcar.yaml

sed -i 's#https://127.0.0.1:6443#https://<server-1-ip>:6443#' ~/.kube/rke2-flatcar.yaml
export KUBECONFIG=~/.kube/rke2-flatcar.yaml
kubectl get nodes
```

Both kubeconfigs are mode `0600` and owned by root, so `scp` as `core` needs the file to be
readable first — copy it with `sudo cat` over SSH, or relax the mode on the node.

If a node does not show up, check the install unit's journal on that node — a wrong token or
an unreachable register URL is the usual cause.

---

## Optional Hardening

Neither of the following is enabled by default. Both are worth doing for a cluster you intend
to keep.

### CIS profile (RKE2)

RKE2 can enforce the CIS Kubernetes benchmark with a single config key, but it **will refuse
to start** if the host is not prepared first. Do these three things in order.

**1. Create the `etcd` user and group.** RKE2 exits if they are missing under a CIS profile.
Add this to the `passwd` block of every RKE2 *server* template, so it exists before first
boot:

```yaml
passwd:
  users:
    - name: core
      ssh_authorized_keys:
        - ${SSH_PUB_KEY_1}
        - ${SSH_PUB_KEY_2}
    - name: etcd
      system: true
      no_create_home: true
      primary_group: etcd
      shell: /sbin/nologin
  groups:
    - name: etcd
      system: true
```

**2. Activate the sysctl settings.** RKE2 ships the required `sysctl` config but does not
apply it. On each server node, after the first boot:

```sh
sudo cp -f /opt/rke2/share/rke2/rke2-cis-sysctl.conf /etc/sysctl.d/60-rke2-cis.conf
sudo sysctl --system
```

**3. Enable the profile.** Add it to the `config.yaml` block in the template:

```yaml
          profile: cis
```

`protect-kernel-defaults` is implied by the profile — setting it to `false` alongside a CIS
profile makes RKE2 exit with an error. Use `cis` on v1.25 and newer; older releases use the
versioned names (`cis-1.6`, `cis-1.23`).

Note that a CIS-profile cluster also applies a default-deny `NetworkPolicy` in the built-in
namespaces, so plan for that before enabling it on an existing cluster. See the
[RKE2 hardening guide](https://docs.rke2.io/security/hardening_guide) for the full list of
controls.

### Reboot coordination

Flatcar's `update-engine` reboots nodes on its own schedule. On a multi-server cluster this
can take two control-plane nodes down at once and **lose etcd quorum**. This applies to k3s
and RKE2 alike.

Turn the automatic reboot off on every node by adding this to the template:

```yaml
    - path: /etc/flatcar/update.conf
      mode: 0644
      overwrite: true
      contents:
        inline: |
          GROUP=stable
          REBOOT_STRATEGY=off
```

Keep the `GROUP=` line that matches the channel you installed with — this file is replaced
wholesale, so omitting it changes which channel the node tracks.

Then install [kured](https://kured.dev/) in the cluster. It watches for the reboot-required
flag Flatcar sets, cordons and drains one node at a time, reboots it, and uncordons it. With
`REBOOT_STRATEGY=off` the node applies updates but waits for kured to act, so you keep quorum.

This is the piece most setups skip and then debug at 3am.

---

## NVMe-TCP Kernel Module

Storage solutions such as OpenEBS Mayastor or Rancher Longhorn need the NVMe-TCP kernel
module, which Flatcar does not ship. This section is distribution-agnostic — it applies
unchanged to k3s and RKE2 nodes. Run these steps **on every node that should run storage
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
- [`test-config-generation.yml`](.github/workflows/test-config-generation.yml): Runs the config generation tests on every change to `scripts/` or `tests/`.
- [`renovate.yml`](.github/workflows/renovate.yml): Runs [Renovate](https://docs.renovatebot.com/) on a weekly schedule to keep the Flatcar SDK version, the k3s and RKE2 versions, and the Butane image tag up to date via pull requests.

Dependency updates are automated:

- **[Dependabot](.github/dependabot.yml)** keeps the GitHub Actions used in these workflows up to date.
- **[Renovate](renovate.json)** tracks the Flatcar SDK/scripts version, the k3s and RKE2 versions, and the Butane Docker image tag, which aren't covered by Dependabot's built-in ecosystems.

---

## Tests

[`tests/test-config-generation.sh`](tests/test-config-generation.sh) runs the real
generation scripts against a fixture `.env` inside a throwaway copy of `scripts/`, so your
own `.env` and generated files are never touched. It covers both distributions end to end:
templates render without Butane warnings, the installer scripts are actually downloaded,
the cluster token and register ports land where they should, the systemd units enable and
start the right service, and the config ISO carries that distribution's configs at the ISO
root.

```sh
tests/test-config-generation.sh
```

Requires `docker`, `envsubst`, `mkisofs` (or `genisoimage`), `isoinfo` and `python3`. It
exits non-zero on the first failing assertion set and prints a pass/fail summary.

The suite is run in CI by
[`test-config-generation.yml`](.github/workflows/test-config-generation.yml) on every push
and pull request that touches `scripts/` or `tests/`.

It does **not** boot a node. Whether a config actually brings up a cluster can only be
confirmed by installing one, as described above.

---

## Security Notes

- `generate-config-iso.sh` packs `.env*` into the ISO, so **the generated ISO contains your
  cluster token and SSH public keys in clear text.** Anyone holding the ISO can join a node to
  your cluster. Do not share it, and wipe it from shared storage when you are done.
- The generated Ignition JSON files embed the same token. `.gitignore` already excludes
  `.env`, `scripts/**/*.json` and `*.iso`, so none of this is committed — keep it that way.
- The RKE2 token is written to `/etc/rancher/rke2/config.yaml` with mode `0600`. The k3s token
  is passed as a systemd `Environment=` line, which is world-readable via `systemctl cat`.
- The Ignition configs fetch the installer from `https://get.k3s.io` / `https://get.rke2.io` at
  first boot without checksum verification. If that is not acceptable in your environment, bake
  a pinned, verified installer into the Ignition config instead.

---

## Known Limitations

- The hostname in `scripts/k3s/server-1-ignite-boot.yaml` is `node-1`, not `server-1`.
- The install script for the NVMe-TCP module hardcodes the `stable` Flatcar channel, so
  `lts-*` releases are not covered.
- One `.env` holds the settings for both distributions. Building a k3s ISO with only the RKE2
  block filled in renders empty k3s placeholders rather than failing.

---

## Troubleshooting

- **Node does not join the cluster?**
  - `journalctl -u k3s-install.service` / `journalctl -u rke2-install.service` on the node
    shows the installer output.
  - Check that the token is identical everywhere and that the register URL is reachable.
  - **Check the port.** RKE2 joins on `9345`, not `6443`. A `RKE2_SERVER_REGISTER_URL`
    pointing at 6443 is the single most common RKE2 misconfiguration here. Verify with
    `curl -k https://<server-1-ip>:9345/ping`.
  - Servers use `systemctl status k3s` / `rke2-server`, agents `k3s-agent` / `rke2-agent`.
- **The install unit did nothing?**
  - The units have `ConditionPathExists=!/opt/bin/k3s` and `!/opt/rke2/bin/rke2`, so they are
    skipped once the distribution is installed. That is expected on reboots.
- **RKE2 installed but nothing is running?**
  - Unlike the k3s installer, `get.rke2.io` only unpacks the tarball — it never starts the
    service. The templates handle this with two `ExecStartPost=` lines that enable and start
    `rke2-server`/`rke2-agent`. If you wrote your own template and the node has
    `/opt/rke2/bin/rke2` but no running unit, that is the missing piece.
- **RKE2 refuses to start with a CIS profile?**
  - The `etcd` user and group must exist on the host, and the sysctl settings must be applied.
    See [CIS profile (RKE2)](#cis-profile-rke2).
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
