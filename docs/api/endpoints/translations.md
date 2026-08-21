# HDF ↔ OSCAL Translations API

Stateless translation endpoints between the **Heimdall Data Format (HDF)** and **OSCAL** artifacts (#449). These endpoints do not persist anything to SPARC's database — tenant compliance state stays in the tenant's own systems. SPARC's value is centralizing the MITRE [hdf-libs](https://github.com/mitre/hdf-libs) CLI install (pinned to v3.2.0), and exposing the native HDF↔OSCAL translation as authenticated REST.

## Base URL

```
https://sparc.example.com/api/v1
```

## Authentication

All endpoints require a valid Bearer token.

```
Authorization: Bearer YOUR_API_TOKEN_HERE
```

## Authorization

Any authenticated user may translate (AC-3 — no extra permission required). The **optional back-matter enrichment** (`authorization_boundary_id` parameter, see below) additionally requires `evidence.read` on the named boundary.

## Payload formats

Every endpoint accepts the input document in either of two ways:

- **`multipart/form-data`** with a `file` field, or
- **a raw request body** with `Content-Type: application/json`.

If neither is supplied the endpoint returns `400 Bad Request`.

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/v1/oscal/sar_from_hdf` | HDF results → OSCAL Assessment Results (SAR) |
| `POST` | `/api/v1/oscal/poam_from_hdf` | HDF results → OSCAL Plan of Action & Milestones (POA&M) |
| `POST` | `/api/v1/oscal/poam_from_amendments` | HDF Amendments → OSCAL Plan of Action & Milestones (POA&M) |
| `POST` | `/api/v1/hdf/amendments_from_oscal_poam` | OSCAL POA&M → HDF Amendments JSON |

---

### POST `sar_from_hdf` — HDF results → OSCAL SAR

```
POST /api/v1/oscal/sar_from_hdf
```

Converts an HDF results document into an OSCAL Assessment Results document via `hdf convert --from hdf --to oscal-sar`.

**Optional query parameter**

| Parameter | Type | Description |
|-----------|------|-------------|
| `authorization_boundary_id` | integer | When supplied, SPARC merges the boundary's Evidence (and attestation provenance) into the OSCAL output's `back-matter.resources[]`. Requires `evidence.read` on the boundary. |

**Request (raw JSON body)**

```bash
curl -X POST https://sparc.example.com/api/v1/oscal/sar_from_hdf \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  --data-binary @results.hdf.json
```

**Request (multipart)**

```bash
curl -X POST "https://sparc.example.com/api/v1/oscal/sar_from_hdf?authorization_boundary_id=42" \
  -H "Authorization: Bearer $TOKEN" \
  -F "file=@results.hdf.json"
```

**Response** `200 OK` — an OSCAL SAR document:

```json
{
  "assessment-results": {
    "uuid": "…",
    "metadata": { "title": "…", "oscal-version": "1.1.2" },
    "results": [ … ]
  }
}
```

#### Output is schema-validated before it is returned

SPARC validates the translated document against the bundled NIST OSCAL v1.1.2
Assessment Results schema and **will not return one that fails**. Previously this
endpoint returned the converter's output as-is, so a caller could receive a
`200` carrying a document no OSCAL tool would accept — a failure that then
surfaced somewhere with no connection to this call.

**Response** `502 Bad Gateway` — the converter produced non-conforming OSCAL:

```json
{
  "error": "The translated document does not conform to the OSCAL schema and was not returned",
  "details": [
    "/assessment-results/results/0: missing required properties: reviewed-controls",
    "/assessment-results/results/0/findings/0: missing required properties: description",
    "/assessment-results/results/0/risks/0/characterizations/0: missing required properties: origin"
  ],
  "note": "This is a defect in the bundled hdf-libs converter, not in the submitted file. …"
}
```

`502` rather than `422` is deliberate: **your input is not the problem**, and
there is nothing you can change about the submitted HDF to fix it. The fault is
in the upstream converter SPARC depends on.

> **Known limitation.** With the currently pinned hdf-cli (3.4.1), this endpoint
> returns `502` for real HDF input: the converter omits OSCAL-required
> properties (`reviewed-controls`, `finding/description`,
> `characterization/origin`) and emits an empty `prop.value`. Tracked upstream at
> [mitre/hdf-libs#184](https://github.com/mitre/hdf-libs/issues/184); the
> endpoint starts returning `200` once a fixed hdf-libs is pinned.
>
> SPARC does not fill the gaps in. `reviewed-controls` is *what the assessment
> covered* — synthesising it would produce a document that passes the schema and
> misstates the assessment. Determining it is the converter's job.

---

### POST `poam_from_hdf` — HDF results → OSCAL POA&M

```
POST /api/v1/oscal/poam_from_hdf
```

Converts an HDF results document into an OSCAL POA&M via `hdf convert --from hdf --to oscal-poam`. Accepts the same `authorization_boundary_id` enrichment parameter as `sar_from_hdf`.

> **Note (hdf-cli 3.2.0):** the bundled hdf-cli removed the direct `hdf → oscal-poam` converter, so this endpoint returns **`501 Not Implemented`**. To produce an OSCAL POA&M, use `poam_from_amendments` below (the 3.2.0-supported path). Tracked in [mitre/hdf-libs#104](https://github.com/mitre/hdf-libs/issues/104) and SPARC #663.

**Response** `200 OK`:

```json
{
  "plan-of-action-and-milestones": {
    "uuid": "…",
    "metadata": { "oscal-version": "1.1.2" },
    "poam-items": [ … ]
  }
}
```

---

### POST `poam_from_amendments` — HDF Amendments → OSCAL POA&M

```
POST /api/v1/oscal/poam_from_amendments
```

> ### ⚠️ Currently unavailable on the bundled converter
>
> **hdf-cli 3.5.1 emits an OSCAL POA&M that fails the NIST OSCAL schema on EVERY
> OSCAL release from 1.1.1 through 1.2.2** — so this
> endpoint returns **`502 Bad Gateway`** rather than an invalid document, for *valid*
> HDF Amendments input and not only for malformed input.
>
> Targeting a newer OSCAL version does not help: 1.2.x rejects **more** (7–8
> violations vs 3), because it applies the non-empty-string datatype to `title`
> fields the 1.1.x schemas left unconstrained. The document declares itself
> `"oscal-version": "1.1.2"`.
>
> Three violations on the 1.1.x line, reproducible from a four-line synthetic fixture:
>
> ```
> /plan-of-action-and-milestones/risks/0: missing required properties: statement
> /plan-of-action-and-milestones/risks/0/props/0/value: does not match pattern
> /plan-of-action-and-milestones/metadata/parties/0/name: does not match pattern
> ```
>
> **Do not build a pipeline on this endpoint until the upstream converter is fixed.**
> `sar_from_hdf` is unaffected — that path was fixed in 3.5.1; this one was not.
>
> Filed upstream as [mitre/hdf-libs#236](https://github.com/mitre/hdf-libs/issues/236).
> Full evidence, the reproducer and the raw converter output are in
> [`docs/dev/hdf-libs-3.5.1-oscal-poam-upstream-report.md`](../../dev/hdf-libs-3.5.1-oscal-poam-upstream-report.md). Until then SPARC will not
> return the document: it validates every OSCAL document it emits (#831, #1017), and a
> 200 carrying invalid OSCAL is worse than an error because it propagates — the
> consumer stores it, signs it, or submits it, and the failure surfaces somewhere with
> no connection to this call.

Converts an **HDF Amendments** document into an OSCAL POA&M via `hdf convert --from hdf-amendments --to oscal-poam`. This is the hdf-cli 3.2.0-supported replacement for the removed direct `hdf → oscal-poam` path (#663). Accepts the same optional `authorization_boundary_id` enrichment parameter as `sar_from_hdf`.

**Response** `200 OK` — *when the converter emits schema-valid OSCAL; see the warning above*:

```json
{
  "plan-of-action-and-milestones": {
    "uuid": "…",
    "metadata": { "oscal-version": "1.1.2" },
    "poam-items": [ … ]
  }
}
```

**Response** `502 Bad Gateway` — what the bundled converter currently produces:

```json
{
  "error": "The translated document does not conform to the OSCAL schema and was not returned",
  "details": [
    "OSCAL poam validation failed:",
    "/plan-of-action-and-milestones/risks/0: missing required properties: statement"
  ],
  "note": "This is a defect in the bundled hdf-libs converter, not in the submitted file."
}
```

---

### POST `amendments_from_oscal_poam` — OSCAL POA&M → HDF Amendments

```
POST /api/v1/hdf/amendments_from_oscal_poam
```

Converts an OSCAL POA&M document into an HDF **Amendments** document (`hdf convert --from oscal-poam`). The result is round-tripped through `hdf amend verify` before being returned, so the payload is guaranteed to `hdf amend apply` cleanly. No boundary enrichment applies.

**Response** `200 OK` — an HDF Amendments document.

---

## Errors

| Status | When |
|--------|------|
| `400 Bad Request` | No payload supplied (neither `file` nor raw body) |
| `401 Unauthorized` | Missing or invalid Bearer token |
| `403 Forbidden` | `authorization_boundary_id` supplied without `evidence.read` on that boundary |
| `404 Not Found` | `authorization_boundary_id` references a non-existent boundary |
| `422 Unprocessable Entity` | `hdf-libs` rejected the input (invalid HDF/OSCAL); the body includes `details` and a truncated `stderr` |

All errors follow the standard SPARC error envelope (`{"error": "…"}`); see [errors.md](../errors.md).

## NIST 800-53 controls

`IA-2` (Bearer auth), `AC-3` (access enforcement), `AU-12` (each translation audit-logged), `CA-7` (continuous-monitoring translation surface), `SI-2` (amendments output gates tenant pipelines).
