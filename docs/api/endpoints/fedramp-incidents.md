# FedRAMP Incidents API

A boundary's FedRAMP incidents (#1390). A provider evaluates each incident promptly for whether it is a FedRAMP Reportable Incident, one that affects or is likely to affect the confidentiality or integrity of federal customer data (IEC-CSO-EFR), and reports one in an Initial, Ongoing and Final Incident Report (IEC-CSO-IIR, IEC-CSO-OIR, IEC-CSO-FIR). SPARC keeps one record per incident, works out when each report is due, writes each report, and keeps each report sent with the document as it was sent.

When each report is due, and whether FedRAMP says MUST or SHOULD, depends on the boundary's certification class and the incident's Potential Agency Impact N-rating, as the vendored FedRAMP Consolidated Rules set them. Until the incident is rated it is treated as N5 (IEC-CSO-DPR).

| Report | Counted from |
|---|---|
| Initial | The completed FedRAMP Reportable Incident evaluation (`evaluation_completed_at`) |
| Ongoing | The last report sent, once an Initial report has been, until the incident is resolved |
| Final | The resolution (`resolved_at`) |

Business days are federal business days (weekends and US federal holidays excluded); hours are clock hours.

Incidents are sensitive and have permissions of their own. FedRAMP must be turned on for the boundary (`fedramp_enabled`); otherwise every endpoint answers `422`.

## Endpoints

| Method | Path | Description |
|---|---|---|
| GET | `/api/v1/authorization_boundaries/:id/fedramp_incidents` | Every incident, newest first, each with its deadlines |
| POST | `/api/v1/authorization_boundaries/:id/fedramp_incidents` | Record an incident (`201`) |
| GET | `/api/v1/authorization_boundaries/:id/fedramp_incidents/:incident_id` | One incident |
| PUT | `/api/v1/authorization_boundaries/:id/fedramp_incidents/:incident_id` | Update it. Only the fields sent change |
| GET | `/api/v1/authorization_boundaries/:id/fedramp_incidents/:incident_id/report?type=Initial` | Its Incident Report of that type (`Initial`, `Ongoing`, `Final`), validated against FedRAMP's pinned schema |
| POST | `/api/v1/authorization_boundaries/:id/fedramp_incidents/:incident_id/reports` | Record a report sent (`201`), keeping the report as it stood |

The boundary may be named by id, slug or UUID; `:incident_id` is the incident's `uuid`. An incident is never deleted.

## Authentication and authorization

A valid Bearer token whose user holds **`incident.read`** on the boundary to read, **`incident.write`** to record, or an instance administrator. `evidence.read` and `evidence.write` do not give access. The audit log records `fedramp_incident_recorded`, `fedramp_incident_report_recorded` and `fedramp_incident_report_exported`.

## Request body (POST, PUT)

```json
{
  "fedramp_incident": {
    "tracking_id": "INC-2026-0042",
    "reportable": true,
    "coordinator": "Incident desk, ir@provider.example, 202-555-0100",
    "description": "Credential stuffing against the customer portal",
    "started_at": "2026-11-20T08:40:00Z",
    "detected_at": "2026-11-20T09:00:00Z",
    "detection_source": "WAF alert",
    "evaluation_completed_at": "2026-11-20T10:00:00Z",
    "milestones": [ { "occurred_at": "2026-11-20T09:30:00Z", "description": "Contained" } ],
    "current_rating": 3,
    "evaluation_notes": "Two agency tenants affected",
    "functional_impact": "Integrity of account settings for affected tenants",
    "recovery_plan": "Reset credentials; complete by 2026-11-22",
    "affected_agencies": [ "Example Agency" ],
    "observed_activity": "…",
    "indicators": [ "203.0.113.7" ],
    "related_cve_ids": [ "CVE-2026-1234" ],
    "root_cause": "…",
    "response_activities": "…",
    "resolved_at": null,
    "lessons_learned": [ "Rate-limit the login endpoint" ]
  }
}
```

`tracking_id` is required and unique on the boundary; it is the same on every report. `current_rating` (0–5) adds an N-rating to the incident's history (`ratings`) when it differs from the current one; the report gives the earlier ratings as `historicalRating`. `related_cve_ids` must be CVE identifiers. `lessons_learned` feeds the Ongoing Certification Report.

### Recording a report sent

```json
{ "report": { "report_type": "Initial", "sent_at": "2026-11-20T10:40:00Z" } }
```

`sent_at` may not be in the future. A report keeps the document exactly as it stood and its SHA-256.

## Response

Each incident carries `current_rating`, `reports` (without their documents), `deadlines_unavailable` (why there are none: not reportable, or no certification class) and `deadlines`:

```json
{ "report_type": "Initial", "rule_id": "IEC-CSO-IIR", "due_at": "2026-11-20T16:00:00Z",
  "timeframe": [ "hours", 6 ], "force": "MUST", "status": "due" }
```

A deadline's `status` is `sent`, `late`, `overdue`, `due`, `waiting`, `not_needed` (an Ongoing report once resolved) or `untimed` (FedRAMP sets no timeframe for the rating, N0).

## Errors

| Status | When |
|---|---|
| `403` | No `incident.read` (or `incident.write` to record) on the boundary |
| `404` | No such incident on this boundary |
| `422` | FedRAMP is off for the boundary; a value the record does not allow; an unknown field; a report of an incident that is not reportable; a Final report before resolution; the boundary has no Certification Package Overview address, which every report names |
| `502` | SPARC wrote a report that does not validate (never returned) |

Incident reports are not listed in the [exchange index](exchange-index.md): they go to the affected parties.
