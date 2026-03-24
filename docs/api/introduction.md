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

## Further Reading

- [Authentication](authentication.md) -- token types, auth modes, and generating tokens
- [Error Handling](errors.md) -- status codes, error format, and common errors
- [Pagination](pagination.md) -- paginating and filtering list responses
- [Endpoint Reference](endpoints/) -- detailed documentation for each resource
