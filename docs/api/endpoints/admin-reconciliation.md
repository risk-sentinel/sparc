# Catalog Reconciliation Report (admin)

Instance-wide catalog-lineage reporting (#911, layer 2 of 3).

Each document carries its own `reconciliation` object answering *"what is wrong
with THIS document"*. This endpoint answers the other question — **"how much of
this instance is affected"** — which is what an operator needs before a catalog
upgrade lands on their users.

Related: [Control Catalogs](control-catalogs.md) ·
[Profile Documents](profile-documents.md) · [CDEF Documents](cdef-documents.md)

## Authentication & authorization

Bearer token, **admin only**. It enumerates every document in the instance
regardless of who can see them, so it cannot be boundary-scoped without
answering a different question. A non-admin gets `403`; an unauthenticated
caller gets `401`.

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/admin/reconciliation` | Instance-wide lineage report: totals, severity split, per-type breakdown, and the affected documents |

## Response

```json
{
  "data": {
    "total": 71,
    "blocking": 69,
    "advisory": 2,
    "by_type": [
      { "type": "Ssp documents",  "affected": 2,  "total": 3 },
      { "type": "Cdef documents", "affected": 69, "total": 232 }
    ],
    "documents": [
      { "slug": "aws-apigateway-oscal-1-2-1", "status": "unresolved", "…": "…" }
    ]
  }
}
```

| Field | Meaning |
|---|---|
| `total` | affected documents across the instance |
| `blocking` | those whose lineage problem prevents a clean upgrade |
| `advisory` | those worth knowing about that do not block |
| `by_type` | per document type: `affected` out of `total` held |
| `documents` | the affected documents themselves, one row each |

### Guarantees worth relying on

These hold, and are asserted by the contract suite:

- `blocking + advisory == total` — every affected document is one or the other,
  so the headline can be split into urgent and not without anything falling
  between the two
- `documents.length == total` — the count and the list it summarises describe
  the same set
- the `affected` values in `by_type` sum to `total`
- no type reports more `affected` than it holds

A summary whose parts do not add up is worse than none, because it is a number
someone will plan an upgrade around.

## Notes

The report is computed on request and reflects the instance at that moment. It
is a read: nothing is modified, and no lineage is repaired by calling it.
