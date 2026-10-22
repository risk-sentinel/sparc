# Discovery

The discovery endpoint returns an authorization-scoped inventory of every API endpoint the caller may use. Use it to determine which resources and HTTP methods the authenticated caller is permitted to access. All authenticated users (including service accounts) can call this endpoint.

Since v1.17.2 (#1233) the inventory is built from the API's own route table, the same one token limits are enforced against, so it lists **every** route (before, a hand-kept list covered 45 of the API's paths). A route is listed when both hold:

- **the token's limits allow it.** A token limited to some resources sees only those, with the access level it holds. A token with no limits sees every resource its caller may use.
- **the caller's permissions allow it.** Each route is listed under the permission its controller checks, as recorded in `app/lib/api_route_permissions.rb` (catalog, profile, CDEF and mapping reads are listed under their read permission). Instance administrators see everything. A collection read of boundary-scoped documents (SSP, SAP, SAR, POA&M) is listed only to a caller holding that document type's read permission; without it the list would be empty.

## Endpoints

| Method | Path | Description | Auth |
|--------|------|-------------|------|
| `GET` | `/api/v1/available` | List available endpoints scoped to caller permissions | Bearer token |

---

### GET /api/v1/available

Returns the full set of API endpoints the authenticated caller is authorized to use. Each entry includes the path, allowed HTTP methods, a human-readable description, and the resource `group` (the name a token's `allowed_endpoints` uses, e.g. `ssp_documents`) with its `group_label`. Endpoints where the caller has no permitted methods are omitted entirely.

Paths are shown as the route declares them, except the 45 the earlier list carried, which keep the spelling it used (for example `/api/v1/ssp_documents/:slug`), so a consumer matching on them sees no change.

#### Path Parameters

None.

#### Query Parameters

None.

#### Response Body

```json
{
  "api_version": "v1",
  "system_id": "sparc-application",
  "authenticated_as": "jane.doe@acme-corp.com",
  "auth_mode": "token",
  "endpoints": [
    {
      "path": "/api/v1/available",
      "methods": ["GET"],
      "description": "API discovery — lists available endpoints scoped to caller permissions",
      "group": "available",
      "group_label": "Discovery"
    },
    {
      "path": "/api/v1/ssp_documents",
      "methods": ["GET", "POST"],
      "description": "System Security Plans",
      "group": "ssp_documents",
      "group_label": "System security plans (SSP)"
    },
    {
      "path": "/api/v1/ssp_documents/:slug",
      "methods": ["GET", "PUT", "DELETE"],
      "description": "Single SSP document"
    },
    {
      "path": "/api/v1/ssp_documents/convert",
      "methods": ["POST"],
      "description": "Parse uploaded file into SSP"
    },
    {
      "path": "/api/v1/ssp_documents/:slug/update_fields",
      "methods": ["PUT"],
      "description": "Bulk update SSP control fields"
    },
    {
      "path": "/api/v1/ssp_documents/:slug/export",
      "methods": ["GET"],
      "description": "Export SSP as JSON"
    },
    {
      "path": "/api/v1/sar_documents",
      "methods": ["GET", "POST"],
      "description": "Security Assessment Results"
    },
    {
      "path": "/api/v1/control_catalogs",
      "methods": ["GET"],
      "description": "NIST and custom control catalogs"
    },
    {
      "path": "/api/v1/profile_documents",
      "methods": ["GET", "POST"],
      "description": "Baselines and resolved profiles"
    }
  ]
}
```

> **Note:** The example above is truncated. The actual response includes all endpoints the caller can access. Admin users see every route, including administration (`users`, `roles`, `service_accounts`, ...). Non-admin users see only endpoints and methods matching their role permissions and their token's limits. Reference endpoints any authenticated caller may read, such as the guides and the federation identity, are listed for everyone. Catalog, profile, CDEF and mapping reads are listed for every caller too: reading the control library needs only a valid token. Their write methods still need the matching write key (`catalogs.write`, `profiles.write`, `cdef.write`, `mappings.write`), and the CDEF coverage analysis needs `cdef.read`.

#### Status Codes

| Status | Description |
|--------|-------------|
| `200 OK` | Endpoint inventory returned successfully |
| `401 Unauthorized` | Missing or invalid Bearer token |

#### cURL Example

```bash
curl -s \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  "https://sparc.example.com/api/v1/available" | jq .
```

---

## Common Errors

| Status | Body | Cause |
|--------|------|-------|
| `401 Unauthorized` | `{"error": "Unauthorized"}` | Bearer token is missing, expired, or invalid |
