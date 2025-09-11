#!/bin/bash

set -euox pipefail

MODULES=/opt/modules

function create_systemd_usr_lib_modules_mount {
    sudo mkdir -p "${MODULES}" "${MODULES}.wd"
    echo "Creating systemd mount unit for /usr/lib/modules overlay..."
    cat << EOF | sudo tee /etc/systemd/system/usr-lib-modules.mount
[Unit]
Description=Custom Kernel Modules
ConditionPathExists=/opt/modules
Before=sysinit.target
After=systemd-sysext.service
DefaultDependencies=no

[Mount]
Type=overlay
What=overlay
Where=/usr/lib/modules
Options=lowerdir=/usr/lib/modules,upperdir=/opt/modules,workdir=/opt/modules.wd

[Install]
UpheldBy=systemd-sysext.service
EOF
    sudo systemctl enable --now usr-lib-modules.mount
}

# Check if /usr/lib/modules is writable and refresh overlay mount if needed

if ! touch /usr/lib/modules/testfile; then
    echo "/usr/lib/modules is read-only, setting up overlay mount..."
    if ! mount | grep -q 'on /usr/lib/modules'; then
        create_systemd_usr_lib_modules_mount
    else
        echo "/usr/lib/modules is already mounted."
        rm -f /usr/lib/modules/testfile
        systemctl disable usr-lib-modules.mount || true
        sudo umount /usr/lib/modules || true
        rm -rf "${MODULES}" "${MODULES}.wd"
        create_systemd_usr_lib_modules_mount
    fi
else
    echo "/usr/lib/modules is writable, no overlay mount needed."
    rm -f /usr/lib/modules/testfile
fi

if [ ! -f /etc/systemd/system/usr-lib-modules.mount ]; then
    create_systemd_usr_lib_modules_mount
fi

function create_systemd_install_nvme_tcp_service {
    SERVICE_NAME="install-nvme-tcp-kernel-module.service"
    SCRIPT_PATH="/opt/install-nvme-tcp-kernel-module.sh"
    if [ ! -f "$SCRIPT_PATH" ]; then
        echo "Error: $SCRIPT_PATH not found!"
        exit 1
    fi
    echo "Creating systemd service to install NVMe-TCP kernel module..."
    cat <<EOF | sudo tee /etc/systemd/system/$SERVICE_NAME
[Unit]
Description=Install NVMe-TCP Kernel Module
After=network.target

[Service]
Type=oneshot
ExecStart=$SCRIPT_PATH
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl enable $SERVICE_NAME
    sudo systemctl start $SERVICE_NAME
}

if [ ! -f /etc/systemd/system/install-nvme-tcp-kernel-modules.service ]; then
    create_systemd_install_nvme_tcp_service
fi