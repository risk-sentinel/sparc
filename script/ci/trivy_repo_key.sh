#!/usr/bin/env bash
# Install the Trivy apt repository's signing key, only if it is the key Aqua
# announced.
#
#   script/ci/trivy_repo_key.sh
#
# The key is fetched from the repository it signs, so fetching alone proves
# nothing about it. Aqua rotated it after its March 2026 incident and published
# the new fingerprint (aquasecurity/trivy discussion #10549, 2026-04-17); the
# key served must match it, or the job fails instead of trusting it. A rotation
# means re-checking the announcement and changing EXPECTED here.
#
#   NIST SR-3, SR-11, SI-7
set -euo pipefail

EXPECTED=825AD9036F7C850E6A6FED4935B8ACA44FD9CA9F
key=$(mktemp)
trap 'rm -f "$key"' EXIT

# The URL serves the key directly; a redirect is refused, not followed.
wget -q --max-redirect=0 -O "$key" https://aquasecurity.github.io/trivy-repo/deb/public.key
fpr=$(gpg --show-keys --with-colons "$key" | awk -F: '/^fpr:/ {print $10; exit}')
if [[ "$fpr" != "$EXPECTED" ]]; then
  echo "::error::Trivy repo key fingerprint is ${fpr:-unreadable}, not the announced $EXPECTED" >&2
  exit 1
fi
gpg --dearmor < "$key" | sudo tee /usr/share/keyrings/trivy.gpg > /dev/null
