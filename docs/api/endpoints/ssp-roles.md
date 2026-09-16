# SSP Roles

The roles a System Security Plan **declares** — the entries that land in OSCAL
`metadata.roles`, and the only ids a `role-id` anywhere in the document is
allowed to reference.

Nested under an SSP: roles belong to exactly one plan, and the authorization
question is always about that plan.

## Why this endpoint exists

A `role-id` is an NCName token that must resolve to a role declared in
`metadata.roles`. It is **not** a UUID — UUIDs enter through `party-uuids`,
which reference `metadata.parties`.

Before this endpoint an SSP declared exactly three roles, hardcoded in the
exporter, and the statement editor accepted responsible roles as **free text**.
An author could type `isso` and produce a document whose reference resolved to
nothing. That is a **referential** break, not a schema one: the document
validates cleanly, and a consuming tool resolving the reference finds nothing —
so `OscalSchemaValidationService` cannot see it. Three hardcoded roles is also
not enough for a real plan; ISSO, ISSM, Control Provider and System
Administrator are all ordinary.

| | |
|---|---|
| **Base path** | `/api/v1/ssp_documents/:ssp_document_id/roles` |
| **Auth** | Bearer token |
| **Read** | `ssp.read` on the SSP's authorization boundary |
| **Write** | `ssp.write` on the SSP's authorization boundary |

`:ssp_document_id` is the SSP's slug. `:id` is the **OSCAL role-id**, not a
database key — roles are a JSON structure inside the document's metadata, and
there is no roles table.

## Endpoints

| Method | Path | Description |
|---|---|---|
| `GET` | `.../roles` | Declared roles, the boundary vocabulary, and NIST ids not yet declared |
| `POST` | `.../roles` | Declare a role — by `membership_role` (normal) or by `id` |
| `PATCH` / `PUT` | `.../roles/:id` | Retitle a declared role |
| `DELETE` | `.../roles/:id` | Undeclare a role |

## Declaring from the boundary (the normal path)

Pass `membership_role` instead of an id. The role comes from the
**authorization-boundary membership** vocabulary — the built-ins plus whatever
`SPARC_AUTH_BOUNDARY_ROLES` adds — which is where the system's personnel
actually sit. Nobody types an identifier.

Each membership role resolves in exactly one way:

* **NIST names it** → declared with NIST's id. `isso` becomes
  `information-system-security-officer`; `system_owner` becomes `system-owner`.
* **NIST does not** → declared **organization-defined** (the prop shown below),
  under the hyphenated form of the value: `ciso` becomes `ciso`.

`GET .../roles` lists the vocabulary under `meta.membership_roles`, each entry
showing what it would resolve to, so a client can offer it by label:

| Field | Meaning |
|---|---|
| `membership_role` | The value to send back as `membership_role` |
| `label` | Display label (an operator label from `SPARC_AUTH_BOUNDARY_ROLES` wins) |
| `role_id` | The OSCAL `role-id` it declares |
| `organization_defined` | `true` when NIST names no equivalent |
| `declared` | Already declared on this document |

Only **responsibility-bearing** roles are offered or accepted. `view_only` and
`project_member` name a level of access, not a function anyone is responsible
for, so posting one is refused with `422`.

Importing boundary members as system users (`POST /ssp_documents/:id/import_boundary_users`)
resolves roles the same way and declares every role it references. A system
user's `role-ids` describes the user rather than claiming responsibility, so the
import resolves access-only members too.

## Two tiers of role, both legal

NIST constrains `responsible-role/@role-id` with `allow-other="yes"` at every
site in the SSP model. Custom roles are **anticipated**, not merely tolerated —
so this is not an allow-list, and an unknown id is never rejected for being
unknown. The one hard rule is that a referenced id must **resolve**.

**NIST-suggested.** `GET .../roles` returns, under `meta.suggested`, the ids
NIST suggests that this document has not declared yet. They are read from the
conformance dataset for the document's own OSCAL version, so they track the
version rather than a copied list. Prefer them: an author typing `isso` mints a
private id for a role NIST already defines as
`information-system-security-officer`, and a reader resolving the NIST id knows
what it means.

**Deployment-defined.** Pass `organization_defined: true` to declare a role this
deployment owns — "Policy Department", say. The role is marked with a prop under
the deployment's namespace (`SPARC_OSCAL_NS`):

```json
{ "id": "policy-department",
  "title": "Policy Department",
  "props": [ { "name": "role-source",
               "ns": "https://sparc.risk-sentinel.org/ns",
               "value": "organization-defined" } ] }
```

The namespace goes on a **prop of the role**, never on the id: a `role-id` is a
plain token and cannot carry one. Posting a URI as an id is refused for exactly
that reason.

## Examples

Declare from the boundary vocabulary:

```bash
curl -X POST "$SPARC/api/v1/ssp_documents/acme-prod/roles" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"role": {"membership_role": "ciso"}}'
```

Declare a NIST role by id:

```bash
curl -X POST "$SPARC/api/v1/ssp_documents/acme-prod/roles" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"role": {"id": "incident-response"}}'
```

Declare one of your own:

```bash
curl -X POST "$SPARC/api/v1/ssp_documents/acme-prod/roles" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"role": {"id": "policy-department",
                "title": "Policy Department",
                "organization_defined": true}}'
```

`title` is optional — it defaults to a humanised form of the id.

## Responses

Each role serialises as:

| Field | Meaning |
|---|---|
| `id` | The OSCAL `role-id` |
| `title` | Display name |
| `organization_defined` | Marked as this deployment's own |
| `nist_suggested` | Present in NIST's suggested vocabulary |

## Errors

| Status | When |
|---|---|
| `403` | No `ssp.read` / `ssp.write` on the SSP's boundary |
| `404` | The role is not declared on this document |
| `409` | `DELETE` on a role that statements still reference |
| `422` | Missing id, an id that is not an NCName token, or a duplicate; a `membership_role` outside the responsibility-bearing vocabulary; `id` and `membership_role` sent together |

The `409` is deliberate: undeclaring a role that statements still point at would
manufacture the dangling reference this endpoint exists to prevent. Reassign the
statements first.

## Defaults

A plan that has declared nothing still **declares** the defaults its export
emits — `prepared-by`, `system-owner`, `authorizing-official` and
`information-system-security-officer`. The first write materialises them, so
what you see listed is what the document exports. Removing the last role leaves
**none** declared; it does not resurrect the defaults.

## See also

- [SSP Control Statements](ssp-control-statements.md) — where `role-id` is referenced
- [SSP Documents](ssp-documents.md)
