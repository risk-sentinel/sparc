# SPARC API Introduction

The SPARC REST API provides programmatic access to compliance documentation management. All endpoints live under `/api/v1/`, return JSON responses, and require Bearer token authentication.

## Base URL

The base URL depends on your deployment environment. It is configurable per installation.

| Environment | Base URL |
|---|---|
| Production | `https://sparc.example.com/api/v1` |
| Local (Docker) | `http://localhost:3000/api/v1` |
| Local (Rails) | `http://localhost:3000/api/v1` |

## Quick Start

**1. Obtain an API token**

Generate a token via the Admin UI or Rails console. See [Authentication](authentication.md) for details.

**2. Set the Authorization header**

```
Authorization: Bearer YOUR_API_TOKEN_HERE
```

**3. Make a request**

```bash
curl -s https://sparc.example.com/api/v1/available \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE"
```

## End-to-End Workflow

The following walkthrough demonstrates a realistic compliance workflow using cURL. Replace `YOUR_API_TOKEN_HERE` with your actual token.

### 1. Discover available endpoints

```bash
curl -s https://sparc.example.com/api/v1/available \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" | jq .
```

### 2. List control catalogs

```bash
curl -s https://sparc.example.com/api/v1/control_catalogs \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" | jq .
```

### 3. Create a profile document

```bash
curl -s -X POST https://sparc.example.com/api/v1/profile_documents \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "profile_document": {
      "name": "Acme Cloud HIGH Baseline",
      "description": "HIGH baseline profile for Acme Cloud Platform",
      "control_catalog_id": 1,
      "baseline": "HIGH"
    }
  }' | jq .
```

### 4. Create an SSP document

```bash
curl -s -X POST https://sparc.example.com/api/v1/ssp_documents \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "ssp_document": {
      "name": "Acme Cloud Platform SSP",
      "slug": "acme-cloud-platform-ssp",
      "description": "System Security Plan for the Acme Cloud Platform",
      "profile_document_id": 1
    }
  }' | jq .
```

### 5. Get SSP details

```bash
curl -s https://sparc.example.com/api/v1/ssp_documents/acme-cloud-platform-ssp \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" | jq .
```

### 6. Export SSP as OSCAL JSON

```bash
curl -s https://sparc.example.com/api/v1/ssp_documents/acme-cloud-platform-ssp/export \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -o acme-cloud-platform-ssp-oscal.json
```

### 7. Create a SAR document

```bash
curl -s -X POST https://sparc.example.com/api/v1/sar_documents \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "sar_document": {
      "name": "Acme Cloud Platform SAR Q1 2026",
      "description": "Security Assessment Results for Q1 2026",
      "ssp_document_id": 1
    }
  }' | jq .
```

### 8. Create a POA&M document

```bash
curl -s -X POST https://sparc.example.com/api/v1/poam_documents \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "poam_document": {
      "name": "Acme Cloud Platform POA&M",
      "description": "Plan of Action and Milestones for Acme Cloud Platform",
      "sar_document_id": 1
    }
  }' | jq .
```

### 9. Clean up

```bash
curl -s -X DELETE https://sparc.example.com/api/v1/ssp_documents/acme-cloud-platform-ssp \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" | jq .
```

## UI Automation: Bearer-Token to Session Cookie Bridge (#573)

Test runners (Playwright, Cypress, headless Chromium) often need to
drive the SPARC UI as an authenticated user. The bridge endpoint
exchanges a SPARC API token for a Rails session cookie that
subsequent web requests will accept:

```
POST /api/v1/sessions/from_token
Authorization: Bearer sparc_sa_<your_service_account_token>
```

Response: `204 No Content` with a `Set-Cookie` header containing the
Rails session cookie. Attach that cookie to subsequent web requests
to drive the UI as the bridged user.

### Playwright (Python) example

```python
import os
import requests
from playwright.sync_api import sync_playwright

SPARC_URL = "https://sparc.example.com"
TOKEN     = os.environ["SPARC_TEST_ADMIN_TOKEN"]

# Bridge: token → session cookie
resp = requests.post(
    f"{SPARC_URL}/api/v1/sessions/from_token",
    headers={"Authorization": f"Bearer {TOKEN}"},
)
assert resp.status_code == 204
session_cookie = resp.cookies.get_dict()

with sync_playwright() as p:
    browser = p.chromium.launch()
    context = browser.new_context()
    # Hand Playwright the bridged session cookie
    for name, value in session_cookie.items():
        context.add_cookies([{"name": name, "value": value,
                              "url": SPARC_URL}])
    page = context.new_page()
    page.goto(f"{SPARC_URL}/admin/users")  # already authenticated
    ...
```

### Security notes

- The bridge requires a valid Bearer token; revoked / expired tokens
  return `401` with no `Set-Cookie`.
- Bridged sessions inherit `SPARC_SESSION_TIMEOUT_MINUTES` — no
  longer-lived than form-login sessions.
- Every bridge attempt is audit-logged (`api_session_bridged` on
  success, `api_session_bridge_failed` on failure) and visible in
  `/admin/audit_logs` under the **Authentication** category.
- The endpoint shares a dedicated Rack::Attack throttle bucket
  (`api/sessions_from_token/min/ip`) keyed on client IP, distinct
  from general API write rate limits.
- A non-admin SA bridges into a non-admin session. Admin-or-not
  follows the user record.

## Further Reading

- [Authentication](authentication.md) -- token types, auth modes, and generating tokens
- [Error Handling](errors.md) -- status codes, error format, and common errors
- [Pagination](pagination.md) -- paginating and filtering list responses
- [Endpoint Reference](endpoints/) -- detailed documentation for each resource
