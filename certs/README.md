# Custom / private-CA trust (#774)

This directory is the injection point for **custom or private Certificate
Authorities** that SPARC's container must trust for **outbound** TLS — LDAPS to
an internal directory, an OIDC provider fronted by a private CA, a corporate
TLS-intercepting proxy, or a DoD-PKI-signed endpoint.

By default it is **empty** (only this README and `.gitkeep`). **Do not commit
real CA certificates here** — this is a public repository; add them at build or
run time in your own environment.

There are two ways to add a CA; pick whichever fits your deployment.

## 1. Build-time bake-in (permanent, rebuild required)

Drop PEM/CRT files into this directory before building the image:

```sh
cp my-internal-root-ca.crt certs/
docker build -t sparc:custom .
```

The Dockerfile copies them into the system trust store
(`/etc/pki/ca-trust/source/anchors/`) and runs `update-ca-trust`, so the CA is
folded into the OS bundle. **Every** outbound TLS client trusts it: Ruby
OpenSSL / Net::HTTP, RestClient, the AWS SDK, and the LDAP client's default
trust store (see #773). Best for locked-down / air-gapped image builds.

## 2. Runtime mount (no rebuild)

Mount a CA file or a directory of PEMs into a running container and point
`SPARC_EXTRA_CA_CERTS` at it (or use the conventional mount path `/rails/certs`):

```yaml
# docker-compose.yml
services:
  web:
    environment:
      SPARC_EXTRA_CA_CERTS: /rails/certs
    volumes:
      - ./certs:/rails/certs:ro
```

At startup the entrypoint (`bin/lib/ca-trust.sh`) **appends** the mounted CAs to
the system bundle into a writable combined bundle and exports `SSL_CERT_FILE`.
This runs as the non-root runtime user, so it never modifies the root-owned
system trust store — and it **appends**, so the public CA set stays trusted.

Accepted file extensions: `.crt`, `.pem`, `.cer` (PEM-encoded).

NIST SP 800-53: **SC-8** (transmission confidentiality/integrity), **SC-12**
(cryptographic key establishment — trust anchors).
