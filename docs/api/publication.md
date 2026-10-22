# Publishing through the API

A document is published by setting `lifecycle_status` to `"published"` on its
create or update request. Publishing makes the document read-only, so it is
held to the same rules as the web **Publish** button (owner, 2026-10-21):

| Document | `lifecycle_status: "published"` is accepted when |
|---|---|
| Control catalog, profile, CDEF (these have a review and approval workflow) | the document is **approved** (`POST .../submit_for_review`, then an approver's `POST .../approve`), **or** the caller may approve it: the type's approve permission (`catalogs.approve`, `profiles.approve`, `cdef.approve`), the `policy_manager` role, or an instance administrator |
| SSP, SAP, SAR, POA&M | the document passes the publication checks: a creator or prepared-by role, a contact party, responsible parties, and its required content. A document must exist before it is published, so these are refused on create |

Otherwise the request is refused with `403 Forbidden` and nothing changes:

```json
{
  "error": "Not published",
  "details": [
    "Publishing a control catalog needs its approval: submit it for review (POST .../submit_for_review) and have an approver approve it, or publish as a caller who may approve it (catalogs.approve or policy_manager)."
  ]
}
```

Each refusal is audited as `api_publication_refused`. A request that does not
set `"published"`, or one for a document that is already published, is not
affected.

`lifecycle_status` values: `started`, `in_progress` (shown as Draft) and
`published`.
