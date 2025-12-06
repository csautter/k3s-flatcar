#!/bin/bash
set -ex

if [ -z "$VERSION" ]; then
    VERSION=stable-4230.2.2
fi
echo "Full version: $VERSION"
VERSION_MAJOR=$(echo $VERSION | sed -E 's/^.*?-//' | cut -d. -f1)
echo "Major version: $VERSION_MAJOR -> reduced for container image tag"
CONTAINER_NAME=ghcr.io/flatcar/flatcar-sdk-all:$VERSION_MAJOR.0.0

docker pull $CONTAINER_NAME
mkdir -p ./deployments/kernel/nvme/modules

cat build/kernel/nvme/docker-nvme-tcp-inner-script.sh | docker run -i --privileged -v /dev:/dev -v ./deployments/kernel/nvme/modules:/opt/kernel-modules/ $CONTAINER_NAME bash

container_id=$(docker ps -l -q)
echo "Container ID: $container_id"
docker container stop $container_id