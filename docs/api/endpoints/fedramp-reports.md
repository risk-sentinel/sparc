# FedRAMP Reports API

A boundary's FedRAMP reports (#1354, #1384, #1390). The vulnerability reports are written from its scanner findings, finding dispositions and the provider's FedRAMP evaluation of each vulnerability:

- the **Vulnerability Detail Report** (FedRAMP rule VER-RPT-VDT), against FedRAMP's `fedramp-vulnerability-detail-report-schema-2026-06-24.json`;
- the **Accepted Vulnerability Info** (VER-RPT-AVI), against `fedramp-accepted-vulnerability-info-schema-2026-06-24.json`;
- the **Historical Vulnerability Activity** (VER-TFR-MRH), against `fedramp-historical-ver-activity-schema-2026-06-24.json`: both lists in one snapshot, for automated retrieval.

The **Certification Package Overview** (FRC-CSO-PKG), against `fedramp-certification-package-overview-schema-2026-06-24.json`, is written from the boundary's FedRAMP fields and contacts (`fedramp_package`, `fedramp_contacts`; see [Authorization Boundaries](authorization-boundaries.md)). It includes service identification, service properties, the trust center and the contacts. It does not yet include the assessor, advisors, certified services or third-party information resources.

The **Security Decision Record** (SDR-CSO-FRR, SDR-CSO-MTD, SDR-CSX-KSI), against `fedramp-security-decision-record-schema-2026-06-24.json`, is written from what is recorded:

- `metadata`: `version` is the boundary's `fedramp_sdr_version`, which counts each change to its [FedRAMP statements](fedramp-statements.md); `lastUpdated` the newest statement or SSP change; `updateSource` this SPARC and the boundary's UUID;
- `portsAndProtocols`: one entry per OSCAL protocol and port range on the SSP's components, with the component's `encryption` property and its purpose (or description) when recorded;
- `securityControls`: the SSP's controls, each with a status from its statements (`implemented` / `alternative` → Implemented; `partial`, or in place mixed with `planned` → Partially Implemented; only `planned` → Not Implemented; `not-applicable` items do not count), its implementation prose, and its set-parameters. For Rev5, FedRAMP's assigned value fills any parameter the SSP leaves unset (FRC-CSF-ACP);
- `fedRampRequirements` and `keySecurityIndicators`: the boundary's answered rules that apply to its profile, and its answered KSIs; each paragraph of a text field is one statement.

The record is written from whatever is recorded. What FedRAMP still requires of it (unanswered rules, unanswered KSIs for 20x, Rev5 baseline controls missing from the SSP per FRC-CSF-BSL, ports and protocols) is counted in the `X-SPARC-SDR-Gaps` response header and listed on the boundary's FedRAMP page.

The response body is the FedRAMP document itself, with `$schema` naming the schema it validates against. SPARC validates every report against that pinned schema, and checks that every required field is filled in, before returning it.

## Endpoints

| Method | Path | Description |
|---|---|---|
| GET | `/api/v1/authorization_boundaries/:id/fedramp/vulnerability_detail_report` | The Vulnerability Detail Report for a period |
| GET | `/api/v1/authorization_boundaries/:id/fedramp/accepted_vulnerability_info` | The Accepted Vulnerability Info for a period |
| GET | `/api/v1/authorization_boundaries/:id/fedramp/historical_ver_activity` | The Historical Vulnerability Activity: active and accepted vulnerabilities together, by default for the 12 months ending now |
| GET | `/api/v1/authorization_boundaries/:id/fedramp/certification_package_overview` | The Certification Package Overview. It takes no parameters |
| GET | `/api/v1/authorization_boundaries/:id/fedramp/security_decision_record` | The Security Decision Record. It takes no parameters |

The boundary may be named by id, slug or UUID. The three vulnerability reports are also listed in the boundary's [exchange index](exchange-index.md) once the boundary has a FedRAMP Certification Package Overview address. The overview is listed once the boundary records every field it requires.

## The overview address

Each vulnerability report names the overview's address (`certificationPackageOverviewUri`). It is one of:

- the boundary's `fedramp_package_overview_uri`, normally where the provider's trust center publishes the overview (FedRAMP requires a trust center, CDS-CSO-UTC);
- SPARC's own endpoint above, when the boundary sets `fedramp_overview_from_sparc`. The address is `SPARC_APP_URL` plus `/api/v1/authorization_boundaries/<boundary UUID>/fedramp/certification_package_overview`, so `SPARC_APP_URL` must be an `https://` address. Readers need a SPARC token, so this endpoint does not by itself meet FedRAMP's trust center rules (CDS-TRC).

The boundary's `fedramp_overview_address` gives the address in effect.

## Authentication and authorization

A valid Bearer token whose user holds `evidence.read` on the boundary (or across the instance), or an instance administrator.

Each download is recorded in the audit log as `fedramp_vulnerability_detail_report_exported`, `fedramp_accepted_vulnerability_info_exported` or `fedramp_historical_ver_activity_exported`, with who downloaded it, the period (or, for the historical activity, its `generatedAt`) and how many vulnerabilities it listed. The overview is recorded as `fedramp_certification_package_overview_exported`, with how many contacts it listed; the SDR as `fedramp_security_decision_record_exported`, with its version, how many rules it carries and how many gaps remain.

## Parameters

| Parameter | Description |
|---|---|
| `from` | Start of the report period: an ISO 8601 date-time, or a date (the start of that day, UTC). Default: 30 days before `to`; for the historical activity, 12 months before `to` |
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

**The historical activity** lists the same entries as the two reports for its period: `activeVulnerabilities` holds the Vulnerability Detail Report's, and `acceptedVulnerabilities` the Accepted Vulnerability Info's, each with its `acceptanceRationale`. FedRAMP's schema gives it no `reportPeriod`; it carries `generatedAt`, when the snapshot was built. Its default window, the 12 months ending now, spans the 192 days after which a vulnerability not remediated is accepted.

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
| `422` | FedRAMP is not enabled for the boundary (`fedramp_enabled`, #1390); the boundary has no FedRAMP Certification Package Overview address (or names SPARC's own endpoint while `SPARC_APP_URL` is not `https://`), or `from` / `to` is not an ISO 8601 date or date-time, or `from` is not before `to`. For the overview: the boundary does not yet record a field it requires, or a Security or Sales contact; the error lists what is missing |
| `502` | SPARC built a report that fails FedRAMP's schema or its completeness check. It is not returned; the body is `{ "error": "SPARC produced an invalid report", "details": [...] }`. This is a defect in SPARC, not in the request |

## NIST SP 800-53

PL-2 (the overview's system description), RA-5 (vulnerability monitoring), CA-7 (continuous monitoring), CA-5 (accepted vulnerabilities), SI-2 (flaw remediation status), AC-3 / AC-6 (boundary-scoped permission), AU-12 (each download audited).
