# HDF ↔ OSCAL Translations API

Stateless translation endpoints between the **Heimdall Data Format (HDF)** and **OSCAL** artifacts (#449). These endpoints do not persist anything to SPARC's database — tenant compliance state stays in the tenant's own systems. SPARC's value is centralizing the MITRE [hdf-libs](https://github.com/mitre/hdf-libs) CLI install (pinned to v3.1.0), and exposing the native HDF↔OSCAL translation as authenticated REST.

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

---

### POST `poam_from_hdf` — HDF results → OSCAL POA&M

```
POST /api/v1/oscal/poam_from_hdf
```

Converts an HDF results document into an OSCAL POA&M via `hdf convert --from hdf --to oscal-poam`. Accepts the same `authorization_boundary_id` enrichment parameter as `sar_from_hdf`.

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
