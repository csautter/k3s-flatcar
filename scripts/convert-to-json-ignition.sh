#!/bin/bash
set -e
set -x

# Renders the Butane templates of one Kubernetes distribution into Ignition JSON.
# Usage: ./convert-to-json-ignition.sh [k3s|rke2]   (default: k3s)

DISTRO="${1:-k3s}"

if [ ! -d "$DISTRO" ]; then
    echo "unknown distribution '$DISTRO': no such directory next to this script" >&2
    echo "usage: $0 [k3s|rke2]" >&2
    exit 1
fi

if [ ! -f .env ]; then
    echo "no .env found, copy .env.example to .env and fill it in first" >&2
    exit 1
fi

# Load the cluster configuration. Tracing is off across the source so the
# token does not end up in the terminal or in CI logs.
set +x
set -a
# shellcheck disable=SC1091
source .env
set +a
set -x

# Only these placeholders are substituted. A bare envsubst would also expand
# shell variables that the templates are meant to write out verbatim, such as
# the $PATH in /etc/profile.d/rke2.sh, baking the build host's value into the node.
SUBST_VARS='${SSH_PUB_KEY_1} ${SSH_PUB_KEY_2}'
SUBST_VARS="$SUBST_VARS "'${K3S_TOKEN} ${K3S_VERSION} ${SERVER_REGISTER_URL}'
SUBST_VARS="$SUBST_VARS "'${RKE2_TOKEN} ${RKE2_VERSION} ${RKE2_SERVER_REGISTER_URL}'

# generate ignition config files for every node of the selected distribution
# using the template files and the environment variables
for template in "$DISTRO"/*-ignite-boot.yaml; do
    base="${template%.yaml}"
    envsubst "$SUBST_VARS" < "$template" > "$base.yaml.tmp"
    docker run --rm -i quay.io/coreos/butane:v0.29.0 < "$base.yaml.tmp" > "$base.json"
    rm "$base.yaml.tmp"
done
