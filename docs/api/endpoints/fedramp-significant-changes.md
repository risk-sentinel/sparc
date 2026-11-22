# FedRAMP Significant Changes API

A boundary's FedRAMP significant changes (#1390). FedRAMP requires a provider to evaluate every potential significant change, decide its type, and keep an auditable record of that evaluation (SCN-CSO-EVA, SCN-CSO-MAR). SPARC keeps one record per change evaluated, works out which Significant Change Notifications it needs and when each is due, writes the notification (SCN-CSO-INF), and keeps each notice sent with the document as it was sent (SCN-CSO-HIS).

| Type | Notices |
|---|---|
| `Routine` | None. A routine recurring change is recorded as evaluated and is never notified (SCN-RTR-NNR) |
| `Adaptive` | After finishing: within 10 business days of the finish (SCN-ADP-NTF) |
| `Transformative` | Initial plans: at least 30 business days before the start (SCN-TRF-NIP). Final plans: at least 10 before the start (SCN-TRF-NFP). After finishing: within 5 of the finish (SCN-TRF-NAF). After verification: within 5 of the verification, assessment or validation (SCN-TRF-NAV). Updated service documentation published: within 30 of the finish (SCN-TRF-UPD) |

Business days are federal business days: Monday to Friday, less the US federal holidays (5 U.S.C. 6103), each on the day it is observed. The counts are read from the vendored FedRAMP Consolidated Rules. The start is the actual start (`started_on`) once recorded, else the planned start. A change made during an emergency or incident (`emergency: true`, SCN-CSO-EMG) gives its before-start notices afterwards, by the after-finishing deadline.

FedRAMP must be turned on for the boundary (`fedramp_enabled`); otherwise every endpoint answers `422`.

## Endpoints

| Method | Path | Description |
|---|---|---|
| GET | `/api/v1/authorization_boundaries/:id/fedramp_significant_changes` | Every change, newest first, each with its deadlines |
| POST | `/api/v1/authorization_boundaries/:id/fedramp_significant_changes` | Record a change (`201`) |
| GET | `/api/v1/authorization_boundaries/:id/fedramp_significant_changes/:change_id` | One change |
| PUT | `/api/v1/authorization_boundaries/:id/fedramp_significant_changes/:change_id` | Update it. Only the fields sent change |
| GET | `/api/v1/authorization_boundaries/:id/fedramp_significant_changes/:change_id/notification` | Its Significant Change Notification, validated against FedRAMP's pinned schema. `422` for a routine change |
| POST | `/api/v1/authorization_boundaries/:id/fedramp_significant_changes/:change_id/notices` | Record a notice sent (`201`), keeping the notification as it stood |

The boundary may be named by id, slug or UUID; `:change_id` is the change's `uuid`. A change is never deleted.

## Authentication and authorization

A valid Bearer token whose user holds `evidence.read` on the boundary to read, `evidence.write` to record, or an instance administrator. The audit log records `fedramp_significant_change_recorded`, `fedramp_significant_change_notice_recorded` and `fedramp_significant_change_notification_exported`.

## Request body (POST, PUT)

```json
{
  "fedramp_significant_change": {
    "change_type": "Transformative",
    "description": "Move the database tier to a new region",
    "type_explanation": "Changes the system boundary and data flows",
    "reason": "Capacity",
    "customer_impact": "None expected; endpoints unchanged",
    "plan_summary": "Phased cutover with verification of the impacted KSIs",
    "planned_start": "2027-01-15",
    "planned_completion": "2027-02-12",
    "milestones": [ { "description": "Replica in sync", "target_date": "2027-01-29" } ],
    "impacted_controls": [ "KSI-CNA-RNT", "sc-7" ],
    "impact_analysis": "https://trust.example/sia/2027-01.pdf",
    "assessor_name": "Example 3PAO",
    "related_vulnerability": "",
    "approver_name": "Pat Doe",
    "approver_title": "CISO",
    "new_risks": "None identified",
    "emergency": false,
    "started_on": null,
    "finished_on": null,
    "verified_on": null
  }
}
```

`change_type` (`Routine`, `Adaptive`, `Transformative`) and `description` are required. `plan_summary` is required once the plan has dates or milestones. Dates are `YYYY-MM-DD`; the finish may not precede the start, nor the verification the finish.

The notification carries the schema's fields. The approver's name and title and the new risks, which FedRAMP requires (SCN-CSO-INF, SCN-ADP-NTF, SCN-TRF-NAV) but the schema has no field for, are included as additional information (SCN-CSO-ARI): `approverName`, `approverTitle`, `newRisksSummary`.

### Recording a notice

```json
{ "notice": { "stage": "after_finish", "sent_on": "2026-12-04" } }
```

`stage` is one of the change's deadlines: `initial_plans`, `final_plans`, `after_finish`, `after_verification`, `documentation`. `sent_on` may not be in the future. Recording a stage again replaces the earlier record. A notice keeps the notification exactly as it stood and its SHA-256 (the published documentation stage has no document).

## Response

```json
{
  "data": {
    "uuid": "6f1c…",
    "change_type": "Adaptive",
    "description": "New dashboard",
    "finished_on": "2026-11-20",
    "notices": [
      { "stage": "after_finish", "rule_id": "SCN-ADP-NTF", "sent_on": "2026-12-04",
        "recorded_at": "2026-12-04T15:02:11Z", "recorded_by_id": 7, "recorded_by": "Pat Doe", "sha256": "…" }
    ],
    "deadlines": [
      { "stage": "after_finish", "rule_id": "SCN-ADP-NTF", "label": "After finishing", "due_on": "2026-12-07",
        "timeframe": [ "bizdays", 10 ], "retroactive": false, "status": "sent", "sent_on": "2026-12-04" }
    ]
  }
}
```

A deadline's `status` is `sent`, `late` (sent after it was due), `overdue`, `due`, or `waiting` (the date it counts from is not recorded yet).

## Errors

| Status | When |
|---|---|
| `403` | No `evidence.read` (or `evidence.write` to record) on the boundary |
| `404` | No such change on this boundary |
| `422` | FedRAMP is off for the boundary; a value the record does not allow; an unknown field; a routine change's notification; a notice for a stage the change does not have; the boundary has no Certification Package Overview address, which every notification names |
| `502` | SPARC wrote a notification that does not validate (never returned) |

The [exchange index](exchange-index.md) lists 12 months of Adaptive and Transformative changes' notifications.
