# API Reference

SPARC is **API-first** — every user-facing function is backed by a REST endpoint,
and the web UI is a client over that API. The API lives under the `Api::V1::`
namespace at `/api/v1/`.

## Canonical docs

The full, per-endpoint reference is maintained under
[`docs/api/`](https://github.com/risk-sentinel/sparc/tree/main/docs/api) in the
main repository:

| Doc | Purpose |
|-----|---------|
| [introduction.md](https://github.com/risk-sentinel/sparc/blob/main/docs/api/introduction.md) | Overview & getting started |
| [authentication.md](https://github.com/risk-sentinel/sparc/blob/main/docs/api/authentication.md) | Bearer-token auth & the session-cookie bridge |
| [INVENTORY.md](https://github.com/risk-sentinel/sparc/blob/main/docs/api/INVENTORY.md) | **Index of all endpoints** (links the per-resource docs in `api/endpoints/`) |
| [errors.md](https://github.com/risk-sentinel/sparc/blob/main/docs/api/errors.md) · [pagination.md](https://github.com/risk-sentinel/sparc/blob/main/docs/api/pagination.md) | Error format & pagination conventions |
| [README.md](https://github.com/risk-sentinel/sparc/blob/main/docs/api/README.md) | Postman collection + local/prod environments |

## Authentication

The API accepts:

- **Service-account tokens** — `Authorization: Bearer sparc_sa_<token>` (issued from
  the [Service Accounts](Screens#service-accounts--api-tokens) admin screen).
- **OIDC JWTs** — when `SPARC_API_AUTH` is set to `jwt` or `hybrid`.

`SPARC_API_AUTH` selects the mode (`token` / `jwt` / `hybrid`); see
[Configuration](Configuration). For UI test automation, `POST /api/v1/sessions/from_token`
exchanges a Bearer token for a Rails session cookie (v1.8.4).

## Resource coverage

Per-resource endpoints exist for SSP, SAR, SAP, POA&M, Profile, CDEF documents,
control catalogs, control mappings, authoritative sources, federation peers,
baseline parameters, back-matter resources, evidence and evidence control links,
attestations, the KSI catalog and validations, admin credentials, users,
federation identity, and discovery. Common verbs include `convert`,
`update_fields`, and `export`.

> **Changed: publishing through the API needs approval (v1.17.2).** Setting
> `lifecycle_status: "published"` is accepted for a catalog, profile or CDEF
> only once it is approved, or from a caller who may approve it (the type's
> `.approve` permission, `policy_manager`, or an instance administrator); an
> SSP, SAP, SAR or POA&M must pass the same publication checks as the
> **Publish** button. Anything else is `403` and audited. Full details in
> [`docs/api/publication.md`](https://github.com/risk-sentinel/sparc/blob/main/docs/api/publication.md).

> **Changed: discovery lists the whole API (v1.17.2).** `GET /api/v1/available`
> was a hand-kept list of 45 paths; it now lists every route the caller may
> use, from the same route table token limits are enforced against. A token
> limited to some resources sees only those, and each entry carries the
> resource `group` a token's `allowed_endpoints` names. The paths it listed
> before are still listed, spelled as before. Full details in
> [`docs/api/endpoints/discovery.md`](https://github.com/risk-sentinel/sparc/blob/main/docs/api/endpoints/discovery.md).

> **New: editing a token's limits (v1.17.2).**
> `PATCH /api/v1/users/:user_id/api_tokens/:id` changes a token's
> `allowed_endpoints` and `allowed_cidrs` in place, without reissuing it.
> Instance administrators only. Full details in
> [`docs/api/endpoints/api-tokens.md`](https://github.com/risk-sentinel/sparc/blob/main/docs/api/endpoints/api-tokens.md).

> **New: federation identity.** `GET /api/v1/federation/identity` publishes the
> two constants every peer derives object identity against — the namespace URI
> and the federation namespace UUID. Object UUIDs are UUIDv5 derived against
> that namespace, and peers deduplicate without coordinating only while every
> instance uses the same one; when two disagree nothing errors, the same
> logical object just arrives under a second identity. The UUID is **derived
> from the namespace URI** rather than randomly generated, so an integrator can
> recompute it rather than embed a copied literal, and the response publishes
> the recipe so it can be verified rather than trusted. Read-only,
> authenticated, not permission-gated. Full details in
> [`docs/api/endpoints/federation-identity.md`](https://github.com/risk-sentinel/sparc/blob/main/docs/api/endpoints/federation-identity.md).

> **New: SSP components.** `/api/v1/ssp_documents/:slug/components` is full CRUD
> over the components of a system security plan. Components previously had **no
> API at all** — they could be created, edited and deleted only through the
> enrichment screen. The endpoints also carry the OSCAL validation pair: a
> `validation` component recording `validation_type`, `validation_reference` and
> a link to the authoritative record, joined to the product component it
> validates. Full details in
> [`docs/api/endpoints/ssp-components.md`](https://github.com/risk-sentinel/sparc/blob/main/docs/api/endpoints/ssp-components.md).

> **New: SAR risks.** `/api/v1/sar_documents/:slug/risks` is full CRUD over the
> risks an assessment identified. SAR risks previously had **no API at all** —
> POA&M has eight sub-resource controllers and SAR had none, so a risk was
> reachable only through the enrich screen, which accepted `title`,
> `description` and `status` and nothing else. The endpoints carry the OSCAL
> rating (`impact`, `likelihood`, on the five-level `very-low` … `very-high`
> scale, exported as characterization facets), the required `statement`, and the
> collections a risk holds: `threat_ids`, `mitigating_factors`, `origins` and
> `risk_log`. `origins` and `risk_log` are **API-only** — they
> are attribution and append-only history rather than things to type into a
> form, and exist for an integrator migrating an existing risk register. Full
> details in
> [`docs/api/endpoints/sar-risks.md`](https://github.com/risk-sentinel/sparc/blob/main/docs/api/endpoints/sar-risks.md).

> **Breaking: `POST /api/v1/users` no longer takes a password (v1.15.4).**
> `password` and `password_confirmation` are no longer permitted attributes.
> SPARC generates the initial credential itself, returns it **once** as
> `temporary_password` in the creation response, and flags the account so the user
> must replace it at first sign-in.
>
> A supplied password is **ignored without raising an error** — unpermitted
> parameters do not fail the request. If your client provisions users with a
> chosen password, it will keep receiving `201` while that password has no effect,
> so update it to read `temporary_password` from the response instead.
>
> The field is present only when local login is enabled; on an SSO-only instance
> there is no local credential to issue and the key is omitted. Full details in
> [`docs/api/endpoints/users.md`](https://github.com/risk-sentinel/sparc/blob/main/docs/api/endpoints/users.md).

The **HDF ↔ OSCAL bridge** adds three stateless endpoints — `oscal/sar_from_hdf`,
`oscal/poam_from_hdf`, and `hdf/amendments_from_oscal_poam` (see
[Core Functions §18](Core-Functions#18-hdf--oscal-translation-bridge)).

**Check a document before you exchange it (v1.17.11, #1354).**
`POST /api/v1/document_validations` checks a FedRAMP package document, an OSCAL
document (JSON or XML), HDF (v2 or v3) or XCCDF 1.2 against the schema SPARC
pins for that format, and checks that every field the schema requires is filled
in. FedRAMP's own schemas accept an empty string for a required field; SPARC
does not. It stores nothing: a document SPARC could check gets `200` with
`valid` true or false, its errors (each with a JSON Pointer) and, for FedRAMP
documents, a warning for each optional field left empty. Details in
[`docs/api/endpoints/document-validations.md`](https://github.com/risk-sentinel/sparc/blob/main/docs/api/endpoints/document-validations.md).

**Exchange documents with other systems (v1.17.11, #1354).** SPARC pulls
FedRAMP, OSCAL, HDF and XCCDF documents from other systems, takes them by upload,
keeps every version, and serves its own documents back out.

| Endpoints | What they do | Permission |
|---|---|---|
| `/api/v1/exchange_connections` (CRUD), `…/:id/pull`, `…/:id/discover`, `…/:id/test_connection`, `…/:exchange_connection_id/document_sources` (CRUD) | Register a connection (its boundary, root trust-center address, credential and trust pins) and the documents it pulls; pull now; list the root's document links; fetch and validate each document without storing it | `connections.manage` across the instance |
| `/api/v1/exchange_connections/:id/push_receipts`, `…/:exchange_connection_id/certification_materials` (list, add) | A connection's pushes and their outcome; its Class A materials, each then reviewed on the boundary | `connections.manage` across the instance |
| `POST /api/v1/exchange_connections/:exchange_connection_id/document_sources/:id/push` | A provider's push of a changed document. **No token:** an Ed25519 signature checked against keys pinned on the connection ([how to sign](https://github.com/risk-sentinel/sparc/blob/main/docs/api/endpoints/exchange-connections.md#push)) | The signature |
| `/api/v1/authorization_boundaries/:id/received_documents` (list, upload), `…/:id`, `…/:id/file` | Every version the boundary received, its validation result and what changed since the version in effect; the exact bytes, with `X-Content-SHA256` | `evidence.read`; upload `exchange.upload` |
| `…/received_documents/:id/accept`, `…/respond`, `…/reject` | The reviewer's decision | `exchange.review` |
| `/api/v1/authorization_boundaries/:id/exchange_index` | The boundary's current documents (SPARC's exports and its accepted received versions), each with its download URL | `evidence.read` |

- **The connection's credential is write-only.** It is accepted as `credential`
  and never returned; responses say only `credential_set`.
- **A document that fails validation is stored**, with its errors, and answers
  `201` like any other upload. It can never be accepted. Bytes the stream already
  holds answer `200` with `status: "unchanged"`.
- **Every new version waits for a reviewer**, an improvement included: only a
  byte-identical re-delivery needs no person, and that is recorded as unchanged.
- **Separation of duties:** the person who uploaded a version cannot decide it
  (`403`); the instance administrator is exempt.
- Downloads and reads of the exchange index are audited, for FedRAMP's access
  logs.

Details in
[`exchange-connections.md`](https://github.com/risk-sentinel/sparc/blob/main/docs/api/endpoints/exchange-connections.md),
[`received-documents.md`](https://github.com/risk-sentinel/sparc/blob/main/docs/api/endpoints/received-documents.md)
and
[`exchange-index.md`](https://github.com/risk-sentinel/sparc/blob/main/docs/api/endpoints/exchange-index.md).

**FedRAMP vulnerability reports (v1.17.11, #1354, #1384, #1390).** A boundary's
Vulnerability Detail Report (FedRAMP rule VER-RPT-VDT) and Accepted Vulnerability
Info (VER-RPT-AVI) for a report period, and its Historical Vulnerability Activity
(VER-TFR-MRH), written from its findings, dispositions and FedRAMP evaluations.

| Endpoints | What they do | Permission |
|---|---|---|
| `/api/v1/authorization_boundaries/:id/fedramp/vulnerability_detail_report` | The Vulnerability Detail Report, `?from=&to=` (ISO 8601; default the 30 days ending now) | `evidence.read` |
| `/api/v1/authorization_boundaries/:id/fedramp/accepted_vulnerability_info` | The Accepted Vulnerability Info, same period parameters | `evidence.read` |
| `/api/v1/authorization_boundaries/:id/fedramp/historical_ver_activity` | The Historical Vulnerability Activity (VER-TFR-MRH): active and accepted vulnerabilities together; default the 12 months ending now | `evidence.read` |

- The body is the FedRAMP document itself, validated against FedRAMP's pinned
  schema and for completeness before it is returned.
- `422` when the boundary has no FedRAMP Certification Package Overview address,
  or the period cannot be read. `502` with the errors, never the document, if
  SPARC built a report that fails its own validation.
- Each download is audited.

Details in
[`fedramp-reports.md`](https://github.com/risk-sentinel/sparc/blob/main/docs/api/endpoints/fedramp-reports.md).

**Record the FedRAMP evaluation of each vulnerability (v1.17.11, #1354).**
FedRAMP asks a provider to evaluate every detected vulnerability (FRR.VER).
SPARC keeps one evaluation per vulnerability in a boundary, keyed by the
finding's control id, so it outlives each scan: internet-reachable
(VER-EVA-EIR), likely exploitable (VER-EVA-ELX), the Potential Agency Impact
N-rating N0–N5 (VER-EVA-EPA) with its history, when it was evaluated, the planned
next reduction and supplementary information (VER-RPT-VDT).

| Endpoints | What they do | Permission |
|---|---|---|
| `GET /api/v1/authorization_boundaries/:id/fedramp_evaluations` | The boundary's evaluations; `?unevaluated=true` lists the current failing findings not yet evaluated | `evidence.read` |
| `GET …/fedramp_evaluations/:control_id` | One vulnerability's evaluation | `evidence.read` |
| `PUT …/fedramp_evaluations/:control_id` | Record it: `201` the first time, `200` after; only the fields sent change | `evidence.write` |

- A control id with a slash (a package URL) is sent percent-encoded (`%2F`).
- `422` for a control the boundary has no failing finding for, an N-rating
  outside N0–N5, or a next reduction that is not lower than the current rating.
- The boundary's `fedramp_package_overview_uri` (the FedRAMP Certification
  Package Overview address FedRAMP's reports name) is set with
  `PATCH /api/v1/authorization_boundaries/:id`, `https://` only.

Details in
[`fedramp-evaluations.md`](https://github.com/risk-sentinel/sparc/blob/main/docs/api/endpoints/fedramp-evaluations.md).

> **An overdue POA&M risk no longer refuses `hdf/amendments_from_oscal_poam` (v1.17.2, #1208).**
> A risk past its `deadline` becomes an expired amendment, and `hdf amend apply`
> refuses any document holding one. So by default SPARC **leaves overdue
> amendments out** and returns a document that still applies, counting them in the
> `X-SPARC-Overdue-Amendments` response header. Add `?include_overdue=true` to
> receive them as well. Previously one overdue risk made the whole POA&M fail with
> `verification failed: 1 expired`. Details in
> [`docs/api/endpoints/translations.md`](https://github.com/risk-sentinel/sparc/blob/main/docs/api/endpoints/translations.md).

> **`sar_from_hdf` validates before it returns (v1.15.2).** SPARC checks the
> translated document against the NIST OSCAL schema and **will not return one
> that fails** — previously it returned the converter's output as-is, so a caller
> could receive a `200` carrying a document no OSCAL tool would accept.
>
> A non-conforming translation answers **`502 Bad Gateway`**, listing the schema
> violations. `502` rather than `422` is deliberate: your input is not the
> problem and there is nothing you can change about the submitted HDF — the
> fault is in the upstream converter.
>
> **Resolved in v1.16.0.** This endpoint previously returned `502` for real HDF
> input on hdf-cli 3.4.1, because the converter omitted OSCAL-required properties
> (`reviewed-controls`, `finding/description`, `characterization/origin`) —
> [mitre/hdf-libs#184](https://github.com/mitre/hdf-libs/issues/184). **hdf-cli
> 3.5.1 fixed it**, and the endpoint now returns `200` with schema-valid
> assessment-results, verified against the production image (re-verified on
> hdf-cli 3.7.0, 3.7.2, and again on 3.8.0, the current pin). The `502` contract
> above still stands as the behaviour for any future converter regression: SPARC
> does not fill the gaps in — `reviewed-controls` is *what the assessment
> covered*, and synthesising it would produce a document that passes the schema
> and misstates the assessment.

> ### `poam_from_amendments` — resolved on hdf-cli 3.7.0
>
> **This endpoint works.** It returns `200` with a schema-valid OSCAL POA&M.
>
> It previously returned `502` for valid HDF Amendments input, because hdf-cli
> **3.5.1** emitted a POA&M that failed the NIST OSCAL schema on every release
> from 1.1.1 through 1.2.2, on three counts:
>
> - `risks[]` missing the required `statement`
> - `risks[].props[].value` was `""`, which OSCAL's non-empty string datatype rejects
> - `metadata.parties[].name` was `""`, the same violation
>
> Filed as [mitre/hdf-libs#236](https://github.com/mitre/hdf-libs/issues/236),
> **closed upstream on 2026-09-08 and fixed in hdf-cli 3.7.0**; SPARC now
> pins 3.8.0. Re-measured on the same reproducer against both binaries: 3.5.1 produces
> 3 violations on OSCAL 1.1.2 and 7 on 1.2.2; 3.7.0 is valid on both.
>
> The `502` contract above still stands for any future converter regression —
> SPARC validates every OSCAL document it emits and will not hand back one that
> fails the schema. A regression is pinned by a test that runs the minimal
> reproducer, so it would surface as a failing build rather than as a returning
> `502`.
>
> Evidence and reproducer:
> [`docs/dev/hdf-libs-3.5.1-oscal-poam-upstream-report.md`](https://github.com/risk-sentinel/sparc/blob/main/docs/dev/hdf-libs-3.5.1-oscal-poam-upstream-report.md).

### Evidence (v1.12.2)

Evidence is fully manageable over the API — create a record, upload the artifact
file, and associate it with the controls it supports:

| Verb | Path |
|------|------|
| `GET` `POST` | `/api/v1/evidences` |
| `GET` `PATCH` `DELETE` | `/api/v1/evidences/:id` (id or slug) |
| `GET` `POST` | `/api/v1/evidences/:evidence_id/control_links` |
| `DELETE` | `/api/v1/evidences/:evidence_id/control_links/:id` |

Create accepts `multipart/form-data` (metadata plus the artifact) or JSON for
metadata-only evidence. `collected_at` / `collected_by` are **server-recorded**
and cannot be supplied by the client (NIST AU-10).

Because evidence is arbitrary artifact content — PDFs, images, logs, scanner
output — uploads are guarded by an **executable-signature deny-list** rather than
a MIME allowlist, plus the `SPARC_MAX_UPLOAD_MB` size cap. Executable payloads
are rejected with `422` before anything is stored.

A control link that carries both `document_type` and `document_id` is what puts
the evidence into a document's **OSCAL back-matter**, referenced by its durable
`/artifacts/:uuid` resolver URL. A link without a document scope is traceability
only and does not appear in exports.

Full detail:
[evidences.md](https://github.com/risk-sentinel/sparc/blob/main/docs/api/endpoints/evidences.md)
·
[evidence-control-links.md](https://github.com/risk-sentinel/sparc/blob/main/docs/api/endpoints/evidence-control-links.md)

## Pagination

Index endpoints accept `?items` / `?per_page`, clamped at
`MAX_PAGINATION_LIMIT = 200` (v1.7.2).
