#!/usr/bin/env bash
# Integration tests for the Ignition and config-ISO generation scripts.
#
# These run the real scripts from scripts/ against a fixture .env inside a
# throwaway copy, so a developer's own .env and generated files are never
# touched.
#
# Requires: docker, envsubst (gettext), mkisofs or genisoimage, isoinfo, python3.
# Run from anywhere:  tests/test-config-generation.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QUERY="$REPO_ROOT/tests/ignition-query.py"
TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

PASS=0
FAIL=0

ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() {
    FAIL=$((FAIL + 1))
    printf '  FAIL %s\n' "$1"
    [ $# -gt 1 ] && printf '         %s\n' "$2"
    return 0
}

assert_eq() { # desc expected actual
    if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$2], got [$3]"; fi
}
assert_contains() { # desc haystack needle
    case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "[$3] not found in output" ;; esac
}
assert_absent() { # desc haystack needle
    case "$2" in *"$3"*) bad "$1" "[$3] should not be present" ;; *) ok "$1" ;; esac
}
assert_line() { # desc haystack exact-line
    if printf '%s\n' "$2" | grep -Fxq -- "$3"; then ok "$1"; else bad "$1" "no line equal to [$3]"; fi
}

section() { printf '\n== %s\n' "$1"; }

require() {
    command -v "$1" > /dev/null 2>&1 || {
        echo "missing required tool: $1" >&2
        exit 2
    }
}

