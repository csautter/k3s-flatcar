#!/bin/bash

set -euox pipefail

function create_systemd_usr_lib_modules_mount {
    modules=/opt/modules
    sudo mkdir -p "${modules}" "${modules}.wd"
    echo "Creating systemd mount unit for /usr/lib/modules overlay..."
    cat << EOF | sudo tee /etc/systemd/system/usr-lib-modules.mount
[Unit]
Description=Custom Kernel Modules
Before=local-fs.target
ConditionPathExists=/opt/modules

[Mount]
Type=overlay
What=overlay
Where=/usr/lib/modules
Options=lowerdir=/usr/lib/modules,upperdir=/opt/modules,workdir=/opt/modules.wd

[Install]
WantedBy=local-fs.target
EOF
    sudo systemctl enable --now usr-lib-modules.mount
}

if [ ! -f /etc/systemd/system/usr-lib-modules.mount ]; then
    create_systemd_usr_lib_modules_mount
fi

function create_systemd_install_nvme_tcp_service {
    SERVICE_NAME="install-nvme-tcp-kernel-modules.service"
    SCRIPT_PATH="/opt/install-nvme-tcp-kernel-modules.sh"
    if [ ! -f "$SCRIPT_PATH" ]; then
        echo "Error: $SCRIPT_PATH not found!"
        exit 1
    fi
    echo "Creating systemd service to install NVMe-TCP kernel modules..."
    cat <<EOF | sudo tee /etc/systemd/system/$SERVICE_NAME
[Unit]
Description=Install NVMe-TCP Kernel Modules
After=network.target

[Service]
Type=oneshot
ExecStart=$SCRIPT_PATH
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl enable --now $SERVICE_NAME
}

if [ ! -f /etc/systemd/system/install-nvme-tcp-kernel-modules.service ]; then
    create_systemd_install_nvme_tcp_service
fi