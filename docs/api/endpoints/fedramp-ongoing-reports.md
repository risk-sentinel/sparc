# FedRAMP Ongoing Certification Reports API

A boundary's FedRAMP Ongoing Certification Report (#1390). FedRAMP requires one every 3 months, covering the whole period since the previous report (CCM-OCR-AVL). SPARC writes it from the boundary's FedRAMP records, validated against FedRAMP's pinned schema before it is returned, and keeps each report issued exactly as issued.

| Section | Written from |
|---|---|
| `certificationDataChanges` | The FedRAMP rule and KSI answers updated in the period, the Adaptive and Transformative [significant changes](fedramp-significant-changes.md) finished in it, then any `other_changes` sent |
| `plannedCertificationDataChanges` | Adaptive and Transformative changes not finished by the period's end that are under way or planned to start within 3 months after it (`planningHorizonThrough`), then any `other_planned` sent |
| `acceptedVulnerabilities` | A summary of the boundary's [Accepted Vulnerability Info](fedramp-reports.md) for the period |
| `transformativeChanges` | Transformative changes started or finished in the period |
| `updatedRecommendations` | The `recommendations` sent for this report |
| `activeAgencies` | The boundary's `fedramp_active_agencies` ([Authorization Boundaries API](authorization-boundaries.md)) |
| `reportableIncidents.incidents` | The boundary's FedRAMP Reportable [incidents](fedramp-incidents.md) that began by the period's end and were not resolved before it began, with their lessons learned. An empty list attests that none occurred |

The period runs, by default, from the day after the last report issued (or 3 months back, for the first) to today. It may not end in the future. A report issued may not start on or before the end of one already issued. The next report is due 3 months after the last period ends (`next_target_date`, CCM-OCR-NRD).

FedRAMP must be turned on for the boundary (`fedramp_enabled`); otherwise every endpoint answers `422`.

## Endpoints

| Method | Path | Description |
|---|---|---|
| GET | `/api/v1/authorization_boundaries/:id/fedramp_ongoing_reports` | The reports issued, newest first (without their documents), with `meta.next_target_date` and `meta.default_period` |
| GET | `/api/v1/authorization_boundaries/:id/fedramp_ongoing_reports/draft` | The report for a period, not issued. Query: `from`, `to` (`YYYY-MM-DD`), `recommendations[]`, `other_changes[]`, `other_planned[]` |
| POST | `/api/v1/authorization_boundaries/:id/fedramp_ongoing_reports` | Issue the report (`201`), kept exactly as issued with its SHA-256 |
| GET | `/api/v1/authorization_boundaries/:id/fedramp_ongoing_reports/:report_id` | One report as issued, with its `document` |

The boundary may be named by id, slug or UUID; `:report_id` is the report's `uuid`. A report issued is never changed or deleted.

## Authentication and authorization

The report summarizes the boundary's reportable incidents, so a Bearer token's user needs **`incident.read`** on the boundary as well as `evidence.read` to read, and `evidence.write` with `incident.read` to issue; or an instance administrator. The audit log records `fedramp_ongoing_report_issued` and `fedramp_ongoing_report_exported`.

## Request body (POST)

Every field is optional; an empty body issues the default period.

```json
{
  "fedramp_ongoing_report": {
    "from": "2026-08-21",
    "to": "2026-11-20",
    "recommendations": [ "Rotate API keys at least yearly" ],
    "other_changes": [ "New service logo" ],
    "other_planned": []
  }
}
```

At most 100 lines in each list.

## Response (POST, GET one)

```json
{
  "data": {
    "uuid": "0b6e…",
    "period_from": "2026-08-21",
    "period_to": "2026-11-20",
    "recommendations": [ "Rotate API keys at least yearly" ],
    "sha256": "…",
    "issued_by_id": 7,
    "issued_at": "2026-11-20T15:04:05Z",
    "document": { "$schema": "https://fedramp.gov/schemas/fedramp-ongoing-certification-report-schema-2026-06-24.json", "…": "…" }
  }
}
```

## Errors

| Status | When |
|---|---|
| `403` | No `evidence.read` and `incident.read` (or `evidence.write` to issue) on the boundary |
| `404` | No such report on this boundary |
| `422` | FedRAMP is off for the boundary; a bad or future period; a period starting on or before the end of one already issued; an unknown field; the boundary has no Certification Package Overview address, which the report names |
| `502` | SPARC wrote a report that does not validate (never returned) |
