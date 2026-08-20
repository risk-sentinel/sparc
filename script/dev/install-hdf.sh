#!/usr/bin/env bash
# Install the MITRE hdf-libs CLI (https://github.com/mitre/hdf-libs).
#
# LOCAL DEVELOPER CONVENIENCE ONLY (#1001). This downloads MITRE's published
# release binary, which is the fastest way to get a working `hdf` on a laptop.
#
# It is deliberately NOT how the shipping image or CI gets the tool any more.
# Both compile hdf-cli from source against a pinned Go toolchain, because the
# published binaries are built with go1.26.5 and the GO-2026-5026 stdlib fix
# line is go1.26.6 — no release download can clear that, whatever version it
# names. See the hdf-builder stage in ./Dockerfile and the security_gate job
# in .github/workflows/security.yml.
#
# So a binary installed by this script may report the same `hdf version` as the
# one in the container and still carry CVEs the container does not. That is
# fine for local work and is the reason this lives under script/dev/ rather
# than bin/. Do not re-wire a build or a gate to it.
#
# Pinned version: HDF_LIBS_VERSION env var (default tracks current SPARC release).
# Install path:   $HDF_INSTALL_DIR (default /usr/local/bin) — caller may need sudo.
#
# Verifies SHA-256 of the downloaded tarball against checksums.txt from the
# same GitHub release before extracting. Refuses to install on mismatch.

set -euo pipefail

HDF_LIBS_VERSION="${HDF_LIBS_VERSION:-3.5.1}"
HDF_INSTALL_DIR="${HDF_INSTALL_DIR:-/usr/local/bin}"

# Detect platform
case "$(uname -s)" in
  Linux*)   OS="linux" ;;
  Darwin*)  OS="darwin" ;;
  *)        echo "::error:: unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac

case "$(uname -m)" in
  x86_64|amd64)  ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *)             echo "::error:: unsupported arch: $(uname -m)" >&2; exit 1 ;;
esac

ASSET="hdf_${HDF_LIBS_VERSION}_${OS}_${ARCH}.tar.gz"
RELEASE_URL="https://github.com/mitre/hdf-libs/releases/download/v${HDF_LIBS_VERSION}"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "${TMPDIR}"' EXIT

echo "→ downloading hdf-cli v${HDF_LIBS_VERSION} (${OS}/${ARCH})"
curl -fsSL "${RELEASE_URL}/${ASSET}"          -o "${TMPDIR}/${ASSET}"
curl -fsSL "${RELEASE_URL}/checksums.txt"     -o "${TMPDIR}/checksums.txt"

echo "→ verifying SHA-256 against release checksums.txt"
EXPECTED_SHA="$(awk -v f="${ASSET}" '$2 == f { print $1 }' "${TMPDIR}/checksums.txt")"
if [[ -z "${EXPECTED_SHA}" ]]; then
  echo "::error:: ${ASSET} not listed in checksums.txt — release asset missing" >&2
  exit 1
fi

if command -v sha256sum >/dev/null 2>&1; then
  ACTUAL_SHA="$(sha256sum "${TMPDIR}/${ASSET}" | awk '{ print $1 }')"
else
  ACTUAL_SHA="$(shasum -a 256 "${TMPDIR}/${ASSET}" | awk '{ print $1 }')"
fi

if [[ "${ACTUAL_SHA}" != "${EXPECTED_SHA}" ]]; then
  echo "::error:: SHA-256 mismatch for ${ASSET}" >&2
  echo "  expected: ${EXPECTED_SHA}" >&2
  echo "  actual:   ${ACTUAL_SHA}" >&2
  exit 1
fi

echo "→ extracting + installing to ${HDF_INSTALL_DIR}/hdf"
tar -xzf "${TMPDIR}/${ASSET}" -C "${TMPDIR}/"

# Tarball contents include the binary plus auxiliary docs; we only need the binary.
if [[ ! -f "${TMPDIR}/hdf" ]]; then
  echo "::error:: hdf binary not present in tarball" >&2
  exit 1
fi

# Use sudo only if the install dir isn't writable by the current user.
if [[ -w "${HDF_INSTALL_DIR}" ]] || [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  install -m 0755 "${TMPDIR}/hdf" "${HDF_INSTALL_DIR}/hdf"
else
  sudo install -m 0755 "${TMPDIR}/hdf" "${HDF_INSTALL_DIR}/hdf"
fi

echo "→ installed: ${HDF_INSTALL_DIR}/hdf"
"${HDF_INSTALL_DIR}/hdf" version || true

# Warn when the freshly-installed binary is NOT the one PATH resolves. A prior
# `go install github.com/mitre/hdf-libs/...` drops an hdf into $GOBIN
# (~/go/bin), which commonly precedes /usr/local/bin — so this script appears
# to succeed while `hdf` keeps resolving to the older build. The symptom is a
# confusing version-mismatch spec failure that looks unrelated to whatever you
# were working on, so fail loudly here instead.
RESOLVED="$(command -v hdf || true)"
if [[ -n "${RESOLVED}" && "${RESOLVED}" != "${HDF_INSTALL_DIR}/hdf" ]]; then
  echo ""
  echo "::warning:: PATH resolves 'hdf' to ${RESOLVED}, not the copy just installed."
  echo "  ${RESOLVED} reports: $("${RESOLVED}" version 2>/dev/null | head -1)"
  echo "  Most often a leftover 'go install' build in \$GOBIN shadowing this one."
  echo "  Fix by installing over the copy that wins:"
  echo "    HDF_LIBS_VERSION=${HDF_LIBS_VERSION} HDF_INSTALL_DIR=\"$(dirname "${RESOLVED}")\" script/dev/install-hdf.sh"
  echo "  Or remove the shadowing copy:  rm ${RESOLVED} && hash -r"
fi