# A clean copy of scripts/ with a fixture .env. Each caller gets its own, so
# tests cannot affect one another.
new_workdir() {
    local d
    d="$(mktemp -d -p "$TMPROOT")"
    cp -r "$REPO_ROOT/scripts" "$d/scripts"
    rm -f "$d"/scripts/*/*.json "$d"/scripts/*.iso "$d"/scripts/.env
    cat > "$d/scripts/.env" <<'ENV'
SSH_PUB_KEY_1="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITESTKEYONE test@one"
SSH_PUB_KEY_2="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITESTKEYTWO test@two"
K3S_TOKEN="k3stokenaaaabbbbccccddddeeeeffff"
K3S_VERSION="v1.30.1+k3s1"
SERVER_REGISTER_URL="https://192.168.1.102:6443"
RKE2_TOKEN="rke2token1111222233334444555566"
RKE2_VERSION="v1.34.10+rke2r1"
RKE2_SERVER_REGISTER_URL="https://192.168.1.102:9345"
ENV
    echo "$d/scripts"
}

for t in docker envsubst isoinfo python3; do require "$t"; done
command -v mkisofs > /dev/null 2>&1 || command -v genisoimage > /dev/null 2>&1 || {
    echo "missing required tool: mkisofs (or genisoimage)" >&2
    exit 2
}

###############################################################################
section "rendering Butane templates to Ignition JSON"
###############################################################################

WORK="$(new_workdir)"
cd "$WORK" || exit 2

for distro in k3s rke2; do
    log="$TMPROOT/convert-$distro.log"
    ./convert-to-json-ignition.sh "$distro" > "$log" 2>&1
    rc=$?
    assert_eq "convert-to-json-ignition.sh $distro exits 0" 0 "$rc"
    [ "$rc" -ne 0 ] && sed 's/^/         | /' "$log"

    count="$(find "$distro" -name '*-ignite-boot.json' | wc -l | tr -d ' ')"
    assert_eq "$distro renders 4 Ignition configs" 4 "$count"

    # Butane reports a dropped or misspelled key as a warning and still exits 0,
    # which is how contents.remote silently produced an empty install script.
    # Treat any warning as a failure.
    warnings="$(grep -c 'warning\[\|error\[' "$log")"
    assert_eq "$distro renders without Butane warnings" 0 "$warnings"
    [ "$warnings" -ne 0 ] && grep -A2 'warning\[\|error\[' "$log" | sed 's/^/         | /'

    # An unsubstituted placeholder means .env and the templates disagree.
    leftover="$(grep -l '\${' "$distro"/*.json 2> /dev/null)"
    assert_eq "$distro leaves no unsubstituted placeholders" "" "$leftover"
done

###############################################################################
section "installer scripts are actually downloaded"
###############################################################################

# Regression test. contents.remote.url is Container Linux Config v2 syntax that
# Butane drops, leaving a file entry with no contents at all. Ignition then
# creates an empty installer script, the unit's ConditionPathExists is still
# satisfied, and the distribution is never installed.
for node in server-1 server-2 server-3 agent-1; do
    got="$(python3 "$QUERY" "k3s/$node-ignite-boot.json" content /opt/k3s-install.sh 2>&1)"
    assert_eq "k3s $node downloads the k3s installer" "https://get.k3s.io" "$got"

    got="$(python3 "$QUERY" "rke2/$node-ignite-boot.json" content /opt/rke2-install.sh 2>&1)"
    assert_eq "rke2 $node downloads the RKE2 installer" "https://get.rke2.io" "$got"
done

###############################################################################
section "envsubst allowlist"
###############################################################################

# Regression test. A bare envsubst expands every variable present in the build
# environment, including the $PATH that this file is meant to carry to the node
# verbatim, baking the build host's PATH into the config.
profile="$(python3 "$QUERY" rke2/server-1-ignite-boot.json content /etc/profile.d/rke2.sh)"
assert_contains "rke2 profile.d keeps \$PATH literal" "$profile" '$PATH'
assert_absent   "rke2 profile.d has no build-host PATH" "$profile" "/usr/local/sbin"
assert_contains "rke2 profile.d sets KUBECONFIG" "$profile" "/etc/rancher/rke2/rke2.yaml"

###############################################################################
section "RKE2 cluster configuration"
###############################################################################

assert_eq "rke2 config.yaml is mode 0600" "0600" \
    "$(python3 "$QUERY" rke2/server-1-ignite-boot.json mode /etc/rancher/rke2/config.yaml)"

cfg1="$(python3 "$QUERY" rke2/server-1-ignite-boot.json content /etc/rancher/rke2/config.yaml)"
assert_contains "rke2 server-1 carries the token" "$cfg1" "rke2token1111222233334444555566"
assert_contains "rke2 server-1 enables secrets encryption" "$cfg1" "secrets-encryption: true"
# The bootstrap node must not point at itself, or it will not initialise etcd.
assert_absent   "rke2 server-1 has no server: key" "$cfg1" "server: http"

cfg2="$(python3 "$QUERY" rke2/server-2-ignite-boot.json content /etc/rancher/rke2/config.yaml)"
assert_contains "rke2 server-2 joins on the supervisor port 9345" "$cfg2" ":9345"
assert_absent   "rke2 server-2 does not join on 6443" "$cfg2" ":6443"

agent="$(python3 "$QUERY" rke2/agent-1-ignite-boot.json content /etc/rancher/rke2/config.yaml)"
assert_contains "rke2 agent joins on the supervisor port 9345" "$agent" ":9345"

###############################################################################
section "systemd units"
###############################################################################

# The RKE2 installer only unpacks the tarball; unlike the k3s installer it never
# starts the service. Without these the node installs RKE2 and then sits idle.
units="$(python3 "$QUERY" rke2/server-1-ignite-boot.json units)"
assert_contains "rke2 server enables rke2-server" "$units" "systemctl enable rke2-server.service"
assert_contains "rke2 server starts rke2-server" "$units" "start --no-block rke2-server.service"
assert_contains "rke2 server installs to /opt/rke2" "$units" "INSTALL_RKE2_TAR_PREFIX=/opt/rke2"
assert_contains "rke2 server pins the version" "$units" "INSTALL_RKE2_VERSION=v1.34.10+rke2r1"

units="$(python3 "$QUERY" rke2/agent-1-ignite-boot.json units)"
assert_contains "rke2 agent installs the agent type" "$units" "INSTALL_RKE2_TYPE=agent"
assert_contains "rke2 agent enables rke2-agent" "$units" "systemctl enable rke2-agent.service"
assert_absent   "rke2 agent does not start a server" "$units" "rke2-server.service"

units="$(python3 "$QUERY" k3s/server-1-ignite-boot.json units)"
assert_contains "k3s server-1 initialises the cluster" "$units" "cluster-init"

###############################################################################
section "config ISO"
###############################################################################

for distro in k3s rke2; do
    log="$TMPROOT/iso-$distro.log"
    ./generate-config-iso.sh "$distro" > "$log" 2>&1
    rc=$?
    assert_eq "generate-config-iso.sh $distro exits 0" 0 "$rc"
    [ "$rc" -ne 0 ] && sed 's/^/         | /' "$log"

    iso="${distro}_flatcar_config.iso"
    if [ ! -f "$iso" ]; then
        bad "$distro ISO is created" "$iso does not exist"
        continue
    fi
    ok "$distro ISO is created"

    listing="$(isoinfo -R -f -i "$iso")"

    # The node configs must sit at the ISO root, not under a $distro/
    # directory, so the paths below /mnt are the same for either distribution.
    for node in server-1 server-2 server-3 agent-1; do
        assert_line "$distro ISO has /$node-ignite-boot.json at the root" \
            "$listing" "/$node-ignite-boot.json"
    done
    assert_absent "$distro ISO has no $distro/ subdirectory" "$listing" "/$distro/"

    assert_line "$distro ISO carries the helper scripts" "$listing" "/convert-to-json-ignition.sh"

    volid="$(isoinfo -d -i "$iso" | sed -n 's/^Volume id: //p')"
    assert_eq "$distro ISO volume id" "${distro}-flatcar" "$volid"

    # The ISO must carry this distribution's configs, not the other one's.
    extracted="$(isoinfo -R -i "$iso" -x /server-1-ignite-boot.json)"
    case "$distro" in
        k3s)  assert_contains "k3s ISO ships k3s configs"   "$extracted" "get.k3s.io"
              assert_absent   "k3s ISO ships no rke2 configs" "$extracted" "get.rke2.io" ;;
        rke2) assert_contains "rke2 ISO ships rke2 configs"  "$extracted" "get.rke2.io"
              assert_absent   "rke2 ISO ships no k3s configs" "$extracted" "get.k3s.io" ;;
    esac
done

###############################################################################
section "shipped .env.example defaults"
###############################################################################

# The fixture .env above is independent of .env.example, so nothing else here
# would notice a wrong default in the file users actually copy.
example="$(cat "$REPO_ROOT/scripts/.env.example")"
assert_contains "k3s register URL uses the API port 6443" "$example" 'SERVER_REGISTER_URL="https://192.168.1.102:6443"'
assert_contains "RKE2 register URL uses the supervisor port 9345" "$example" 'RKE2_SERVER_REGISTER_URL="https://192.168.1.102:9345"'

for var in SSH_PUB_KEY_1 SSH_PUB_KEY_2 K3S_TOKEN K3S_VERSION SERVER_REGISTER_URL \
    RKE2_TOKEN RKE2_VERSION RKE2_SERVER_REGISTER_URL; do
    assert_contains ".env.example defines $var" "$example" "$var="
done

# Every placeholder the templates reference must be in the allowlist, or it
# renders empty. This catches a new ${VAR} added to a template and nowhere else.
missing=""
for var in $(grep -ho '\${[A-Z0-9_]*}' "$REPO_ROOT"/scripts/*/*.yaml | tr -d '${}' | sort -u); do
    grep -q "\${$var}" "$REPO_ROOT/scripts/convert-to-json-ignition.sh" || missing="$missing $var"
