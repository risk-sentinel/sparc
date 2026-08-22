# POA&M Sub-Objects API

Items, observations, findings, local components, remediations and milestones —
the objects a POA&M is actually made of, and the ones OSCAL exports.

Added in [#1010](https://github.com/risk-sentinel/sparc/issues/1010).
[#832](https://github.com/risk-sentinel/sparc/issues/832) gave `poam_risks` an
API and left all six siblings behind, so a POA&M could be assembled through the
API only in part. Found by the missing-endpoint axis of
[#995](https://github.com/risk-sentinel/sparc/issues/995).

## Base URL

```
https://sparc.example.com/api/v1/poam_documents/:poam_document_id
```

The document may be addressed by **slug** or numeric id.

## Authorization

`poam.read` for reads, `poam.write` for writes, **scoped to the parent
document's authorization boundary**; instance admins bypass.

A document with **no** boundary requires an instance-level grant. That is the
fail-closed direction: an unassociated document must not be editable by anyone
who merely holds the permission on some other boundary.

## Endpoints

Five resources hang off the document, and milestones hang off a remediation.
All six support the same five actions.

| Resource | Path |
|---|---|
| Items | `…/poam_documents/:id/items` |
| Observations | `…/poam_documents/:id/observations` |
| Findings | `…/poam_documents/:id/findings` |
| Local components | `…/poam_documents/:id/local_components` |
| Remediations | `…/poam_documents/:id/remediations` |
| Milestones | `…/poam_documents/:id/remediations/:remediation_id/milestones` |

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/v1/poam_documents/:poam_document_id/items` | List (paginated) |
| `POST` | `/api/v1/poam_documents/:poam_document_id/items` | Create |
| `GET` | `/api/v1/poam_documents/:poam_document_id/items/:id` | Show, including the OSCAL arrays |
| `PATCH`/`PUT` | `/api/v1/poam_documents/:poam_document_id/items/:id` | Update |
| `DELETE` | `/api/v1/poam_documents/:poam_document_id/items/:id` | Delete |
| `GET` | `/api/v1/poam_documents/:poam_document_id/observations` | List (paginated) |
| `POST` | `/api/v1/poam_documents/:poam_document_id/observations` | Create |
| `GET` | `/api/v1/poam_documents/:poam_document_id/observations/:id` | Show, including the OSCAL arrays |
| `PATCH`/`PUT` | `/api/v1/poam_documents/:poam_document_id/observations/:id` | Update |
| `DELETE` | `/api/v1/poam_documents/:poam_document_id/observations/:id` | Delete |
| `GET` | `/api/v1/poam_documents/:poam_document_id/findings` | List (paginated) |
| `POST` | `/api/v1/poam_documents/:poam_document_id/findings` | Create |
| `GET` | `/api/v1/poam_documents/:poam_document_id/findings/:id` | Show, including the OSCAL arrays |
| `PATCH`/`PUT` | `/api/v1/poam_documents/:poam_document_id/findings/:id` | Update |
| `DELETE` | `/api/v1/poam_documents/:poam_document_id/findings/:id` | Delete |
| `GET` | `/api/v1/poam_documents/:poam_document_id/local_components` | List (paginated) |
| `POST` | `/api/v1/poam_documents/:poam_document_id/local_components` | Create |
| `GET` | `/api/v1/poam_documents/:poam_document_id/local_components/:id` | Show, including the OSCAL arrays |
| `PATCH`/`PUT` | `/api/v1/poam_documents/:poam_document_id/local_components/:id` | Update |
| `DELETE` | `/api/v1/poam_documents/:poam_document_id/local_components/:id` | Delete |
| `GET` | `/api/v1/poam_documents/:poam_document_id/remediations` | List (paginated) |
| `POST` | `/api/v1/poam_documents/:poam_document_id/remediations` | Create |
| `GET` | `/api/v1/poam_documents/:poam_document_id/remediations/:id` | Show, including the OSCAL arrays |
| `PATCH`/`PUT` | `/api/v1/poam_documents/:poam_document_id/remediations/:id` | Update |
| `DELETE` | `/api/v1/poam_documents/:poam_document_id/remediations/:id` | Delete |
| `GET` | `/api/v1/poam_documents/:poam_document_id/remediations/:remediation_id/milestones` | List a remediation's milestones |
| `POST` | `/api/v1/poam_documents/:poam_document_id/remediations/:remediation_id/milestones` | Create a milestone |
| `GET` | `/api/v1/poam_documents/:poam_document_id/remediations/:remediation_id/milestones/:id` | Show one |
| `PATCH`/`PUT` | `/api/v1/poam_documents/:poam_document_id/remediations/:remediation_id/milestones/:id` | Update |
| `DELETE` | `/api/v1/poam_documents/:poam_document_id/remediations/:remediation_id/milestones/:id` | Delete |

## Shared shape

Every sub-object carries some subset of the OSCAL arrays, and they take the
same form throughout:

| Field | Shape |
|---|---|
| `props_data` | `[{name, value, class, ns, uuid, remarks}]` |
| `links_data` | `[{href, rel, media_type, text}]` |
| `origins_data` | `[{actor_type, actor_uuid, role_id}]` |
| `methods_data` | array of strings (observations only) |

These are returned on the **detailed** view only — a list of thirty items would
otherwise be mostly markup.

`uuid` is assigned by the server and **refused** if you send one. An OSCAL
sub-object without a uuid is not exportable, so it is not left to the caller.

## Per-resource fields

**Items** — `title`, `description`, `risk_status`, `risk_level`, `likelihood`,
`impact`, `deadline`, `internal_notes`, `closure_evidence`, `remarks`,
`ssp_control_statement_id` (#393 — the SSP statement the item came from).

**Observations** — `title`, `description`, `remarks`, `collected`, `expires`,
`methods_data`.

**Findings** — `title`, `description`, `remarks`,
`implementation_statement_uuid`, and **`target_data`, which is required**. OSCAL
requires a finding to name what it is a finding *about*:

```json
{
  "poam_finding": {
    "title": "AC-2 not satisfied",
    "description": "Accounts are not reviewed",
    "target_data": {
      "type": "statement-id",
      "target-id": "ac-2_smt",
      "status": { "state": "not-satisfied" }
    }
  }
}
```

`target_data` keeps the OSCAL spelling, hyphens included, because it round-trips
to OSCAL unchanged.

**Local components** — `title`, `description`, `component_type`, `purpose`,
`remarks`, `status_state`, `status_remarks`.

**Remediations** — `title`, `description`, `lifecycle`, `remarks`, and
**`poam_risk_id`**. A remediation belongs to a *risk*, not to the document, but
it is routed under the document because that is the object a caller holds. The
risk is resolved **through the document**, so attaching a remediation to a risk
on someone else's POA&M returns `404` — impossible by construction rather than
by a check.

**Milestones** — `title`, `description`, `due_date`, `milestone_type`,
`remarks`. Resolved through the document's risks the same way, so a milestone
cannot be attached to a remediation on another POA&M.

## Status Codes

| Status | Description |
|---|---|
| `200 OK` | Read, update or delete succeeded |
| `201 Created` | Record created |
| `401 Unauthorized` | Missing or invalid Bearer token |
| `403 Forbidden` | Caller lacks `poam.read` / `poam.write` on the document's boundary |
| `404 Not Found` | No such document or record — including a record belonging to a different POA&M |
| `422 Unprocessable Entity` | Validation failed, or the body carried a field this endpoint does not accept |

## Audit

`poam_item_*`, `poam_observation_*`, `poam_finding_*`,
`poam_local_component_*`, `poam_remediation_*`, `poam_milestone_*` — each with
`_created`, `_updated` and `_deleted`.

## NIST 800-53 Controls

- **CA-5** Plan of Action and Milestones
- **AC-3** Access Enforcement · **AU-12** Audit Record Generation
