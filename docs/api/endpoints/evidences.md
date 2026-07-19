# Evidence API

REST API for compliance **evidence** artifacts (#756) — the raw material of an assessment: a screenshot, scan result, config export, signed statement, or policy document demonstrating that a control is implemented.

Before #756, evidence could only be created through the web UI. The API exposed attestations nested under an *assumed-existing* evidence record but offered no way to create one, which blocked tenants without automated validation pipelines from submitting evidence programmatically.

Related surfaces:

- [Evidence Control Links](evidence-control-links.md) — associate evidence with a control / CDEF part, and drive OSCAL back-matter
- [Evidence Attestations](attestations.md) — periodic-review sign-off records
- [Artifacts](artifacts.md) — durable UUID resolver for the stored file

## Base URL

```
https://sparc.example.com/api/v1/evidences
```

The `:id` segment accepts either a numeric id or the evidence slug.

## Authentication

All endpoints require a valid Bearer token.

```
Authorization: Bearer YOUR_API_TOKEN_HERE
```

## Authorization

| Action | Permission |
|--------|-----------|
| `index`, `show` | `evidence.read` (or Instance Admin) |
| `create`, `update`, `destroy` | `evidence.write` (or Instance Admin) |

### Boundary scoping

Instance Admins see all evidence. Other users see evidence in their own authorization boundaries **plus** evidence with no boundary (global artifacts) — matching what the same user sees in the web UI. Evidence's `authorization_boundary_id` is optional, so global evidence is a normal case rather than an edge case.

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/evidences` | List evidence (paginated, newest first, boundary-scoped) |
| `GET` | `/api/v1/evidences/:id` | Show a single evidence record (detailed) |
| `POST` | `/api/v1/evidences` | Create evidence, optionally with a file upload |
| `PATCH` / `PUT` | `/api/v1/evidences/:id` | Update evidence |
| `DELETE` | `/api/v1/evidences/:id` | Delete evidence (audit-logged) |

---

### GET List Evidence

```
GET /api/v1/evidences
```

Returns a paginated list (see [pagination.md](../pagination.md)), newest first.

**Query parameters**

| Parameter | Description |
|---|---|
| `type` | Filter by `evidence_type` (e.g. `scan_result`) |
| `status` | Filter by status (e.g. `collected`) |
| `authorization_boundary_id` | Filter to one boundary |
| `control_id` | Only evidence linked to this control (e.g. `AC-2`) |
| `q` | Free-text over title, description, and original filename |
| `items` / `per_page` | Page size (default 25, max 200) |
| `page` | Page number |

**Response** `200 OK`

```json
{
  "data": [
    {
      "id": 42,
      "uuid": "6f1c0c4e-2b7a-4e51-9a0d-8f2b1c3d4e5f",
      "slug": "q3-vulnerability-scan",
      "title": "Q3 Vulnerability Scan",
      "evidence_type": "scan_result",
      "type_label": "Scan Result",
      "status": "collected",
      "status_label": "Collected",
      "source": "https://scanner.example.com/runs/8821",
      "authorization_boundary_id": 3,
      "collected_at": "2026-07-18T14:02:11Z",
      "collected_by": "Alex Rivera",
      "has_file": true,
      "created_at": "2026-07-18T14:02:11Z"
    }
  ],
  "meta": { "page": 1, "pages": 1, "count": 1, "items": 25 }
}
```

---

### GET Show Evidence

```
GET /api/v1/evidences/:id
```

**Response** `200 OK` — the list shape above plus:

```json
{
  "data": {
    "description": "Authenticated Nessus scan of the production VPC.",
    "original_filename": "q3-scan.pdf",
    "file_content_type": "application/pdf",
    "file_size": 184320,
    "file_hash": "9f2b...c31a",
    "oscal_resolver_url": "https://sparc.example.com/artifacts/6f1c0c4e-2b7a-4e51-9a0d-8f2b1c3d4e5f",
    "linked_control_ids": ["AC-2", "RA-5"],
    "attested": false,
    "updated_at": "2026-07-18T14:05:40Z"
  }
}
```

`oscal_resolver_url` is the durable href (#680) used in OSCAL back-matter. It survives rename, file re-upload, and signed-URL rotation.

---

### POST Create Evidence

```
POST /api/v1/evidences
```

Accepts **`multipart/form-data`** (metadata plus a file) or **`application/json`** for metadata-only evidence.

**Body parameters** (under the `evidence` key)

| Field | Required | Notes |
|---|---|---|
| `title` | yes | |
| `description` | yes | |
| `source` | yes | Where the artifact came from |
| `evidence_type` | yes | `artifact`, `screenshot`, `log`, `config_export`, `scan_result`, `signed_statement`, `policy_document`, `test_result` |
| `status` | yes | `draft`, `collected`, `reviewed`, `attested`, `expired` |
| `authorization_boundary_id` | no | Omit for global evidence |
| `file` | no | The artifact itself |
| `control_ids` | no | Array or comma-separated string; replaces existing control links |

> **`collected_at` and `collected_by` are server-recorded and cannot be set by the client** (#738, NIST AU-10). Values supplied in the request are ignored.

**Example** (multipart)

```bash
curl -X POST https://sparc.example.com/api/v1/evidences \
  -H "Authorization: Bearer $SPARC_TOKEN" \
  -F "evidence[title]=Q3 Vulnerability Scan" \
  -F "evidence[description]=Authenticated Nessus scan of the production VPC." \
  -F "evidence[source]=https://scanner.example.com/runs/8821" \
  -F "evidence[evidence_type]=scan_result" \
  -F "evidence[status]=collected" \
  -F "evidence[file]=@q3-scan.pdf"
```

**Response** `201 Created` — the detailed shape, with a `Location` header.

#### Upload validation

Evidence is arbitrary artifact content (PDF, images, logs, scanner output), so there is **no MIME allowlist** — the document-import allowlist would reject legitimate artifacts. Instead:

- **Executable content is rejected.** The first 32 bytes are checked against known executable signatures (PE/MS-DOS, ELF, Mach-O, Java class, WebAssembly, shebang scripts). A match returns `422` and nothing is persisted.
- **Size is capped** by `SPARC_MAX_UPLOAD_MB`; an oversized file returns `422`.

```json
{
  "error": "File rejected: detected ELF binary (Linux executable). Executable content is not permitted as an upload."
}
```

---

### PATCH Update Evidence

```
PATCH /api/v1/evidences/:id
```

Same body parameters as create, all optional. Supplying a new `file` re-computes the hash and file metadata. Supplying `control_ids` replaces the existing links; omitting the key leaves them untouched.

**Response** `200 OK` — the detailed shape.

---

### DELETE Evidence

```
DELETE /api/v1/evidences/:id
```

Hard delete, audit-logged. Cascades to the evidence's control links and attestations.

**Response** `200 OK`

```json
{ "data": { "id": 42, "slug": "q3-vulnerability-scan", "deleted": true } }
```

---

## Errors

Standard envelope — see [errors.md](../errors.md).

| Status | When |
|---|---|
| `400` | The `evidence` root key is missing from the body |
| `401` | Missing or invalid token |
| `403` | Lacks `evidence.read` / `evidence.write` for the boundary |
| `404` | No evidence with that id or slug |
| `422` | Validation failed, executable upload, or file over the size cap |

## NIST 800-53 mapping

| Control | How |
|---|---|
| IA-2 | Bearer token required on every endpoint |
| AC-3 / AC-6 | `evidence.read` / `evidence.write`, boundary-scoped |
| AU-10 | `collected_at` / `collected_by` server-recorded, never client-supplied |
| AU-12 | All mutations audit-logged |
| CA-2 / CA-7 | Evidence lifecycle for assessment and continuous monitoring |
| SI-10 | Executable-signature deny-list and upload size cap |
