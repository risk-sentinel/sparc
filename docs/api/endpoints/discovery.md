# Discovery

The discovery endpoint returns an authorization-scoped inventory of all available API endpoints. Use it to dynamically determine which resources and HTTP methods the authenticated caller is permitted to access. All authenticated users (including service accounts) can call this endpoint. Admin users see the full endpoint registry; non-admin users see only endpoints matching their assigned permissions.

## Endpoints

| Method | Path | Description | Auth |
|--------|------|-------------|------|
| `GET` | `/api/v1/available` | List available endpoints scoped to caller permissions | Bearer token |

---

### GET /api/v1/available

Returns the full set of API endpoints the authenticated caller is authorized to use. Each entry includes the path, allowed HTTP methods, and a human-readable description. Endpoints where the caller has no permitted methods are omitted entirely.

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
      "description": "API discovery — lists available endpoints scoped to caller permissions"
    },
    {
      "path": "/api/v1/ssp_documents",
      "methods": ["GET", "POST"],
      "description": "System Security Plans"
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

> **Note:** The example above is truncated. The actual response includes all endpoints the caller can access. Admin users will see write methods on admin-only resources (e.g., `control_catalogs`, `users`). Non-admin users will only see endpoints and methods matching their role permissions.

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
