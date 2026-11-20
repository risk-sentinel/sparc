# FedRAMP Reports API

A boundary's FedRAMP vulnerability reports (#1354, #1384), written from its scanner findings, finding dispositions and the provider's FedRAMP evaluation of each vulnerability:

- the **Vulnerability Detail Report** (FedRAMP rule VER-RPT-VDT), against FedRAMP's `fedramp-vulnerability-detail-report-schema-2026-06-24.json`;
- the **Accepted Vulnerability Info** (VER-RPT-AVI), against `fedramp-accepted-vulnerability-info-schema-2026-06-24.json`.

The response body is the FedRAMP document itself, with `$schema` naming the schema it validates against. SPARC validates every report against that pinned schema, and checks that every required field is filled in, before returning it.

## Endpoints

| Method | Path | Description |
|---|---|---|
| GET | `/api/v1/authorization_boundaries/:id/fedramp/vulnerability_detail_report` | The Vulnerability Detail Report for a period |
| GET | `/api/v1/authorization_boundaries/:id/fedramp/accepted_vulnerability_info` | The Accepted Vulnerability Info for a period |

The boundary may be named by id, slug or UUID. Both reports are also listed in the boundary's [exchange index](exchange-index.md) once the boundary has a FedRAMP Certification Package Overview address.

## Authentication and authorization

A valid Bearer token whose user holds `evidence.read` on the boundary (or across the instance), or an instance administrator.

Each download is recorded in the audit log as `fedramp_vulnerability_detail_report_exported` or `fedramp_accepted_vulnerability_info_exported`, with who downloaded it, the period and how many vulnerabilities it listed.

## Parameters

| Parameter | Description |
|---|---|
| `from` | Start of the report period: an ISO 8601 date-time, or a date (the start of that day, UTC). Default: 30 days before `to` |
| `to` | End of the report period: an ISO 8601 date-time, or a date (the end of that day, UTC). Default: now |

## What the reports contain

**A vulnerability** is a control whose scanner findings have ever failed. Its `providerTrackingId` is the control id, the one key that stays the same across scans. `detection.detectedAt` is its earliest failing result and `detection.detectionSource` that result's scanner.

**The period:** a report lists every vulnerability detected on or before `to` that was not resolved before `from`, so one active at any time in the period or resolved within it. Each is reported in its state at `to`.

**Accepted vulnerabilities** are listed in the Accepted Vulnerability Info and **not** in the Vulnerability Detail Report (VER-RPT-VDT: "UNLESS it is an accepted vulnerability"). A vulnerability that is not remediated and not a false positive is accepted when:

1. an approved disposition in force accepts the risk: its NIST risk prop is `accepted`, or it is a `waiver` or `operationalRequirement` (NIST response type `accept`). `acceptanceRationale` is the disposition's reason; or
2. it was not remediated within 192 days of its evaluation (VER-TFR-MAV). `acceptanceRationale` says so.

| Field | Source |
|---|---|
| `providerTrackingId` | The control id |
| `detection` | The earliest failing finding: when, and its scanner |
| `vulnerabilityDescription` | The newest finding's title and description; the control id and "(no description in the scan)" when the scan gave neither |
| `evaluationCompletedAt`, `isInternetReachable`, `isLikelyExploitable`, `currentRating`, `supplementaryRiskInformation` | The provider's FedRAMP evaluation |
| `painReductionEvents` | Each fall in the evaluation's N-rating, with when it was recorded |
| `projectedNextReduction` | The evaluation's planned next reduction; left out once resolved |
| `overdueStatus` | See below |
| `finalDisposition` | `False Positive` (an approved falsePositive), `Remediated` (the newest result passes or is not applicable), `Partially Mitigated` (an approved riskAdjustment, still detected); left out while still active |

`overdueStatus.isOverdue` is `false` once resolved, and for a vulnerability accepted by a disposition. It is `true` when 192 days have passed since evaluation (VER-TFR-MAV), or when a vulnerability has gone unevaluated for more than 14 days, the longest VER-TFR-EVU time frame. An unevaluated vulnerability more than 2 and up to 14 days old has no `overdueStatus`: it depends on the certification class, which SPARC does not record for a boundary.

Fields SPARC does not know are left out, never sent empty or null. `potentialAgencyImpact` (a description of the impact) is not written: SPARC records the N-rating, not a description.

```json
{
  "$schema": "https://fedramp.gov/schemas/fedramp-vulnerability-detail-report-schema-2026-06-24.json",
  "certificationPackageOverviewUri": "https://provider.example/package/cpo.json",
  "reportPeriod": { "from": "2026-10-21T00:00:00Z", "to": "2026-11-20T00:00:00Z" },
  "vulnerabilities": [
    {
      "providerTrackingId": "CVE-2026-1234",
      "detection": { "detectedAt": "2026-11-02T09:14:00Z", "detectionSource": "trivy" },
      "vulnerabilityDescription": "openssl: heap overflow\n\nA crafted certificate overflows ...",
      "evaluationCompletedAt": "2026-11-04T15:00:00Z",
      "isInternetReachable": true,
      "isLikelyExploitable": false,
      "currentRating": 2,
      "painReductionEvents": [ { "reducedAt": "2026-11-10T12:00:00Z", "rating": 2 } ],
      "projectedNextReduction": { "estimatedAt": "2026-11-30T00:00:00Z", "targetRating": 0 },
      "overdueStatus": { "isOverdue": false }
    }
  ]
}
```

## Errors

| Status | When |
|---|---|
| `401` | No token, or an invalid one |
| `403` | No `evidence.read` on this boundary |
| `404` | No such boundary |
| `422` | The boundary has no FedRAMP Certification Package Overview address, or `from` / `to` is not an ISO 8601 date or date-time, or `from` is not before `to` |
| `502` | SPARC built a report that fails FedRAMP's schema or its completeness check. It is not returned; the body is `{ "error": "SPARC produced an invalid report", "details": [...] }`. This is a defect in SPARC, not in the request |

## NIST SP 800-53

RA-5 (vulnerability monitoring), CA-7 (continuous monitoring), CA-5 (accepted vulnerabilities), SI-2 (flaw remediation status), AC-3 / AC-6 (boundary-scoped permission), AU-12 (each download audited).
