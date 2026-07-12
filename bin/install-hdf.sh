#!/usr/bin/env bash
# Install the MITRE hdf-libs CLI (https://github.com/mitre/hdf-libs).
#
# Single source of truth for hdf-cli provisioning, used by:
#   - Dockerfile (bakes binary into the SPARC container)
#   - .github/workflows/security.yml (CI security_gate job)
#   - Local development (run `bin/install-hdf.sh` to provision the binary)
#
# Pinned version: HDF_LIBS_VERSION env var (default tracks current SPARC release).
# Install path:   $HDF_INSTALL_DIR (default /usr/local/bin) — caller may need sudo.
#
# Verifies SHA-256 of the downloaded tarball against checksums.txt from the
# same GitHub release before extracting. Refuses to install on mismatch.

set -euo pipefail

HDF_LIBS_VERSION="${HDF_LIBS_VERSION:-3.2.0}"
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
