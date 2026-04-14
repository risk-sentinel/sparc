# SPARC API — Postman Collection

Complete Postman collection and environment files for the SPARC REST API (v1).

## Quick Start

1. **Import the collection** into Postman:
   - Open Postman → Import → Upload Files
   - Select `sparc-api.postman_collection.json`

2. **Import an environment**:
   - Select `sparc-local.postman_environment.json` for local development
   - Or `sparc-prod.postman_environment.json` for production

3. **Set your API token**:
   - In the environment, set `auth_token` to your SPARC Bearer token
   - Tokens are generated via the Admin UI (Enterprise → Service Accounts) or Rails console

4. **Send a request**:
   - Start with **Discovery → Available Endpoints** to see what you can access
   - The response is scoped to your permissions

## Files

| File | Description |
|------|-------------|
| `sparc-api.postman_collection.json` | 61 endpoints across 13 folders |
| `sparc-prod.postman_environment.json` | Production (sparc.risk-sentinel-sparc.org) |
| `sparc-local.postman_environment.json` | Local development (localhost:3000) |

## Authentication

All API requests require a Bearer token in the `Authorization` header:

```
Authorization: Bearer sparc_your_token_here
```

### Getting a Token

**Option 1: Admin UI (recommended)**
- Login → Enterprise → Service Accounts → Create
- Token is shown once — copy it immediately

**Option 2: Rails Console**
```ruby
token = ApiToken.generate!(user: User.find_by(email: "admin@sparc.local"), name: "postman-testing")
puts token.plaintext_token  # => "sparc_abc123..."
```

### Authentication Modes

SPARC supports three API authentication modes (controlled by `SPARC_API_AUTH` env var):

| Mode | Token Type | Use Case |
|------|-----------|----------|
| `local` (default) | SPARC Bearer tokens (`sparc_` prefix) | Development, standalone |
| `oidc` | Okta/OIDC JWT tokens (`eyJ` prefix) | Full IdP-managed access |
| `hybrid` | Both — JWTs for humans, SPARC tokens for service accounts | **Recommended for production** |

## Collection Structure

### 1. Discovery (1 endpoint)
- `GET /api/v1/available` — Authorization-scoped endpoint inventory

### 2. SSP Documents (7 endpoints)
- CRUD + Excel convert + bulk field update + JSON export
- Uses `:slug` identifier (e.g., `acme-cloud-platform-ssp`)

### 3. SAR Documents (7 endpoints)
- Same pattern as SSP — CRUD + convert + export

### 4. SAP Documents (5 endpoints)
- Standard CRUD with soft-delete

### 5. POA&M Documents (5 endpoints)
- Standard CRUD with soft-delete

### 6. Control Catalogs (5 endpoints)
- CRUD — **admin-only for writes**
- Uses numeric `:id`

### 7. Profile Documents (5 endpoints)
- CRUD with soft-delete
- Uses `:slug` identifier

### 8. Baseline Parameters (3 endpoints)
- Nested under profiles: `/api/v1/profile_documents/:slug/parameters`
- GET schema (with `?family=ac` filter), PUT bulk update, GET export (`?format=yaml`)

### 9. CDEF Documents (5 endpoints)
- CRUD with soft-delete

### 10. Control Mappings (5 endpoints)
- CRUD — **admin-only for writes**

### 11. KSI Catalog (4 endpoints)
- Read-only: themes, indicators (with filters), indicator detail, NIST mappings

### 12. KSI Validations (7 endpoints)
- Nested under authorization boundaries
- CRUD + summary dashboard + compliance report export

### 13. Back-Matter Resources (7 endpoints)
- CRUD + link/unlink control associations
- Filterable by organization, globally_available, rel, source, document, control
- OSCAL-validated `rel` (12 values) and `media_type` (IANA types)
- Supports `authoritative` source for enterprise provider publishing
- Uses numeric `:id`

## Response Format

All list endpoints return paginated responses:

```json
{
  "data": [ ... ],
  "meta": {
    "page": 1,
    "pages": 5,
    "count": 48,
    "items": 10
  }
}
```

**Pagination parameters**: `?page=2&items=25`

## Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `base_url` | API base URL | `http://localhost:3000` |
| `auth_token` | Bearer token (secret) | `sparc_abc123...` |
| `catalog_id` | Numeric catalog ID | `1` |
| `ssp_slug` | SSP document slug | `acme-cloud-platform-ssp` |
| `sar_slug` | SAR document slug | `acme-cloud-sar-2026` |
| `sap_slug` | SAP document slug | `acme-annual-assessment` |
| `poam_slug` | POA&M document slug | `acme-poam-q1-2026` |
| `profile_slug` | Profile document slug | `fedramp-high-baseline` |
| `cdef_slug` | CDEF document slug | `web-server-cdef` |
| `mapping_id` | Numeric mapping ID | `1` |
| `boundary_id` | Authorization boundary ID | `1` |
| `validation_id` | KSI validation ID | `1` |
| `indicator_id` | KSI indicator ID | `1` |

## Running as Test Suite

Use Postman's Collection Runner to execute all requests sequentially:

1. Select the SPARC API collection
2. Choose your environment
3. Set `auth_token` to a valid admin token
4. Click "Run SPARC API"

All GET requests should return 200. POST/PUT/DELETE require appropriate setup data.

## Updating the Collection

When new API endpoints are added to SPARC:

1. Check `GET /api/v1/available` for the updated endpoint list
2. Add the new request to the appropriate folder in the collection
3. Export and commit the updated collection JSON

## Related

- [API Documentation](/about/api) — in-app API reference
- [About SPARC](/about) — platform overview
- [Quick Start Guide](/about/quickstart) — getting started
