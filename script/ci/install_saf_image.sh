#!/usr/bin/env bash
# Put a `saf` command on PATH that runs the SAF CLI from MITRE's release image,
# pinned by digest (#1362, #1368).
#
#   script/ci/install_saf_image.sh <bindir> <image@sha256:digest>
#
# SAF 1.8.0 needs Node >= 24.22.1 and reached npm on 2026-11-17, inside the
# seven-day soak npm_install_soaked.sh enforces. MITRE's 1.8.0 image carries
# the same 522 package files as the npm release (compared byte for byte on
# 2026-11-18) and its own Node, so nothing is installed from npm and the
# runner needs no Node (owner, 2026-11-18). The image is not signed: the
# digest pin is the integrity control.
#
# Each call runs with no network, as the caller's uid and gid, and sees only
# the workspace ($GITHUB_WORKSPACE, else the working directory), mounted at
# its own path so relative and absolute paths inside it both resolve.
#
#   NIST SR-3, SR-11, SI-7
set -euo pipefail

bindir=${1:?usage: install_saf_image.sh <bindir> <image@sha256:digest>}
image=${2:?usage: install_saf_image.sh <bindir> <image@sha256:digest>}

if [[ ! $image =~ ^[a-z0-9./_-]+@sha256:[0-9a-f]{64}$ ]]; then
  echo "::error::$image is not pinned by digest" >&2
  exit 1
fi

docker pull --quiet "$image" > /dev/null
mkdir -p "$bindir"
cat > "$bindir/saf" <<EOF
#!/usr/bin/env bash
set -euo pipefail
root=\${GITHUB_WORKSPACE:-\$PWD}
case "\$PWD/" in
  "\$root"/*) ;;
  *) echo "saf: run from inside \$root, the only directory the container sees" >&2; exit 2 ;;
esac
exec docker run --rm --network none --user "\$(id -u):\$(id -g)" -e HOME=/tmp -e SHELL=/bin/sh \\
  -v "\$root:\$root" -w "\$PWD" "$image" "\$@"
EOF
chmod +x "$bindir/saf"
"$bindir/saf" --version
