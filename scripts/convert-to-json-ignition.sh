#!/bin/bash
set -x

# load env variables from .env file
set -a
source .env
env

# generate ignition config files for n servers
# using the template files and the environment variables

envsubst < server-1-ignite-boot.yaml > server-1-ignite-boot.yaml.tmp
envsubst < server-2-ignite-boot.yaml > server-2-ignite-boot.yaml.tmp

docker run --rm -i quay.io/coreos/butane:latest < server-1-ignite-boot.yaml.tmp > server-1-ignite-boot.json
docker run --rm -i quay.io/coreos/butane:latest < server-2-ignite-boot.yaml.tmp > server-2-ignite-boot.json

rm server-1-ignite-boot.yaml.tmp
rm server-2-ignite-boot.yaml.tmp