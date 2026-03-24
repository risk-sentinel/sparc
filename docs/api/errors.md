# Error Handling

## Standard Error Format

All error responses return a JSON object with an `error` key. Validation errors include an additional `details` array.

**Simple error:**

```json
{
  "error": "Resource not found"
}
```

**Error with details:**

```json
{
  "error": "Validation failed",
  "details": [
    "Name can't be blank",
    "Slug has already been taken"
  ]
}
```

## Status Codes

| Code | Meaning | When |
|---|---|---|
| 200 | OK | Successful GET or PUT request |
| 201 | Created | Successful POST that created a resource |
| 400 | Bad Request | Missing a required parameter (e.g., no file attached for upload) |
| 401 | Unauthorized | Missing or invalid authentication token |
| 403 | Forbidden | Insufficient permissions, endpoint not allowed, or CIDR blocked |
| 404 | Not Found | Resource does not exist or has been soft-deleted |
| 422 | Unprocessable Entity | Validation failed on the submitted data |

## Example Error Responses

### 400 Bad Request

Returned when a required parameter is missing.

```json
{
  "error": "File is required. Attach an Excel (.xlsx) file to the request."
}
```

### 401 Unauthorized -- missing token

```json
{
  "error": "Missing authorization token"
}
```

### 401 Unauthorized -- invalid token

```json
{
  "error": "Invalid or expired token"
}
```

### 403 Forbidden -- endpoint not allowed

```json
{
  "error": "Endpoint not allowed for this service account"
}
```

### 403 Forbidden -- CIDR blocked

```json
{
  "error": "Request origin not in allowed CIDR range"
}
```

### 404 Not Found

```json
{
  "error": "Resource not found"
}
```

### 422 Unprocessable Entity

Returned when submitted data fails model validations. The `details` array lists each validation error.

```json
{
  "error": "Validation failed",
  "details": [
    "Name can't be blank",
    "Slug has already been taken",
    "Profile document must exist"
  ]
}
```

## Validation Errors

Endpoints that create or update resources validate input against model rules. When validation fails, the response includes:

- **Status**: `422 Unprocessable Entity`
- **Body**: JSON with `error` set to `"Validation failed"` and a `details` array containing one string per validation error.

Correct all listed issues and retry the request.

## Rate Limiting

The SPARC API does not currently enforce rate limits. This may change in a future release. If rate limiting is added, the API will return `429 Too Many Requests` with a `Retry-After` header.
