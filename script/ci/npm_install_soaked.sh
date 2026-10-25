#!/usr/bin/env bash
# Install one exactly-pinned npm CLI for a CI job, from versions at least seven
# days old, and verify every installed package's registry signature.
#
#   script/ci/npm_install_soaked.sh <dir> <package@x.y.z>
#
# The tool is pinned exactly (#966); its dependencies are not, so each run
# resolves them afresh. `--before` holds every dependency to versions published
# at least seven days ago: the worm waves of 2026 published poisoned versions of
# trusted packages that were caught and pulled within days, so a week's soak
# keeps CI from installing one in that window (owner, 2026-10-25). Lifecycle
# scripts stay off (`--ignore-scripts`, githubactions:S6505), and
# `npm audit signatures` fails the step if any installed package lacks a valid
# registry signature. It does not support global installs, so tools install
# under <dir> and the caller puts <dir>/node_modules/.bin on PATH.
#
# The SonarQube bridge (sonarqube-hdf.yml) runs these same two commands inline:
# its job has no checkout to run this script from.
#
#   NIST SR-3, SR-11, SI-7
set -euo pipefail

dir=${1:?usage: npm_install_soaked.sh <dir> <package@x.y.z>}
pkg=${2:?usage: npm_install_soaked.sh <dir> <package@x.y.z>}

if [[ ! $pkg =~ @[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "::error::$pkg is not pinned to an exact version" >&2
  exit 1
fi

# GNU date on the runners; the BSD form lets the script run on a Mac too.
before=$(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-7d +%Y-%m-%dT%H:%M:%SZ)
echo "Installing $pkg into $dir from versions published before $before"

mkdir -p "$dir"
npm install --prefix "$dir" --no-save --ignore-scripts --no-fund --no-audit --before="$before" "$pkg"
npm audit signatures --prefix "$dir"
