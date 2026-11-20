# FedRAMP Evaluations API

FedRAMP's vulnerability rules (FRR.VER) ask a provider to evaluate every detected vulnerability and to report the evaluation (#1354, #1384). SPARC records one evaluation per vulnerability in a boundary, keyed by the finding's `control_id`. The `control_id` is the vulnerability's tracking identifier in FedRAMP reports, because it is the one key that stays the same across scans. Every scan writes new [scanner findings](hdf-triage.md), and the evaluation outlives them, as a [disposition](hdf-triage.md) does.

| Field | FedRAMP rule | Meaning |
|---|---|---|
| `internet_reachable` | VER-EVA-EIR | Providers MUST evaluate detected vulnerabilities, considering the context of the cloud service offering, to determine if they are internet-reachable vulnerabilities. |
| `likely_exploitable` | VER-EVA-ELX | Providers MUST evaluate detected vulnerabilities, considering the context of the cloud service offering, to determine if they are likely exploitable vulnerabilities. |
| `pain_rating` | VER-EVA-EPA | The Potential Agency Impact N-rating (PAIN), `0`–`5` (below) |
| `evaluated_at` | VER-RPT-VDT | Time of completed evaluation |
| `next_reduction_rating`, `next_reduction_at` | VER-RPT-VDT | Estimated time and target N-rating of the next reduction in N-rating |
| `supplementary_info` | VER-RPT-VDT | Any supplementary information the provider responsibly determines will help federal agencies assess or mitigate the risk |

The N-ratings, as VER-EVA-EPA defines them:

| Rating | Definition |
|---|---|
| N0 | Exploitation is extremely unlikely to have any adverse effects on agencies that use the cloud service offering. |
| N1 | Exploitation could be expected to have minimal customer effects on one or more agencies that use the cloud service offering. |
| N2 | Exploitation could be expected to have narrow customer effects on one or more agencies that use the cloud service offering. |
| N3 | Exploitation could be expected to have a disruptive customer effect on one agency that uses the cloud service offering. |
| N4 | Exploitation could be expected to have a debilitating customer effect on one agency that uses the cloud service offering OR a disruptive customer effect on more than one federal agency that uses the cloud service offering. |
| N5 | Exploitation could be expected to have a debilitating customer effect on more than one agency that uses the cloud service offering. |

Each change of N-rating is kept in `pain_history` with when it was made. A fall in rating is a PAIN reduction, listed in `pain_reductions`.

## Endpoints

| Method | Path | Description |
|---|---|---|
| GET | `/api/v1/authorization_boundaries/:authorization_boundary_id/fedramp_evaluations` | The boundary's evaluations, or (`?unevaluated=true`) the failing findings not yet evaluated |
| GET | `/api/v1/authorization_boundaries/:authorization_boundary_id/fedramp_evaluations/:control_id` | One vulnerability's evaluation |
| PUT | `/api/v1/authorization_boundaries/:authorization_boundary_id/fedramp_evaluations/:control_id` | Record the evaluation (create or update) |

The boundary may be named by id or slug.

**Control ids in the path.** A control id may contain dots (XCCDF rule ids such as `xccdf_org.example_rule_audit-enabled`) and slashes (package URLs such as `pkg:gem/rack@2.0.0`). Percent-encode the id: a slash must be sent as `%2F`, for example `.../fedramp_evaluations/pkg:gem%2Frack@2.0.0`.

## Authentication and authorization

A valid Bearer token. Permissions are checked against the boundary in the path (a grant on that boundary, or across the instance), or the caller is an instance administrator. They are the same as for the triage dispositions beside them.

| Action | Permission |
|---|---|
| list, show | `evidence.read` |
| record (PUT) | `evidence.write` |

## The evaluation object

