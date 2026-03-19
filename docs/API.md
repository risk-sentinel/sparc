<!-- markdownlint-disable MD013 -->

# REST API

REST API under the `Api::V1::` namespace at `/api/v1/`.

## Authentication

API endpoints use **Bearer token** authentication. Generate an API token via the admin UI
(Admin > Users > [user] > API Tokens > Generate), then include it in the `Authorization` header:

```bash
curl -H "Authorization: Bearer sparc_abc123..." http://localhost:3000/api/v1/users
```

When authentication is disabled (no `SPARC_ENABLE_*` variables set), all API
endpoints are publicly accessible without tokens.

### Token Management

Tokens are managed through the admin UI:
- **Generate**: Admin > Users > [user] > API Tokens section > Generate
- **Revoke**: Admin > Users > [user] > API Tokens section > Revoke
- Tokens can optionally expire after 30, 60, or 90 days
- The plaintext token is shown **only once** at creation time

---

## Users API

All endpoints under `/api/v1/users`. Requires admin role unless accessing own record.

| Endpoint | Method | Auth | Description |
| -------- | ------ | ---- | ----------- |
| `/api/v1/users` | GET | Admin | List users (paginated). Filters: `email`, `name`, `status` |
| `/api/v1/users/:id` | GET | Admin or self | User details with roles |
| `/api/v1/users` | POST | Admin | Create user |
| `/api/v1/users/:id` | PATCH | Admin or self | Update user (self: limited to name/email) |
| `/api/v1/users/:id` | DELETE | Admin | Deactivate user (soft delete) |

### Examples

```bash
# List all users (admin)
curl -H "Authorization: Bearer $TOKEN" http://localhost:3000/api/v1/users

# Filter by status
curl -H "Authorization: Bearer $TOKEN" "http://localhost:3000/api/v1/users?status=active"

# Get user details
curl -H "Authorization: Bearer $TOKEN" http://localhost:3000/api/v1/users/1

# Create user
curl -X POST -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"user":{"email":"new@example.com","password":"securepass123","first_name":"Jane","last_name":"Doe"}}' \
  http://localhost:3000/api/v1/users

# Update user
curl -X PATCH -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"user":{"display_name":"Jane D."}}' \
  http://localhost:3000/api/v1/users/1

# Deactivate user
curl -X DELETE -H "Authorization: Bearer $TOKEN" http://localhost:3000/api/v1/users/1
```

### Response Format

```json
{
  "data": {
    "id": 1,
    "uuid": "abc-123-...",
    "email": "jane@example.com",
    "display_name": "Jane Doe",
    "first_name": "Jane",
    "last_name": "Doe",
    "status": "active",
    "admin": false,
    "created_at": "2026-03-19T00:00:00Z",
    "updated_at": "2026-03-19T00:00:00Z"
  }
}
```

Detailed view (GET /:id) also includes `last_sign_in_at`, `sign_in_count`, and `roles` array.

---

## Authorization Boundaries API

All endpoints under `/api/v1/authorization_boundaries`. Non-admins see only boundaries they have roles on.

| Endpoint | Method | Auth | Description |
| -------- | ------ | ---- | ----------- |
| `/api/v1/authorization_boundaries` | GET | Any authenticated | List boundaries. Filters: `name`, `status` |
| `/api/v1/authorization_boundaries/:id` | GET | Read access | Boundary details with artifact summary |
| `/api/v1/authorization_boundaries` | POST | Admin or write permission | Create boundary |
| `/api/v1/authorization_boundaries/:id` | PATCH | Admin or write permission | Update boundary |
| `/api/v1/authorization_boundaries/:id` | DELETE | Admin | Delete boundary |

### Examples

```bash
# List boundaries
curl -H "Authorization: Bearer $TOKEN" http://localhost:3000/api/v1/authorization_boundaries

# Get boundary details (uses slug)
curl -H "Authorization: Bearer $TOKEN" http://localhost:3000/api/v1/authorization_boundaries/acme-system

# Create boundary
curl -X POST -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"authorization_boundary":{"name":"ACME System","description":"Production system","status":"draft"}}' \
  http://localhost:3000/api/v1/authorization_boundaries

# Update boundary
curl -X PATCH -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"authorization_boundary":{"status":"active"}}' \
  http://localhost:3000/api/v1/authorization_boundaries/acme-system

# Delete boundary
curl -X DELETE -H "Authorization: Bearer $TOKEN" \
  http://localhost:3000/api/v1/authorization_boundaries/acme-system
```

---

## SSP Documents

| Endpoint | Method | Description |
| -------- | ------ | ----------- |
| `/api/v1/ssp_documents/convert` | POST | Upload and convert an SSP Excel file |
| `/api/v1/ssp_documents/:id/update_fields` | PUT | Update SSP control fields |
| `/api/v1/ssp_documents/:id/export` | GET | Export SSP as JSON |

## SAR Documents

| Endpoint | Method | Description |
| -------- | ------ | ----------- |
| `/api/v1/sar_documents/convert` | POST | Upload and convert a SAR Excel file |
| `/api/v1/sar_documents/:id/update_fields` | PUT | Update SAR control fields |
| `/api/v1/sar_documents/:id/export` | GET | Export SAR as JSON |

---

## Error Responses

All errors return JSON with consistent format:

| Status | Meaning |
| ------ | ------- |
| 401 | Missing or invalid API token |
| 403 | Insufficient permissions |
| 404 | Resource not found |
| 422 | Validation error (details in response body) |

```json
{
  "error": "Invalid or expired API token"
}
```

---

## Pagination

List endpoints return paginated results:

```json
{
  "data": [...],
  "meta": {
    "page": 1,
    "pages": 5,
    "count": 120,
    "items": 25
  }
}
```

Query parameters: `page` (default: 1).
