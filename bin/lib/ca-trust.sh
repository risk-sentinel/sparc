# shellcheck shell=bash
#
# Custom / private-CA trust for outbound TLS (#774), runtime mechanism.
#
# Folds operator-supplied CA certificates into a combined trust bundle and
# points OpenSSL at it via SSL_CERT_FILE. Runs as the NON-ROOT runtime user, so
# it never touches the root-owned system trust store (/etc/pki/ca-trust) — a
# runtime `update-ca-trust` would fail as UID 1000. Instead it APPENDS the
# custom CAs to the system bundle in a writable location, so the public CA set
# stays trusted alongside the private one.
#
# Every Ruby OpenSSL client honors SSL_CERT_FILE — Net::HTTP, RestClient, the
# AWS SDK, and the LDAP client's default trust store (#773) — so a single
# combined bundle covers all outbound TLS. NIST SC-8 / SC-12.
#
# Inputs (env):
#   SPARC_EXTRA_CA_CERTS  - path to a PEM file OR a directory of *.crt/*.pem/*.cer
#                           files. Defaults to /rails/certs when that directory
#                           exists and is non-empty.
#   SPARC_SYSTEM_CA_BUNDLE - system bundle to prepend (default /etc/pki/tls/cert.pem)
#   SPARC_CA_BUNDLE_OUT    - where to write the combined bundle
#                            (default /rails/tmp/ca-bundle.pem)
#
# Sourced by bin/docker-entrypoint; unit-tested by spec/scripts/ca_trust_spec.rb.

# List CA files under $1 (a file or a directory), newline-separated. Prints
# nothing (and returns 0) when the source is empty/missing.
sparc_collect_ca_files() {
    local src="$1"
    if [ -f "$src" ]; then
        printf '%s\n' "$src"
    elif [ -d "$src" ]; then
        find "$src" -type f \( -name '*.crt' -o -name '*.pem' -o -name '*.cer' \) 2>/dev/null | sort
    fi
    return 0
}

# Assemble the combined bundle and export SSL_CERT_FILE when custom CAs exist.
# A no-op (returns 0, leaves SSL_CERT_FILE untouched) when none are supplied, so
# it is always safe to call. Written to survive `set -euo pipefail`.
sparc_setup_ca_trust() {
    local src="${SPARC_EXTRA_CA_CERTS:-}"
    if [ -z "$src" ] && [ -d /rails/certs ]; then
        src=/rails/certs
    fi
    [ -n "$src" ] || return 0

    local files
    files="$(sparc_collect_ca_files "$src")"
    if [ -z "$files" ]; then
        echo "[ca-trust] no PEM/CRT files under ${src} — using system trust store only"
        return 0
    fi

    local sys_bundle="${SPARC_SYSTEM_CA_BUNDLE:-/etc/pki/tls/cert.pem}"
    local out="${SPARC_CA_BUNDLE_OUT:-/rails/tmp/ca-bundle.pem}"
    mkdir -p "$(dirname "$out")"

    # System CAs first, then custom — append, never replace.
    {
        if [ -f "$sys_bundle" ]; then
            cat "$sys_bundle"
            echo
        fi
        while IFS= read -r f; do
            [ -n "$f" ] || continue
            echo "# sparc custom CA: ${f}"
            cat "$f"
            echo
        done <<EOF
${files}
EOF
    } > "$out"

    export SSL_CERT_FILE="$out"

    local count
    count="$(printf '%s\n' "$files" | grep -c . || true)"
    echo "[ca-trust] trusting ${count} custom CA file(s) from ${src}; SSL_CERT_FILE=${out}"
    return 0
}
