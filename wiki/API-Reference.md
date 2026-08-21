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
attestations, the KSI catalog and validations, admin credentials, users, and
discovery. Common verbs include `convert`, `update_fields`, and `export`.

> **New: SSP components.** `/api/v1/ssp_documents/:slug/components` is full CRUD
> over the components of a system security plan. Components previously had **no
> API at all** — they could be created, edited and deleted only through the
> enrichment screen. The endpoints also carry the OSCAL validation pair: a
> `validation` component recording `validation_type`, `validation_reference` and
> a link to the authoritative record, joined to the product component it
> validates. Full details in
> [`docs/api/endpoints/ssp-components.md`](https://github.com/risk-sentinel/sparc/blob/main/docs/api/endpoints/ssp-components.md).

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
> assessment-results, verified against the production image. The `502` contract
> above still stands as the behaviour for any future converter regression: SPARC
> does not fill the gaps in — `reviewed-controls` is *what the assessment
> covered*, and synthesising it would produce a document that passes the schema
> and misstates the assessment.

> ### ⚠️ `poam_from_amendments` is unavailable on the bundled converter (v1.16.0)
>
> The same validation now applies to **every** translation path, not just
> `sar_from_hdf` — it had been guarding one of three. With it on,
> **`oscal/poam_from_amendments` returns `502` for valid HDF Amendments input**,
> because hdf-cli **3.5.1** emits a POA&M that fails the NIST OSCAL schema on **every
> OSCAL release from 1.1.1 through 1.2.2, including NIST's current one**
> schema on three counts:
>
> - `risks[]` is missing the required `statement`
> - `risks[].props[].value` is `""`, which OSCAL's non-empty string datatype rejects
> - `metadata.parties[].name` is `""`, the same violation
>
> **Do not build a pipeline on this endpoint until the converter is fixed
> upstream.** `sar_from_hdf` is unaffected — 3.5.1 fixed that path and not this one.
>
> This is not a change in what the converter produces; it is a change in whether
> SPARC hands it to you. Before v1.16.0 the endpoint returned `200` with the
> invalid document.
>
> Filed upstream as [mitre/hdf-libs#236](https://github.com/mitre/hdf-libs/issues/236).
> Targeting a newer OSCAL version does not help — 1.2.x rejects more, not fewer.
>
> Evidence, reproducer and raw output:
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
