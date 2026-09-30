# HDF System API

Export an authorization boundary as an HDF **`hdf-system`** document (schema
v3.7.0, the hdf-libs release SPARC pins). Added in #1179.

`hdf-system` is the document every other HDF v3 document points at through
`systemRef` — results, amendments, evidence packages. It states what the
boundary *is*: its identity, owner, FIPS 199 categorization, authorization
status, components and control designations. Those are authorization facts
SPARC holds, so SPARC writes the document and the evidence pipeline consumes it
(risk-sentinel/sparc-validate#441) rather than deriving one from whatever it
happened to scan.

Related surfaces:

- [HDF Amendment Triage](hdf-triage.md) — the amendments export carries this
  document's URL as `systemRef`
- [Authorization Boundaries](authorization-boundaries.md) — the source record

## Endpoints

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/v1/authorization_boundaries/:authorization_boundary_id/hdf_system` | The boundary as a validated hdf-system document |

`:authorization_boundary_id` accepts the boundary **uuid**, its numeric id, or
its slug. Other documents cite the uuid form, because a slug is regenerated when
the boundary is renamed and a reference must not move.

## Authentication & authorization

```
Authorization: Bearer YOUR_API_TOKEN_HERE
```

Requires **both** `authorization_boundaries.read` **and** `ssp.read` on the
boundary (instance admins bypass). Both, because the document carries the SSP's
implementation narrative as control-designation descriptions — boundary read
alone must not reach SSP content. Missing either returns `403`.

## GET — the document

```bash
curl -H "Authorization: Bearer $TOKEN" \
  https://sparc.example.com/api/v1/authorization_boundaries/8f7e1c94-0d3a-4b21-9c1e-2f4a6b8d0e13/hdf_system \
  > system.hdf.json
hdf validate --type system system.hdf.json
```

The body **is** the artefact — raw hdf-system JSON, not wrapped.

```json
{
  "name": "Portal Production",
  "systemId": "8f7e1c94-0d3a-4b21-9c1e-2f4a6b8d0e13",
  "identifier": "8f7e1c94-0d3a-4b21-9c1e-2f4a6b8d0e13",
  "identifierScheme": "urn:ietf:rfc:4122",
  "description": "Citizen-facing benefits portal",
  "boundaryDescription": "All resources in the production VPC",
  "owner": { "identifier": "system.owner@agency.gov", "type": "email" },
  "authorizationStatus": "authorized",
  "authorizationDate": "2025-06-15T00:00:00Z",
  "categorizationLevel": "moderate",
  "components": [
    {
      "type": "application",
      "name": "Amazon S3",
      "componentId": "11111111-2222-4333-8444-555555555555",
      "description": "Object storage"
    }
  ],
  "controlDesignations": [
    {
      "controlId": "AC-2 (1)",
      "designation": "hybrid",
      "description": "Automated account management is shared with the IdP."
    }
  ],
  "generator": { "name": "sparc", "version": "1.16.3" },
  "labels": { "system_id": "8f7e1c94-0d3a-4b21-9c1e-2f4a6b8d0e13" }
}
```

### Field mapping

| hdf-system field | Source in SPARC | When absent |
|---|---|---|
| `name` | boundary name | — (required) |
| `systemId`, `identifier` | boundary uuid | — |
| `identifierScheme` | `urn:ietf:rfc:4122` (the uuid is an RFC 4122 uuid) | — |
| `description` | boundary description | omitted |
| `boundaryDescription` | authorization boundary description | omitted |
| `owner` | the boundary's **system owner** on the roster (legacy membership, then admin-assigned role) → `{identifier: <email>, type: "email"}`; else the boundary's organization → `{identifier: <organization uuid>, type: "other"}` | omitted |
| `authorizationStatus` | boundary status: `authorized`→`authorized`, `deauthorized`→`revoked`, `draft`→`notYetRequested`, `active`→`pendingAuthorization` | — |
| `authorizationDate` | the boundary's recorded authorization date, **only** when it is ISO 8601; a date becomes midnight UTC | omitted — never guessed from free text |
| `categorizationLevel` | FIPS 199 high-water mark across C/I/A (`fips-199-high` → `high`) | omitted |
| `components` | the components of every CDEF linked to the boundary's environments (below) | **`422`** — the schema requires at least one |
| `controlDesignations` | the boundary SSP's control origination (below) | omitted |
| `dataFlows` | **not exported** — SPARC does not model interconnections | always omitted |
| `generator` | `{name: "sparc", version: <SPARC version>}` | — |
| `labels.system_id` | boundary uuid | — |

### Components

One HDF component per OSCAL defined-component of each linked CDEF. A CDEF
imported from OSCAL contributes its indexed components, keyed on their upstream
uuids; any other CDEF contributes its single document-level component, with the
same uuid the OSCAL CDEF export gives it. A CDEF linked to several environments
is listed once.

| OSCAL component type | HDF component type |
|---|---|
| `software` | `application` |
| `service` | `application` |
| `hardware` | `host` |
| blank | `application` (the OSCAL CDEF export writes a blank type as `software`) |
| `interconnection` | **excluded** — a connection between systems is an HDF data flow, which SPARC does not model |
| `policy`, `process-procedure`, `plan`, `guidance`, `standard`, `validation`, `physical` | **excluded** — not a technical asset evidence can be scoped to, and HDF has no type for it |
| any other value | **excluded** |

A component that carries its own automated check (an AWS Config Rule, modelled
as a `software` component) is an assessment procedure rather than an asset, and
is excluded too.

### Control designations

From the boundary's SSP, per control, from its `control_type` (origination):

| SSP `control_type` | `designation` |
|---|---|
| System Specific | `system-specific` |
| Hybrid — partially inherited | `hybrid` |
| Inherited from provider | `common` |
| Not Applicable, or none recorded | not exported |

`controlId` is the NIST publication form (`AC-2 (1)`). `description` is the
control's implementation statement, else its implementation summary. When the
control has neither, the designation is still exported — it is a recorded fact —
with a description that says so: *Designation recorded in the SPARC SSP as
"…". No implementation statement has been written for this control.*
`providedBy`, `inheritedBy` and `systemRef` are not exported: the SSP records a
control's origination, not which component or leveraged system provides it.

## Validation

Every document is validated before it is returned, and an invalid one is never
returned:

1. **In process**, against the vendored schema
   `lib/data/hdf/hdf-system.v3.7.0.schema.json` — byte-for-byte the bundled
   schema the hdf-libs v3.7.0 CLI embeds (provenance in the sidecar next to it).
2. **`hdf validate --type system`**, whenever the `hdf` binary is present (it is
   in the shipped image).

Both run because they are not equivalent. Measured on hdf-libs 3.7.0, the CLI
accepts an undefined top-level key and a malformed `identifierScheme` — it does
not enforce the schema's `unevaluatedProperties: false` or the uri-reference
format — while the in-process check enforces both.

## Caching

The response carries a **strong** `ETag`: the SHA-256 of the exact response
bytes. The export is deterministic — no generation timestamp, fixed ordering —
so equal bytes mean an equal document. Send it back as `If-None-Match` and an
unchanged document answers `304 Not Modified` with no body.

The tag is computed over the bytes rather than over `updated_at` timestamps
because the document reads records whose edits do not touch the boundary row:
the system-owner membership, the organization, the CDEFs' component index, the
SSP's control fields. A timestamp tag would answer `304` for a changed document.

## Audit

A `200` records `hdf_system_exported` against the boundary, with the number of
components, excluded components and control designations. A `304` exports
nothing and records nothing; neither does a refused request.

## Errors

| Status | When |
|---|---|
| `401` | No or invalid token |
| `403` | Missing `authorization_boundaries.read` or `ssp.read` on the boundary |
| `404` | No boundary with that uuid, id or slug |
| `422` | The boundary has no exportable component (the message names what was found and what to link), or the generated document failed validation (`details` lists the violations) |

```json
{
  "error": "Boundary cannot be exported as an hdf-system document",
  "details": "Authorization boundary \"Portal Production\" has no components. An hdf-system document must list at least one — link a component definition (CDEF) to one of the boundary's environments, then export again."
}
```
