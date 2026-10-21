# SAR Objectives API

Record an assessor's determination of each NIST SP 800-53A **assessment
objective** in a SAR: whether `ac-1_obj.a-1` is satisfied, by whom, with what
notes.

Determinations used to be recordable only in the browser, so an assessment run
by a pipeline could not record results per objective. The API and the screen
now call the same service. An objective determined **failed** opens the
control's risk, linked to a finding on that objective, and the POA&M is built
from those risks. The risk closes once none of the control's objectives is
failing.

> SAR documents are managed through the [SAR Documents API](sar-documents.md),
> and risks through the [SAR Risks API](sar-risks.md).

## Base URL

```
https://sparc.example.com/api/v1/sar_documents/:sar_document_id/objectives
```

The parent document accepts its **slug or its id**.

## Authentication

All endpoints require a valid Bearer token.

```
Authorization: Bearer YOUR_API_TOKEN_HERE
```

## Authorization

| Action | Permission |
|--------|-----------|
| `index` | `sar.read` (or Instance Admin) |
| `update` | `sar.write` (or Instance Admin) |

Both are scoped to the SAR's authorization boundary.

---

## List objectives

```
GET /api/v1/sar_documents/:sar_document_id/objectives
```

| Parameter | Description |
|-----------|-------------|
| `control_id` | Only this control's objectives (`ac-1`, `ac-2.1`). |
| `page`, `items` | Pagination; default 200 per page. |

```json
{
  "data": [
    {
      "id": 4211,
      "uuid": "1f0c…",
      "control_id": "ac-1",
      "objective_id": "ac-1_obj.a-1",
      "label": "AC-01a.[01]",
      "prose": "an access control policy is developed and documented;",
      "parent_objective_id": "ac-1_obj.a",
      "determinable": true,
      "status": "pending",
      "assessor_name": null,
      "assessor_notes": null,
      "assessed_at": null
    }
  ],
  "meta": { "page": 1, "pages": 9, "count": 1795, "items": 200 }
}
```

`determinable` is false for a grouping node (`ac-1_obj`, `ac-1_obj.a`): it has
no statement of its own to determine.

## Record a determination

```
PATCH /api/v1/sar_documents/:sar_document_id/objectives/:id
```

`:id` is the OSCAL objective id (`ac-1_obj.a-1`) or the record id.

```json
{
  "sar_control_objective": {
    "status": "failed",
    "assessor_name": "J. Assessor",
    "assessor_notes": "No policy review in the last 365 days."
  }
}
```

| Field | Values |
|-------|--------|
| `status` | `pending`, `in-progress`, `passing`, `failed`, `not_applicable` |
| `assessor_name`, `assessor_notes` | free text |

`passing` and `failed` set `assessed_at`. A `failed` objective opens (or
reopens) the risk titled `Risk for <control>`. When no objective of the control
is still failing, that risk is closed. An unknown status returns `422`, and an
unknown field returns the strict-parameters error.

In the OSCAL export, a `passing` objective is a finding with state `satisfied`
and a `failed` one is `not-satisfied`. An objective still pending, or
`not_applicable`, is no finding at all: OSCAL has no "unknown" state.