```json
{
  "id": 7,
  "uuid": "6f0c…",
  "authorization_boundary_id": 12,
  "control_id": "CVE-2026-0001",
  "evaluated": true,
  "evaluated_at": "2026-11-20T15:00:00Z",
  "evaluated_by": { "id": 5, "name": "Pat Triager" },
  "internet_reachable": true,
  "likely_exploitable": false,
  "pain_rating": 2,
  "pain_label": "N2",
  "pain_history": [
    { "rating": 4, "at": "2026-11-18T10:00:00Z" },
    { "rating": 2, "at": "2026-11-20T15:00:00Z" }
  ],
  "pain_reductions": [ { "rating": 2, "at": "2026-11-20T15:00:00Z" } ],
  "next_reduction_at": "2026-12-15T00:00:00Z",
  "next_reduction_rating": 1,
  "supplementary_info": "The WAF rejects the triggering payload.",
  "detected_at": "2026-11-17T08:12:00Z",
  "current_finding": { "uuid": "…", "status": "failed", "severity": "HIGH", "title": "…", "scanner": "trivy" },
  "created_at": "2026-11-18T10:00:00Z",
  "updated_at": "2026-11-20T15:00:00Z"
}
```

`detected_at` is when the vulnerability was first detected: the earliest failing result for the control in the boundary. `current_finding` is the current scan's row, or `null` once no current scan reports the control.

## `GET .../fedramp_evaluations`

Paginated (`page`, `items`), ordered by `control_id`.

```json
{ "data": [ { "control_id": "CVE-2026-0001", "evaluated": true, "pain_rating": 2, "...": "..." } ],
  "meta": { "page": 1, "pages": 1, "count": 1, "items": 25 } }
```

With `?unevaluated=true` it lists instead the current scan's failing findings that have no evaluation yet, one per control, in the same shape with `evaluated: false`, `id: null` and every evaluation field `null`. This is the worklist of vulnerabilities still to evaluate.

## `GET .../fedramp_evaluations/:control_id`

`200` with the evaluation. A detected vulnerability (the boundary has a failing finding for it) that has not been evaluated yet answers `200` with `evaluated: false`. A control with neither is `404`.

## `PUT .../fedramp_evaluations/:control_id`

Records the evaluation. Only the fields sent change. Send them under `fedramp_evaluation` or as a flat JSON body:

```json
{
  "fedramp_evaluation": {
    "internet_reachable": true,
    "likely_exploitable": false,
    "pain_rating": 2,
    "evaluated_at": "2026-11-20T15:00:00Z",
    "next_reduction_rating": 1,
    "next_reduction_at": "2026-12-15",
    "supplementary_info": "The WAF rejects the triggering payload."
  }
}
```

| Field | Accepts |
|---|---|
| `internet_reachable`, `likely_exploitable` | `true` / `false`, or `null` (not yet evaluated) |
| `pain_rating`, `next_reduction_rating` | `0`–`5` (or `"N0"`–`"N5"`), or `null` |
| `evaluated_at` | ISO 8601 time. When omitted, the first evaluation records now. It cannot be cleared. |
| `next_reduction_at` | A date or ISO 8601 time, or `null` |
| `supplementary_info` | Text, at most 10,000 characters, or `null` |

`evaluated_by` is the caller. Each recorded evaluation is audited as `fedramp_evaluation_recorded`, with the fields that changed.

| Status | When |
|---|---|
| `201` | The first evaluation of this vulnerability was recorded |
| `200` | An existing evaluation was updated |
| `400` | The body is empty |
| `403` | The caller lacks `evidence.write` on the boundary |
| `404` | No such boundary |
| `422` | The boundary has no failing finding for the control (only a detected vulnerability is evaluated); a rating outside N0–N5; a next reduction that is not lower than the current N-rating; a value that is not a yes or no, a time, or a number; a field this endpoint does not accept |

```json
{ "error": "Next reduction rating must be lower than the current N-rating" }
```

## The boundary's FedRAMP package overview

FedRAMP's reports also name the address of the system's FedRAMP Certification Package Overview. It is the boundary's `fedramp_package_overview_uri`, set with [`PATCH /api/v1/authorization_boundaries/:id`](authorization-boundaries.md).

## Related

- The triage screen records the same evaluation: [HDF Amendment Triage](../../../wiki/User-Guide-HDF-Amendment-Triage.md#fedramp-evaluation).
- [HDF Amendment Triage API](hdf-triage.md): scanner findings and their dispositions.