done
assert_eq "every template placeholder is in the envsubst allowlist" "" "$missing"

###############################################################################
section "pinned tool versions"
###############################################################################

# The Butane image is pinned in two places: the conversion script and the CI
# workflow that exercises it. If they drift, CI stops testing what ships.
script_pin="$(sed -n 's|.*quay\.io/coreos/butane:\([^ "]*\).*|\1|p' \
    "$REPO_ROOT/scripts/convert-to-json-ignition.sh" | head -1)"
ci_pin="$(sed -n 's|.*quay\.io/coreos/butane:\([^ "]*\).*|\1|p' \
    "$REPO_ROOT/.github/workflows/test-config-generation.yml" | head -1)"
assert_eq "CI pins the same Butane version as the conversion script" "$script_pin" "$ci_pin"
[ -n "$script_pin" ] && ok "conversion script pins a Butane version ($script_pin)" \
    || bad "conversion script pins a Butane version" "no pin found"

###############################################################################
section "error handling"
###############################################################################

WORK="$(new_workdir)"
cd "$WORK" || exit 2

./convert-to-json-ignition.sh nosuchdistro > /dev/null 2>&1
assert_eq "convert rejects an unknown distribution" 1 "$?"

./generate-config-iso.sh nosuchdistro > /dev/null 2>&1
assert_eq "ISO build rejects an unknown distribution" 1 "$?"

# Nothing rendered yet, so there is no JSON to pack.
./generate-config-iso.sh k3s > /dev/null 2>&1
assert_eq "ISO build refuses to run before conversion" 1 "$?"

rm -f .env
./convert-to-json-ignition.sh k3s > /dev/null 2>&1
assert_eq "convert refuses to run without .env" 1 "$?"

###############################################################################
printf '\n%s\n' "-----------------------------------------"
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
