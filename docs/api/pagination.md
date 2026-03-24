# Pagination

## Overview

All list endpoints return paginated results using Pagy. Pagination metadata is included in every list response so clients can navigate through result sets.

## Query Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `page` | integer | 1 | The page number to retrieve |
| `items` | integer | 25 | Number of items per page (max 100) |

## Response Format

List responses include a `data` array and a `meta` object with pagination details:

```json
{
  "data": [
    { "id": 1, "name": "Acme Cloud Platform SSP", "slug": "acme-cloud-platform-ssp" },
    { "id": 2, "name": "Internal Tools SSP", "slug": "internal-tools-ssp" }
  ],
  "meta": {
    "page": 1,
    "pages": 5,
    "count": 112,
    "items": 25
  }
}
```

| Meta Field | Description |
|---|---|
| `page` | Current page number |
| `pages` | Total number of pages |
| `count` | Total number of records matching the query |
| `items` | Number of items returned per page |

## cURL Example

Fetch page 3 with 10 items per page:

```bash
curl -s "https://sparc.example.com/api/v1/ssp_documents?page=3&items=10" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" | jq .
```

## Navigation Tips

- Check `meta.pages` to determine the total number of pages before iterating.
- When `meta.page` equals `meta.pages`, you have reached the last page.
- Setting `items` above 100 will be clamped to 100.

**Iterating all pages (Bash example):**

```bash
page=1
while true; do
  response=$(curl -s "https://sparc.example.com/api/v1/ssp_documents?page=$page&items=50" \
    -H "Authorization: Bearer YOUR_API_TOKEN_HERE")

  echo "$response" | jq '.data[]'

  pages=$(echo "$response" | jq '.meta.pages')
  if [ "$page" -ge "$pages" ]; then
    break
  fi
  page=$((page + 1))
done
```

## Filtering

Most list endpoints accept query parameters to filter results. Filters are applied server-side before pagination.

Common filter parameters:

| Parameter | Example | Description |
|---|---|---|
| `status` | `?status=published` | Filter by document status |
| `name` | `?name=NIST` | Filter by name (partial match) |
| `catalog_id` | `?catalog_id=1` | Filter by associated catalog |

```bash
curl -s "https://sparc.example.com/api/v1/ssp_documents?status=published&name=NIST&page=1&items=25" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" | jq .
```

Refer to individual endpoint documentation for the full list of supported filters.
