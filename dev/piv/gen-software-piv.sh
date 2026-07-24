#!/bin/sh
# #790 — generate a test CA, an nginx server cert, and a "software PIV" client
# certificate shaped like a DoD CAC. No smart-card hardware needed: the proxy
# validates the cert and forwards the verified PEM, and SPARC only ever sees
# that PEM — so a cert+key pair is a faithful stand-in for a real card.
#
# POSIX sh (no bashisms) so a minimal init container can run it during
# `docker compose up`, making the PIV gateway a first-class part of the
# dev/smoke stack. Idempotent: it no-ops if certs already exist.
#
# The client cert carries every identity shape so one card exercises every
# SPARC_PIV_IDENTITY_SOURCE:
#   - Subject CN  DOE.JOHN.Q.1234567890   (edipi_cn → EDIPI 1234567890)
#   - SAN otherName UPN 1234567890@mil     (upn)
#   - SAN rfc822Name john.doe@mail.mil     (email / fallback)
#
# Usage:  dev/piv/gen-software-piv.sh <output-dir>
set -eu

OUT="${1:?usage: gen-software-piv.sh <output-dir>}"
UPN_OID="1.3.6.1.4.1.311.20.2.3"
EDIPI="1234567890"
mkdir -p "$OUT"

if [ -f "$OUT/client.crt" ] && [ -f "$OUT/ca.crt" ] && [ -f "$OUT/server.crt" ]; then
  echo "==> certs already present in $OUT — nothing to do"
  exit 0
fi

echo "==> test CA"
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$OUT/ca.key" -out "$OUT/ca.crt" \
  -subj "/CN=SPARC Test PIV CA" 2>/dev/null

echo "==> nginx server cert (CN=localhost, signed by the CA)"
printf 'subjectAltName=DNS:localhost' > "$OUT/server-ext.cnf"
openssl req -newkey rsa:2048 -nodes \
  -keyout "$OUT/server.key" -out "$OUT/server.csr" \
  -subj "/CN=localhost" 2>/dev/null
openssl x509 -req -in "$OUT/server.csr" -CA "$OUT/ca.crt" -CAkey "$OUT/ca.key" \
  -CAcreateserial -days 3650 -out "$OUT/server.crt" \
  -extfile "$OUT/server-ext.cnf" 2>/dev/null

echo "==> software-PIV client cert (DoD CN + UPN + email SAN)"
printf 'subjectAltName=email:john.doe@mail.mil,otherName:%s;UTF8:%s@mil' "$UPN_OID" "$EDIPI" > "$OUT/client-ext.cnf"
openssl req -newkey rsa:2048 -nodes \
  -keyout "$OUT/client.key" -out "$OUT/client.csr" \
  -subj "/CN=DOE.JOHN.Q.${EDIPI}" 2>/dev/null
openssl x509 -req -in "$OUT/client.csr" -CA "$OUT/ca.crt" -CAkey "$OUT/ca.key" \
  -CAcreateserial -days 3650 -out "$OUT/client.crt" \
  -extfile "$OUT/client-ext.cnf" 2>/dev/null

# Postgres/nginx run as non-root and refuse group/world-readable keys.
chmod 0644 "$OUT"/*.crt
chmod 0600 "$OUT"/*.key
rm -f "$OUT"/*.csr "$OUT"/*.srl "$OUT"/*-ext.cnf

echo "==> generated in $OUT:"
ls -1 "$OUT" | sed 's/^/    /'
echo "    (EDIPI in CN: ${EDIPI}; UPN: ${EDIPI}@mil; email: john.doe@mail.mil)"
