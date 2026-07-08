# Artifacts API

Durable artifact resolver (#680). Resolves an **immutable artifact UUID** to a freshly-signed, time-limited download URL for programmatic consumers (the UI and external OSCAL tooling).

The resolver separates a **stable identity** (the artifact's immutable UUID, surfaced as `/artifacts/:uuid` in exported OSCAL back-matter) from the **mutable location** (a short-lived signed blob URL). Because a new signed URL is generated on every request, the durable `/artifacts/:uuid` reference never expires and survives evidence rename, file re-upload, and signed-URL rotation.

## Base URL

```
https://sparc.example.com/api/v1/artifacts
```

## Authentication

All endpoints require a valid Bearer token.

```
Authorization: Bearer YOUR_API_TOKEN_HERE
```

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/artifacts/:uuid` | Resolve an artifact's stable UUID to its current content + signed URL |
| `GET` | `/api/v1/artifacts/versions/:uuid` | Resolve a specific retained content version by its version UUID |

---

### GET Resolve an Artifact

Resolves the stable logical identity (`:uuid`) to the artifact's **current** content and a freshly-signed download URL. The link/location is stable across re-uploads; the signed `url` is regenerated on every call.

**Path:** `GET /api/v1/artifacts/:uuid`

**Path Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `uuid` | string | Yes | Immutable artifact (Evidence) UUID as it appears in exported OSCAL back-matter |

**Example Request**

```bash
curl -X GET "https://sparc.example.com/api/v1/artifacts/2f1c9b84-3a6e-4d1a-9f0b-6b2f0c7e8a11" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Accept: application/json"
```

**Response Body**

```json
{
  "data": {
    "uuid": "2f1c9b84-3a6e-4d1a-9f0b-6b2f0c7e8a11",
    "title": "AC-2 Access Review Evidence Q2 2026",
    "filename": "ac-2-access-review-q2.pdf",
    "media_type": "application/pdf",
    "current_version_uuid": "8d4a2f10-1c33-4b7e-a2c9-77e5b1d9f004",
    "url": "https://userdata.sparc.example.com/rails/active_storage/blobs/redirect/..."
  }
}
```

**Status Codes**

| Code | Description |
|------|-------------|
| `200` | Artifact resolved; `url` is a freshly-signed, time-limited download link |
| `401` | Unauthorized -- missing or invalid token |
| `404` | Artifact not found, or the record has no attached file to resolve |

---

### GET Resolve an Artifact Version

Resolves a specific **content version** by its immutable version UUID (#680), returning its retained content and drift metadata (reviewed-at, superseded-at, whether it is current).

**Path:** `GET /api/v1/artifacts/versions/:uuid`

**Path Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `uuid` | string | Yes | Immutable `ArtifactVersion` UUID |

**Example Request**

```bash
curl -X GET "https://sparc.example.com/api/v1/artifacts/versions/8d4a2f10-1c33-4b7e-a2c9-77e5b1d9f004" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Accept: application/json"
```

**Response Body**

```json
{
  "data": {
    "version_uuid": "8d4a2f10-1c33-4b7e-a2c9-77e5b1d9f004",
    "logical_id": "2f1c9b84-3a6e-4d1a-9f0b-6b2f0c7e8a11",
    "reviewed_at": "2026-04-01T10:00:00Z",
    "superseded_at": null,
    "current": true,
    "current_version_uuid": "8d4a2f10-1c33-4b7e-a2c9-77e5b1d9f004",
    "media_type": "application/pdf",
    "url": "https://userdata.sparc.example.com/rails/active_storage/blobs/redirect/..."
  }
}
```

| Field | Description |
|-------|-------------|
| `logical_id` | The stable artifact (Evidence) UUID this version belongs to |
| `current` | `true` when this version is the artifact's current content |
| `superseded_at` | Timestamp when this version was replaced, or `null` if still current |
| `url` | Freshly-signed, time-limited download link for this retained version's content |

**Status Codes**

| Code | Description |
|------|-------------|
| `200` | Version resolved; `url` is a freshly-signed, time-limited download link |
| `401` | Unauthorized -- missing or invalid token |
| `404` | Version not found, or its retained content is missing |

---

## Common Errors

| Code | Error | Description |
|------|-------|-------------|
| `401` | `Unauthorized` | Missing or invalid Bearer token |
| `404` | `Not Found` | The UUID does not resolve to an artifact/version, or the record has no attached content |
| `500` | `Internal Server Error` | Unexpected server error -- contact your administrator |

## NIST 800-53 mapping

| Control | How these endpoints address it |
|---|---|
| `AU-10` Non-Repudiation | Stable artifact identity survives file re-upload and signed-URL rotation |
| `SI-12` Information Handling and Retention | Retained content versions are individually addressable |
| `CM-8` System Component Inventory | Every artifact/version has a durable, resolvable identifier |
