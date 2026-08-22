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
| 422 | Unprocessable Entity | Validation failed on the submitted data, or the body carried a field the endpoint does not accept |

## Example Error Responses

### 400 Bad Request

Returned when a required parameter is missing.

```json
{
  "error": "File is required. Attach a document file to the request."
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

### 422 Unprocessable Entity — unrecognized fields

Returned when a request body carries a field the endpoint does not accept.
**Nothing is written.** The response names each offending field and lists what
the endpoint does accept, so a misspelling can be corrected rather than guessed
at.

```json
{
  "error": "The request body contained fields this endpoint does not accept. Nothing was changed.",
  "details": [
    "Unrecognized field: not_a_real_column",
    "Unrecognized field: descriptionn"
  ],
  "expected": ["name", "description", "version", "source", "oscal_version", "lifecycle_status"]
}
```

Until [#995](https://github.com/risk-sentinel/sparc/issues/995) an unrecognized
field was **discarded in silence** and the request returned `200` with the
resource unchanged, so "nothing to do" and "I did not understand you" arrived as
the same response. That is what let
[#994](https://github.com/risk-sentinel/sparc/issues/994) answer
`200 {"status": "updated"}` to a body it had never parsed.

Two consequences worth knowing before you send a request:

- **A field the server owns is refused, not ignored.** Evidence provenance
  (`collected_at`, `collected_by`, `collected_by_user_id`) and an attestation's
  `attester_name` are stamped from the authenticated account. Supplying them
  used to be accepted and dropped; it now fails, so a caller cannot believe a
  backdated timestamp or a substituted name took effect. Omit them and the
  server fills them in.
- **`id` is refused like any other field.** Echoing a resource you read back is
  not supported — `created_at`, `updated_at` and `slug` are refused too.

## Validation Errors

Endpoints that create or update resources validate input against model rules. When validation fails, the response includes:

- **Status**: `422 Unprocessable Entity`
- **Body**: JSON with `error` set to `"Validation failed"` and a `details` array containing one string per validation error.

Correct all listed issues and retry the request.

## Rate Limiting

The SPARC API does not currently enforce rate limits. This may change in a future release. If rate limiting is added, the API will return `429 Too Many Requests` with a `Retry-After` header.
