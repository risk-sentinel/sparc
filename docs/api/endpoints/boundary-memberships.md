# Boundary Memberships API

Manage the personnel roster on an authorization boundary — the people recorded against a boundary with an RMF role (Authorizing Official, ISSO, Assessor, and so on) for the ATO package. All endpoints are nested under a specific authorization boundary.

Added in #875. Before that, the roster could only be built through the web UI, so nothing automated could provision the personnel on a package.

> **Two role systems.** These are the *legacy* string-role memberships shown in the boundary's Personnel Roster. They are distinct from the canonical `Role` catalog granted via `user_roles`, which governs SPARC *permissions*. A boundary's roster view merges both. A membership records accountability for the package; it does not by itself grant access to SPARC.

## Base URL

```
https://sparc.example.com/api/v1/authorization_boundaries/:authorization_boundary_id/memberships
```

The boundary may be addressed by numeric id or by slug.

## Authentication

All endpoints require a valid Bearer token.

```
Authorization: Bearer YOUR_API_TOKEN_HERE
```

## Authorization

Read endpoints require read access to the parent boundary; every mutation requires `authorization_boundaries.write`. Instance admins bypass both. Memberships are scoped to the boundary in the path — an id belonging to a different boundary returns `404`, not the record.

Every mutation is audited (`api_authorization_boundary_membership_created` / `_updated` / `_deleted`).

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `…/memberships` | List the boundary's roster |
| `GET` | `…/memberships/roles` | The role vocabulary this instance accepts |
| `GET` | `…/memberships/:id` | Show a single membership |
| `POST` | `…/memberships` | Add a person to the roster |
| `PATCH`/`PUT` | `…/memberships/:id` | Update a membership |
| `DELETE` | `…/memberships/:id` | Remove a person from the roster |

---

### Roles are configurable — do not hardcode them

The role vocabulary is set per deployment via `SPARC_AUTH_BOUNDARY_ROLES` ([Environment Variables](../../ENVIRONMENT_VARIABLES.md)). An instance may narrow the seven built-ins or add roles of its own, so **a client that hardcodes the built-in keys will be wrong on a configured instance**. Call `GET …/memberships/roles` and use what it returns.

Submitted roles are resolved before validation, so spelling differences do not create duplicate roles:

| You send | Stored as |
|---|---|
| `isso`, `ISSO`, `Isso` | `isso` |
| `Authorizing Official (AO)`, `AO` | `authorizing_official` |
| `Team Member` | `project_member` |
| `Assessor / 3PAO`, `3PAO` | `assessor` |
| `Security Champion` *(when configured)* | `security_champion` |

A value that resolves to nothing acceptable returns `422`.

---

### GET Role Vocabulary

```bash
curl -X GET "https://sparc.example.com/api/v1/authorization_boundaries/1/memberships/roles" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Accept: application/json"
```

**Response** `200 OK`

```json
{
  "data": {
    "available": [
      { "value": "authorizing_official", "label": "Authorizing Official (AO)" },
      { "value": "system_owner", "label": "System Owner (SO/ISO)" },
      { "value": "isso", "label": "ISSO" }
    ],
    "acceptable": [
      "authorizing_official", "system_owner", "ciso", "isso",
      "project_member", "assessor", "view_only"
    ]
  }
}
```

`available` is what to offer for a **new** assignment. `acceptable` additionally includes the built-in roles, which remain valid on records that already hold them even when a deployment narrows the offered list — so narrowing configuration never strands an existing member.

---

### GET List Roster

**Query Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `page` | integer | No | Page number (default: `1`) |
| `items` | integer | No | Items per page (default: `25`) |
| `role` | string | No | Filter by role. Resolved the same way a write is, so `ISSO` and `isso` match identically |

```bash
curl -X GET "https://sparc.example.com/api/v1/authorization_boundaries/1/memberships?role=isso" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE"
```

**Response** `200 OK`

```json
{
  "data": [
    {
      "id": 42,
      "user_name": "Dana Reed",
      "user_email": "dana@example.gov",
      "user_id": 7,
      "role": "isso",
      "role_label": "ISSO",
      "authorization_boundary_id": 1,
      "created_at": "2026-08-02T12:00:00Z",
      "updated_at": "2026-08-02T12:00:00Z"
    }
  ],
  "meta": { "page": 1, "items": 25, "count": 1, "pages": 1 }
}
```

`user_id` is populated when the roster entry has been matched to a SPARC user account by email; it is `null` for people who have no account.

---

### POST Add a Member

**Body Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `user_name` | string | **Yes** | The person's name as it appears on the package roster |
| `user_email` | string | No | Used to match the entry to a SPARC user account |
| `role` | string | **Yes** | Any value accepted by the vocabulary above |

```bash
curl -X POST "https://sparc.example.com/api/v1/authorization_boundaries/1/memberships" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{"authorization_boundary_membership": {"user_name": "Dana Reed", "user_email": "dana@example.gov", "role": "ISSO"}}'
```

**Response** `201 Created` — the created membership, with `role` resolved to its canonical value.

**Errors**

| Status | Cause |
|--------|-------|
| `401` | Missing or invalid Bearer token |
| `403` | Caller lacks `authorization_boundaries.write` |
| `404` | Boundary not found |
| `422` | Missing `user_name`, or a role outside the vocabulary (`Role is not an available role`) |

---

### PATCH Update a Member

Accepts the same parameters as create; send only what changes.

```bash
curl -X PATCH "https://sparc.example.com/api/v1/authorization_boundaries/1/memberships/42" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{"authorization_boundary_membership": {"role": "assessor"}}'
```

**Response** `200 OK`

Updating a field *other than* `role` succeeds even when the member holds a role the deployment has since retired from `SPARC_AUTH_BOUNDARY_ROLES` — the vocabulary is enforced on the value being set, not re-litigated on every save. Changing such a member's `role` still requires a currently acceptable value.

---

### DELETE Remove a Member

```bash
curl -X DELETE "https://sparc.example.com/api/v1/authorization_boundaries/1/memberships/42" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE"
```

**Response** `200 OK`

```json
{ "data": { "id": 42, "deleted": true } }
```
