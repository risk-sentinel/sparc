#!/usr/bin/env bash
# Resolve — and cross-check — the hdf-cli toolchain pins.
#
# WHY THIS EXISTS (#835, extending #962)
#
# The hdf-cli version is stated in more than one place because nothing can read
# a Dockerfile ARG from a GitHub Actions `env:` block. CI-1 was bitten by that
# directly: `security.yml` pinned HDF_LIBS_VERSION 3.4.1 while the image baked
# 3.5.1, so the security gate validated amendments with a different binary than
# the product shipped. Both sides built cleanly, so the drift was invisible.
#
# CI-2 added an assertion covering the Dockerfile against `security.yml`. That
# left a third copy unguarded — `script/dev/install-hdf.sh` carries its own
# default — and #835 would have added a fourth in `ci.yml`.
#
# So: the **Dockerfile is the single source of truth**, this script is the only
# thing that reads it, and every caller either derives from it or asserts
# against it. `ci.yml` derives (adding no copy at all); `security.yml` asserts,
# because `setup-go` needs the version before any step has run.
#
# Usage:
#   script/ci/hdf_pins.sh                 # print pins as KEY=VALUE, verify copies
#   script/ci/hdf_pins.sh --github-output # additionally append to $GITHUB_OUTPUT
#   HDF_LIBS_VERSION=x XTEXT_VERSION=y GO_FIX_LINE=z script/ci/hdf_pins.sh --assert
#                                         # fail unless the caller's values match
#
# Exit 0 on agreement, 1 on any drift or unreadable pin.

set -euo pipefail

cd "$(dirname "$0")/../.."

DOCKERFILE="Dockerfile"
INSTALL_SCRIPT="script/dev/install-hdf.sh"

fail() { echo "::error::hdf pins: $*" >&2; exit 1; }

# Capture what the CALLER passed in BEFORE anything below overwrites it.
#
# This is not defensive tidiness. Reading the Dockerfile into the same variable
# names first makes `--assert` compare the Dockerfile against itself, so it
# passes unconditionally — a guard against drift that cannot detect drift. It
# was written that way and caught only by testing the failing case, which is the
# same lesson as the gate that reported success for 85 runs.
CALLER_HDF_LIBS_VERSION="${HDF_LIBS_VERSION:-}"
CALLER_XTEXT_VERSION="${XTEXT_VERSION:-}"
CALLER_GO_FIX_LINE="${GO_FIX_LINE:-}"

[ -f "$DOCKERFILE" ] || fail "$DOCKERFILE not found (is this running from the repo root, and is it in the sparse checkout?)"

read_arg() {
  local name="$1" value
  value="$(sed -n "s/^ARG ${name}=\(.*\)$/\1/p" "$DOCKERFILE" | head -1)"
  # An ARG that is renamed or removed must not silently resolve to empty — an
  # empty version would make `git clone --branch v` fail with a confusing error
  # a long way from the cause.
  [ -n "$value" ] || fail "ARG ${name} not found in $DOCKERFILE"
  printf '%s' "$value"
}

HDF_LIBS_VERSION="$(read_arg HDF_LIBS_VERSION)"
XTEXT_VERSION="$(read_arg XTEXT_VERSION)"
GO_FIX_LINE="$(read_arg GO_FIX_LINE)"

# ── Copy 3: the developer install script's own default ────────────────────────
# It downloads a release binary rather than building, so it is not used by CI —
# but a developer running it gets whatever it says, and "the version I tested
# locally" silently differing from the image is the same class of defect.
if [ -f "$INSTALL_SCRIPT" ]; then
  script_default="$(sed -n 's/^HDF_LIBS_VERSION="\${HDF_LIBS_VERSION:-\(.*\)}"$/\1/p' "$INSTALL_SCRIPT" | head -1)"
  [ -n "$script_default" ] || fail "could not read the HDF_LIBS_VERSION default from $INSTALL_SCRIPT — its shape changed, so this check has stopped checking"
  [ "$script_default" = "$HDF_LIBS_VERSION" ] || \
    fail "$INSTALL_SCRIPT defaults to ${script_default}, $DOCKERFILE says ${HDF_LIBS_VERSION}"
fi

# ── Assert mode: the caller restated the pins; they must agree ────────────────
if [ "${1:-}" = "--assert" ]; then
  # Compares the CALLER's values (captured at entry) against the Dockerfile's.
  assert_pin() {
    local name="$1" actual="$2" expected="$3"
    [ -n "$actual" ] || fail "--assert given but ${name} is unset in the environment"
    [ "$actual" = "$expected" ] || fail "${name} drift — caller has '${actual}', $DOCKERFILE has '${expected}'"
  }
  assert_pin HDF_LIBS_VERSION "$CALLER_HDF_LIBS_VERSION" "$HDF_LIBS_VERSION"
  assert_pin XTEXT_VERSION    "$CALLER_XTEXT_VERSION"    "$XTEXT_VERSION"
  assert_pin GO_FIX_LINE      "$CALLER_GO_FIX_LINE"      "$GO_FIX_LINE"
fi

echo "HDF_LIBS_VERSION=${HDF_LIBS_VERSION}"
echo "XTEXT_VERSION=${XTEXT_VERSION}"
echo "GO_FIX_LINE=${GO_FIX_LINE}"

if [ "${1:-}" = "--github-output" ]; then
  [ -n "${GITHUB_OUTPUT:-}" ] || fail "--github-output given but GITHUB_OUTPUT is unset"
  {
    echo "hdf_libs_version=${HDF_LIBS_VERSION}"
    echo "xtext_version=${XTEXT_VERSION}"
    echo "go_fix_line=${GO_FIX_LINE}"
  } >> "$GITHUB_OUTPUT"
fi
