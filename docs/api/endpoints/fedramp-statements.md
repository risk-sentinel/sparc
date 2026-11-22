# FedRAMP Statements API

A boundary's answer to each FedRAMP rule (FRR) that applies to it and to each FedRAMP Key Security Indicator (KSI) (#1390). Its Security Decision Record carries these answers (FedRAMP SDR-CSO-FRR, SDR-CSX-KSI).

Which rules apply is decided by the boundary's FedRAMP certification profile: `certification_type` (`20x` or `Rev5`), `certification_path` (`Program` or `Agency`) and `certification_class` (`A`–`D`), set in `fedramp_package` with [`PATCH /api/v1/authorization_boundaries/:id`](authorization-boundaries.md). SPARC reads the rules from the vendored FedRAMP Consolidated Rules and returns those that affect providers:

- each subset of rules applies to the types, paths and classes FedRAMP names for it;
- a rule whose wording varies by class gets that class's statement and force (`MUST`, `SHOULD`, `MAY`, ...);
- Class A adds the rules FedRAMP lists for it as mandatory (FRC-CLA-MFR, `MUST`), recommended (FRC-CLA-RFR, `SHOULD`) and optional (FRC-CLA-OFR, `MAY`).

Every KSI may be answered. The SDR requires them for 20x; a Rev5 boundary may record them too.

FedRAMP must be turned on for the boundary (`fedramp_enabled`); otherwise every endpoint answers `422`.

## Endpoints

| Method | Path | Description |
|---|---|---|
| GET | `/api/v1/authorization_boundaries/:id/fedramp_statements` | Every rule that applies (`?kind=frr`, the default) or every KSI (`?kind=ksi`), each with the boundary's answer, or `null` |
| GET | `/api/v1/authorization_boundaries/:id/fedramp_statements/:kind/:rule_id` | One rule or KSI and its answer |
| PUT | `/api/v1/authorization_boundaries/:id/fedramp_statements/:kind/:rule_id` | Record the answer: `201` the first time, `200` after. Only the fields sent change |

The boundary may be named by id, slug or UUID. `:kind` is `frr` or `ksi`; `:rule_id` is FedRAMP's id (`SDR-CSO-FRR`, `KSI-CED-RAT`).

## Authentication and authorization

A valid Bearer token whose user holds `evidence.read` on the boundary to read, `evidence.write` to record, or an instance administrator. Each change is recorded in the audit log as `fedramp_statement_recorded`.

## Request body (PUT)

```json
{
  "fedramp_statement": {
    "status": "Partially Implemented",
    "implementation": "How the rule is followed, or why not and the risk to customers.",
    "validation": "How it was shown to be in place and working.",
    "assessment": "The verification of it.",
    "tests": ["Quarterly review of training completion"],
    "evidence": [
      { "evidence_type": "Report", "description": "LMS completion report",
        "location": "https://evidence.example/lms", "text": "", "last_updated": "2026-11-01" }
    ]
  }
}
```

| Field | Description |
|---|---|
| `status` | `Implemented`, `Partially Implemented` or `Not Implemented` (the SDR schema's values); `null` clears it |
| `implementation`, `validation`, `assessment` | Text, at most 20,000 characters each |
| `tests` | KSI only: the tests that demonstrate it, at most 50 |
| `evidence` | KSI only: entries with `evidence_type` (the SDR schema's values: `Log`, `Report`, `Screenshot`, `Configuration`, `Policy`, `Procedure`, `Audit Record`), `description`, `location` (an http(s) address), `text`, `last_updated` (`YYYY-MM-DD`); at most 50 |

Each change counts up the boundary's `fedramp_sdr_version`, which the Security Decision Record carries as its `metadata.version`.

## Response

```json
{
  "data": [
    { "kind": "frr", "rule_id": "SDR-CSO-FRR", "name": "FedRAMP Rules", "statement": "Providers MUST supply ...",
      "family": "SDR", "force": "MUST",
      "answer": { "status": "Implemented", "implementation": "...", "validation": null, "assessment": null,
                  "tests": [], "evidence": [], "updated_at": "2026-11-21T20:00:00Z", "updated_by_id": 7 } }
  ],
  "meta": { "kind": "frr", "certification_type": "20x", "certification_path": "Program", "certification_class": "B",
            "sdr_version": 3, "rules_version": "2026.11.02.01", "total": 157, "answered": 1 }
}
```

A KSI carries `theme` and `controls` (its NIST SP 800-53 Rev 5 controls) instead of `family` and `force`.

## Errors

| Status | When |
|---|---|
| `401` | No token, or an invalid one |
| `403` | No `evidence.read` (or, to record, `evidence.write`) on this boundary |
| `404` | No such boundary |
| `422` | FedRAMP is not enabled for the boundary; the rule does not apply to its profile (or the profile is incomplete); a value the SDR schema does not allow; or a field the endpoint does not take |

## NIST SP 800-53

PL-2 (security documentation), CA-2 (control assessments), AC-3 / AC-6 (boundary-scoped permission), AU-12 (each change audited).
