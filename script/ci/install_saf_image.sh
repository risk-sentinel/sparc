#!/usr/bin/env bash
# Put a `saf` command on PATH that runs the SAF CLI from its pinned image (#1362).
#
# Usage: script/ci/install_saf_image.sh <image@sha256:digest> <expected-version>
#   e.g. script/ci/install_saf_image.sh "$SAF_IMAGE" "$SAF_VERSION"
#
# WHY AN IMAGE, NOT npm: @mitre/saf 1.8.0 (2026-11-02, carrying security fixes)
# was released to GitHub and Docker Hub but never published to npm, whose
# newest version is 1.7.0. The GitHub release has no checksums file, so the
# Docker image pinned by DIGEST is the only 1.8.0 channel whose content we can
# pin. Integrity comes from the digest; the image carries no signature to check.
#
# Measured 2026-11-15 against the 11-05 main scan artifacts: cyclonedx_sbom2hdf,
# anchoregrype2hdf, supplement passthrough write and validate threshold give
# the same findings, statuses, impacts and threshold results as 1.6.0 on npm.
# The only difference is the converter library's own version stamp.
#
# The wrapper runs each call:
#   --network none     saf converts and validates local files; it needs no network
#   -u <runner uid>    output files belong to the runner, not the image's user
#   SHELL, HOME        oclif looks the user up in /etc/passwd without them and
#                      crashes (uv_os_get_passwd ENOENT) for an unknown uid
#   -v $PWD:$PWD       every saf call in these workflows uses workspace paths;
#                      a path outside the working directory is not visible
#
# NIST SP 800-53 Rev 5: SI-7 (software integrity: the tool is pinned by
# digest), SR-11 (component authenticity), SC-7 (no network for the tool).
set -euo pipefail

image=${1:?usage: install_saf_image.sh <image@sha256:digest> <expected-version>}
expected=${2:?usage: install_saf_image.sh <image@sha256:digest> <expected-version>}

if [[ ! $image =~ @sha256:[0-9a-f]{64}$ ]]; then
  echo "::error::$image is not pinned by digest" >&2
  exit 1
fi

docker pull --quiet "$image" >/dev/null

bin="${RUNNER_TEMP:?RUNNER_TEMP is not set}/saf-bin"
mkdir -p "$bin"
cat > "$bin/saf" <<EOF
#!/usr/bin/env bash
exec docker run --rm --network none -u "\$(id -u):\$(id -g)" -e SHELL=/bin/sh -e HOME=/tmp \\
  -v "\$PWD:\$PWD" -w "\$PWD" "$image" "\$@"
EOF
chmod 0755 "$bin/saf"

# Read the version back out of the tool rather than trusting the tag.
actual="$("$bin/saf" --version)"
case "$actual" in
  "@mitre/saf/$expected "*) echo "SAF CLI: $actual" ;;
  *) echo "::error::expected @mitre/saf/$expected from $image, got: $actual" >&2; exit 1 ;;
esac

if [ -n "${GITHUB_PATH:-}" ]; then
  echo "$bin" >> "$GITHUB_PATH"
fi
