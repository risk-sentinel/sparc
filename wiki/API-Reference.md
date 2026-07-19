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

The **HDF ↔ OSCAL bridge** adds three stateless endpoints — `oscal/sar_from_hdf`,
`oscal/poam_from_hdf`, and `hdf/amendments_from_oscal_poam` (see
[Core Functions §18](Core-Functions#18-hdf--oscal-translation-bridge)).

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
