#!/bin/bash
set -e
set -x

# load env variables from .env file
set -a
source .env
env

# generate ignition config files for every node
# using the template files and the environment variables

for template in *-ignite-boot.yaml; do
    base="${template%.yaml}"
    envsubst < "$template" > "$base.yaml.tmp"
    docker run --rm -i quay.io/coreos/butane:v0.29.0 < "$base.yaml.tmp" > "$base.json"
    rm "$base.yaml.tmp"
done
