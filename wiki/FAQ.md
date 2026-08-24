# FAQ & Troubleshooting

For deeper operational guidance see
[`docs/troubleshooting.md`](https://github.com/risk-sentinel/sparc/blob/main/docs/troubleshooting.md).

## General

**What is SPARC?**
A Rails 8.1 application for managing NIST SP 800-53 compliance documentation —
SSPs, SARs, SAPs, POA&Ms, CDEFs, and control catalogs — with a REST API and
OSCAL import/export. SPARC is a **translation engine + UI** for OSCAL /
policy-as-code, not a system of record: tenant systems own the source of truth.

**Which OSCAL version does SPARC target?**
NIST OSCAL **v1.2.2** as of v1.16.0 — that is the version written into
`metadata.oscal-version` and the one JSON exports are validated against.
SPARC can validate against **1.1.1, 1.1.2, 1.1.3, 1.2.0, 1.2.1 and 1.2.2**, and a
document that carries its own `oscal-version` is validated against that instead
of the default.

Every schema is baked into the container, so validation works air-gapped with no
dependency on NIST GitHub at runtime.

Two caveats worth knowing:

- **XML exports are still validated against the 1.2.1 XSDs.** The JSON schema set
  moved to 1.2.2 and the XSD set has not yet followed, so an XML export declares
  1.2.2 while being checked against 1.2.1. The two releases are near-identical,
  but it is a mismatch rather than a deliberate choice.
- **1.2.0 is skipped on purpose.** That release omits the `associated-risk`
  definition, so `related-risks[].risk-uuid` is rejected by a schema defect
  rather than by anything wrong with the document. 1.2.1 restores it.

## Authentication

**I can't log in — there's no login form.**
All auth modes default to **disabled**. Enable at least one, e.g.
`SPARC_ENABLE_LOCAL_LOGIN=true`, then bootstrap an admin with
`bin/rails sparc:bootstrap_admin`. See [Configuration](Configuration#authentication).

**The OIDC/Okta or LDAP tab does nothing when clicked.**
This was a CSP regression fixed in **v1.8.1**. Ensure you're on ≥ v1.8.1.

**SSO buttons do nothing in Chrome/Edge but work in Firefox.**
Fixed in **v1.8.5** — Chromium enforces CSP `form-action` on every redirect hop.
Upgrade to ≥ v1.8.5.

**Deploy fails on a "Email has already been taken" / case-variant email.**
v1.8.5 added a DB-enforced `LOWER(email)` unique index. Resolve pre-existing
case-variant duplicate emails before deploying.

## Deployment & data

**A deploy "hangs" or the container restarts during a long migration.**
Long data migrations now use the deferred pattern (v1.8.3): the container binds
its port immediately and the migration body runs post-boot via Solid Queue.
Check **Admin → Data Migrations** for status.

**I edited `db/seeds/*.rb` but production didn't pick up the change.**
Bump the section version in `SeedRunner::CURRENT_VERSIONS` — `SeedRunner.run_section`
skips a section whose version already matches (the v1.6.6 converters incident).

**A new AWS converter / CDEF didn't appear after deploy.**
Same cause as above — confirm the relevant `SeedRunner` version was bumped, and
for AWS Labs CDEFs that `SPARC_AWS_LABS_CDEF_ENABLED=true`.

## OSCAL & validation

**My OSCAL export was rejected.**
Exports are validated against the NIST schemas before download (1.2.2 by default). CDEF
mutations are validated **pre-commit** (v1.8.0) — an invalid result is rejected
rather than persisted. Check the error detail for the failing JSON pointer.

## Still stuck?

- [docs/troubleshooting.md](https://github.com/risk-sentinel/sparc/blob/main/docs/troubleshooting.md)
- [Open an issue](https://github.com/risk-sentinel/sparc/issues)
- [Configuration reference](Configuration)
