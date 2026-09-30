# Delivery API contract — what integrators build against

The part of SPARC's `/api/v1` surface that other systems consume: sparc-horizon
(the delivery HUD), sparc-validate (the evidence pipeline), and anyone else pulling
authorization data. It answers #1154 part 3. Each endpoint's full reference is in
[`endpoints/`](endpoints/); this page is the contract in one place.

Measured against SPARC on the v1.17.0 line. If this page and an endpoint page
disagree, the endpoint page (and the running API) wins, and this page is wrong.

## Authentication

- **Bearer tokens only.** Every `/api/v1` request carries
  `Authorization: Bearer <token>`. A token acts as the user or service account it
  was minted for, with that principal's permissions. See [`authentication.md`](authentication.md).
- **Service accounts** are the non-interactive principals for pipelines. They get
  a token; they never hold a browser session.
- **No mTLS on the API today.** PIV/CAC mutual TLS is a *browser sign-in* method;
  the API does not use client certificates, and there is no client-certificate
  issuance path. Transport is TLS to the deployment's load balancer.
- **OIDC JWTs** are accepted in hybrid mode (`SPARC_API_AUTH=hybrid`), for humans
  signing in through the IdP.

## Documents you can pull

All document exports share one contract (#1181):

| Document | Endpoint | Read permission |
|---|---|---|
| SSP | `GET /api/v1/ssp_documents/:id/export` | `ssp.read` on its boundary |
| Assessment plan (SAP) | `GET /api/v1/sap_documents/:id/export` | `sap.read` on its boundary |
| Assessment results (SAR) | `GET /api/v1/sar_documents/:id/export` | `sar.read` on its boundary |
| POA&M | `GET /api/v1/poam_documents/:id/export` | `poam.read` on its boundary |
| Component definition | `GET /api/v1/cdef_documents/:id/export` | any authenticated caller (CDEFs are instance-scoped) |
| Control mapping | `GET /api/v1/control_mappings/:id/export` | any authenticated caller |
| HDF system document | `GET /api/v1/authorization_boundaries/:id/hdf_system` | `authorization_boundaries.read` **and** `ssp.read` on the boundary |

`:id` accepts the slug (and, where noted in the endpoint page, the numeric id or uuid).

**Format.** `format=fields` (the default: SPARC's control-field JSON, unchanged for
existing callers) | `oscal` | `oscal-yaml` | `oscal-xml`. Mappings offer `oscal`
(default) and `oscal-yaml` only — SPARC carries no OSCAL XSD for the mapping
model, so XML could be neither ordered nor validated, and is refused by name. The
HDF system document is JSON.

**Validation.** `validate=true` (default) returns only a schema-valid document;
a non-conforming one is refused with `422 {error, details, hint}`. `validate=false`
returns it anyway, so a caller can see what failed. An unknown format is
`422 {error, expected}`.

**Versions.** OSCAL documents are written at the document's own version, or
**1.2.3** (SPARC's default) when it has none. XML is validated against the XSDs of
the release the document declares; SPARC carries 1.1.2, 1.1.3, 1.2.2 and 1.2.3,
and a document declaring another release is validated against the nearest
carried one in its line (the result reports both).

## Caching — ETags

Every export above returns a **strong ETag** computed over the exported bytes
(plus format, validate and version). Send it back as `If-None-Match`; an
unchanged document answers **`304 Not Modified`** with an empty body. The tag
changes when anything in the document changes — including child records such as
an SSP control or a POA&M item, which do not move the parent's `updated_at`.

A 304 saves the transfer, not the work: SPARC still builds the document to
compare. One known exception: a SAR with no assessment end date writes the
current time into its export, so its bytes — and its ETag — change on every
request, and it is never answered 304.

## Identity — what to join on

- **Use `uuid`, not `id` or `slug`.** Every boundary, organization and document
  carries a durable RFC 4122 `uuid`. `id` is a database key (not stable across
  environments); `slug` and `name` change on rename.
- **SPARC's rows use version-4 UUIDs** (`gen_random_uuid()`), not version 5.
  Fixtures that show v5 UUIDs for organizations, boundaries or SSPs do not match
  what a live instance returns.
- **Organization → boundary tree.** Boundary rows (list and detail) carry
  `organization_id` and `organization_uuid` (#1178); both are `null` when a
  boundary has no organization. Leveraged authorizations carry
  `leveraging_boundary_uuid` and `leveraged_boundary_uuid` (`null` when the
  leveraged system is not a boundary in this instance).
- **SPARC-namespace props** (`https://sparc.risk-sentinel.org/ns`) on SSP, SAR and
  POA&M exports: `node-type` (SSP metadata: `system`; organization party:
  `organization`), `parent-uuid` (the SSP's boundary uuid), `fips-199`,
  `next-decision-date`, `blocks-ato`, `condition-expires`, `trigger`,
  `evidence-kind`, `signed-by`. Emitted only where SPARC holds the data; a
  validated export refuses a malformed one. Always under the registered URI,
  whatever `SPARC_OSCAL_NS` is set to.
- **Canonical control ids.** The catalog form is canonical (`ac-2.1`); the API
  emits canonical ids in catalog responses and accepts the other forms on input
  (#1162). Normalise to the catalog form.

## Mappings — the KSI and 800-53 crosswalks

Two families of mapping documents are published through
`GET /api/v1/control_mappings/:id/export`:

- **FedRAMP 20x KSI → NIST SP 800-53 Rev 5** — authored by FedRAMP (from each
  indicator's `controls[]` in FedRAMP's consolidated rules), method `human`,
  rationale `functional`; every entry `intersects`.
- **NIST SP 800-53 Rev 5 ↔ Rev 4** — method `automation`, rationale `syntactic`.

Each document carries its **provenance** (method, matching rationale, status,
description). There is **no confidence score**: SPARC has never recorded one, so
it does not invent one. Building one is tracked in #1196. List mappings with
`GET /api/v1/control_mappings`.

## Sending things back

- **Attestations:** `POST /api/v1/evidences/:evidence_id/attestations` (and
  `GET …/attestations/export` in the CMS schema). See
  [`endpoints/attestations.md`](endpoints/attestations.md).
- **KSI validations:** `…/authorization_boundaries/:id/ksi_validations` (CRUD) — see [`endpoints/ksi-validations.md`](endpoints/ksi-validations.md).
- **Risk decisions:** the authorizing official's decision on a risk —
  `blocks_ato`, `condition_expires`, `reopen_trigger` — is written with
  `PATCH /api/v1/poam_risks/:id` (and `blocks_ato` on `PATCH /api/v1/sar_risks/:id`).
- **Not yet:** there is no endpoint that accepts an OSCAL assessment-results
  document with observations carrying `expires`, nor a `saf attest` file, nor a
  first-class "AO decision" object. Those would be new API surface; raise them as
  their own issue rather than assuming them.

## Finding every endpoint

`GET /api/v1/available` lists the endpoints the calling token may use.
[`INVENTORY.md`](INVENTORY.md) lists all of them, with their docs, Postman request
and test coverage.
