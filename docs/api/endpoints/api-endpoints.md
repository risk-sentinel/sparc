# API Endpoint Catalog

What an API token's `allowed_endpoints` may name.

Added in [#1176](https://github.com/risk-sentinel/sparc/issues/1176). A token
used to be limited by typing path patterns, which a person had to guess and
which said nothing about reading versus changing. Limits are now chosen per
resource, with Read and Write separately. This endpoint lists the choices from
the same definition the token forms show and the authentication check
enforces (`ApiEndpointCatalog`).

## Base URL

```
https://sparc.example.com/api/v1/api_endpoints
```

## Authorization

**Instance admin only**, like issuing a token.

## Endpoints

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/v1/api_endpoints` | Every resource group, its access levels, and the entries to send |

### GET /api/v1/api_endpoints

```json
{
  "data": [
    {
      "group": "ssp_documents",
      "label": "System security plans (SSP)",
      "access_levels": ["read", "write"],
      "entries": ["ssp_documents:read", "ssp_documents:write"]
    },
    {
      "group": "oscal",
      "label": "OSCAL translations",
      "access_levels": ["read"],
      "entries": ["oscal:read"]
    }
  ],
  "meta": {
    "all_endpoints": "*",
    "note": "…"
  }
}
```

## How a request is classified

A **group** is the first path segment after `/api/v1`, so a nested resource
sits with its parent: an SSP's components are in `ssp_documents`.

**Read or Write is a property of the route**, not of the HTTP verb a caller
might guess:

| Route | Access |
|---|---|
| `GET`, `HEAD` | Read |
| `POST` that only computes: field-import previews, the bulk converter preview, baseline-parameter import preview, CDEF coverage analysis, the entitlement-sync preview, and the four HDF/OSCAL translations | Read |
| Every other `POST`, and every `PUT`, `PATCH`, `DELETE` | Write |

The SSP and SAR `convert` endpoints are **Write**: despite the name, both
create a document.

A group offers only the levels its routes have, so a read-only group such as
`oscal` has no `:write` entry. Sending one is refused.

## Entries

| Entry | Meaning |
|---|---|
| `"*"` | Every endpoint. Stored as an empty list, which has always meant unrestricted |
| `"<group>:read"`, `"<group>:write"` | That access level on that group |
| `"/api/v1/…"` | A path pattern as used before #1176 (`x*` is a prefix, anything else exact). Grants Read **and** Write on the paths it matches, so no existing token narrows on upgrade. A new pattern that matches no route is refused |

A request outside a token's limits gets `403` with
`"error": "Token is not authorized for this endpoint"`.

## Status Codes

| Status | Description |
|---|---|
| `200 OK` | The catalog |
| `401 Unauthorized` | Missing or invalid Bearer token |
| `403 Forbidden` | Caller is not an instance admin |

## NIST 800-53 Controls

- **AC-3** Access Enforcement — one definition of a token's reach, read by issuance and enforcement alike
- **AC-6** Least Privilege — per-resource Read and Write
