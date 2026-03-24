# Users API

Manage user accounts. All operations require admin privileges except self-update, which allows authenticated users to modify their own profile fields.

## Base URL

```
https://sparc.example.com/api/v1/users
```

## Authentication

All endpoints require a valid Bearer token.

```
Authorization: Bearer YOUR_API_TOKEN_HERE
```

## Authorization

| Operation | Required Role |
|-----------|---------------|
| List, Show, Create, Delete | Admin only |
| Update (other users) | Admin only |
| Update (self) | Any authenticated user |

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/users` | List all users (admin) |
| `GET` | `/api/v1/users/:id` | Show a single user (admin) |
| `POST` | `/api/v1/users` | Create a new user (admin) |
| `PUT` | `/api/v1/users/:id` | Update a user |
| `DELETE` | `/api/v1/users/:id` | Delete a user (admin) |

---

### GET List All Users (Admin Only)

Returns a paginated list of user accounts.

**Query Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `page` | integer | No | Page number (default: `1`) |
| `items` | integer | No | Items per page (default: `25`) |
| `email` | string | No | Filter by email (partial match) |
| `name` | string | No | Filter by first or last name (partial match) |
| `status` | string | No | Filter by status (e.g., `active`, `inactive`, `locked`) |

**Example Request**

```bash
curl -X GET "https://sparc.example.com/api/v1/users?status=active&page=1&items=25" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Accept: application/json"
```

**Response Body**

```json
{
  "data": [
    {
      "id": 1,
      "email": "admin@acme-corp.com",
      "first_name": "Jane",
      "last_name": "Smith",
      "display_name": "Jane Smith",
      "admin": true,
      "status": "active",
      "created_at": "2026-01-01T08:00:00Z",
      "updated_at": "2026-03-20T16:00:00Z"
    },
    {
      "id": 2,
      "email": "bob.jones@acme-corp.com",
      "first_name": "Bob",
      "last_name": "Jones",
      "display_name": "Bob Jones",
      "admin": false,
      "status": "active",
      "created_at": "2026-02-10T09:00:00Z",
      "updated_at": "2026-03-15T12:00:00Z"
    }
  ],
  "meta": {
    "page": 1,
    "pages": 1,
    "count": 2,
    "items": 25
  }
}
```

**Status Codes**

| Code | Description |
|------|-------------|
| `200` | Users returned successfully |
| `401` | Unauthorized -- missing or invalid token |
| `403` | Forbidden -- admin privileges required |

---

### GET Show a Single User (Admin Only)

Returns a single user account.

**Path Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | integer | Yes | Numeric user ID |

**Example Request**

```bash
curl -X GET "https://sparc.example.com/api/v1/users/1" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Accept: application/json"
```

**Response Body**

```json
{
  "data": {
    "id": 1,
    "email": "admin@acme-corp.com",
    "first_name": "Jane",
    "last_name": "Smith",
    "display_name": "Jane Smith",
    "admin": true,
    "status": "active",
    "created_at": "2026-01-01T08:00:00Z",
    "updated_at": "2026-03-20T16:00:00Z"
  }
}
```

**Status Codes**

| Code | Description |
|------|-------------|
| `200` | User returned successfully |
| `401` | Unauthorized -- missing or invalid token |
| `403` | Forbidden -- admin privileges required |
| `404` | User not found |

---

### POST Create a New User (Admin Only)

Create a new user account.

**Request Body**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `email` | string | Yes | User email address (must be unique) |
| `password` | string | Yes | Password (minimum 12 characters) |
| `password_confirmation` | string | Yes | Must match password |
| `first_name` | string | Yes | First name |
| `last_name` | string | Yes | Last name |
| `display_name` | string | No | Display name (defaults to first + last name) |
| `admin` | boolean | No | Admin privileges (default: `false`) |

**Example Request**

```bash
curl -X POST "https://sparc.example.com/api/v1/users" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "user": {
      "email": "alice.chen@acme-corp.com",
      "password": "SecureP@ssw0rd!2026",
      "password_confirmation": "SecureP@ssw0rd!2026",
      "first_name": "Alice",
      "last_name": "Chen",
      "display_name": "Alice Chen",
      "admin": false
    }
  }'
```

**Response Body**

```json
{
  "data": {
    "id": 3,
    "email": "alice.chen@acme-corp.com",
    "first_name": "Alice",
    "last_name": "Chen",
    "display_name": "Alice Chen",
    "admin": false,
    "status": "active",
    "created_at": "2026-03-23T12:00:00Z",
    "updated_at": "2026-03-23T12:00:00Z"
  }
}
```

**Status Codes**

| Code | Description |
|------|-------------|
| `201` | User created successfully |
| `401` | Unauthorized -- missing or invalid token |
| `403` | Forbidden -- admin privileges required |
| `422` | Validation error -- check response body for details |

---

### PUT Update a User

Update a user account. Admins can update any user with the full set of admin fields. Non-admin users can only update their own profile with the self-update fields.

**Path Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | integer | Yes | Numeric user ID |

**Admin Update Fields**

| Field | Type | Description |
|-------|------|-------------|
| `email` | string | User email address |
| `first_name` | string | First name |
| `last_name` | string | Last name |
| `display_name` | string | Display name |
| `admin` | boolean | Admin privileges |
| `status` | string | Account status: `active`, `inactive`, `locked` |

**Self-Update Fields** (non-admin updating own profile)

| Field | Type | Description |
|-------|------|-------------|
| `first_name` | string | First name |
| `last_name` | string | Last name |
| `display_name` | string | Display name |
| `email` | string | Email address |

**Example Request (Admin)**

```bash
curl -X PUT "https://sparc.example.com/api/v1/users/2" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "user": {
      "admin": true,
      "status": "active"
    }
  }'
```

**Example Request (Self-Update)**

```bash
curl -X PUT "https://sparc.example.com/api/v1/users/3" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "user": {
      "display_name": "Alice C.",
      "email": "alice.c@acme-corp.com"
    }
  }'
```

**Response Body**

```json
{
  "data": {
    "id": 2,
    "email": "bob.jones@acme-corp.com",
    "first_name": "Bob",
    "last_name": "Jones",
    "display_name": "Bob Jones",
    "admin": true,
    "status": "active",
    "updated_at": "2026-03-23T14:00:00Z"
  }
}
```

**Status Codes**

| Code | Description |
|------|-------------|
| `200` | User updated successfully |
| `401` | Unauthorized -- missing or invalid token |
| `403` | Forbidden -- cannot update other users without admin privileges |
| `404` | User not found |
| `422` | Validation error -- check response body for details |

---

### DELETE Delete a User (Admin Only)

Delete a user account.

**Path Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | integer | Yes | Numeric user ID |

**Example Request**

```bash
curl -X DELETE "https://sparc.example.com/api/v1/users/3" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE"
```

**Response Body**

```json
{
  "data": {
    "id": 3,
    "email": "alice.chen@acme-corp.com",
    "deleted": true
  }
}
```

**Status Codes**

| Code | Description |
|------|-------------|
| `200` | User deleted successfully |
| `401` | Unauthorized -- missing or invalid token |
| `403` | Forbidden -- admin privileges required |
| `404` | User not found |

---

## Common Errors

| Code | Error | Description |
|------|-------|-------------|
| `401` | `Unauthorized` | Missing or invalid Bearer token |
| `403` | `Forbidden` | Admin privileges required, or attempting to update another user's profile |
| `404` | `Not Found` | User does not exist |
| `422` | `Unprocessable Entity` | Validation failed -- duplicate email, password too short, or missing required fields |
| `500` | `Internal Server Error` | Unexpected server error -- contact your administrator |
