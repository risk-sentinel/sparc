# SSP Components

The components of a System Security Plan — the software, hardware, services,
policies and procedures the system is built from, and the third-party
validations that attest to them.

Nested under an SSP: a component belongs to exactly one plan, and the
authorization question is always about that plan.

## Why this endpoint exists

Until it landed, SSP components had **no API surface at all**. They could be
created, edited and deleted only through the enrichment screen, which made the
web UI the only way to perform those mutations. The gap surfaced while adding
validation modeling (#998): "this module is FIPS 140-2 validated, certificate
#4282" is exactly the assertion a pipeline needs to write, and there was no way
to write it except by hand in a browser.

| | |
|---|---|
| **Base path** | `/api/v1/ssp_documents/:ssp_document_id/components` |
| **Auth** | Bearer token |
| **Read** | `ssp.read` on the SSP's authorization boundary |
| **Write** | `ssp.write` on the SSP's authorization boundary |

`:ssp_document_id` is the SSP's slug. A component is addressed by its **OSCAL
uuid** or its numeric id — the uuid is what an exported document carries, the id
is what a UI-shaped caller holds.

## Endpoints

| Method | Path | Description |
|---|---|---|
| `GET` | `.../components` | List this SSP's components (paginated) |
| `GET` | `.../components/:id` | One component, with its validation pairing |
| `POST` | `.../components` | Create |
| `PATCH` / `PUT` | `.../components/:id` | Update |
| `DELETE` | `.../components/:id` | Delete |

`GET .../components` accepts `?component_type=` to filter, plus the usual
`page` / `per_page`.

---

## GET List Components

```bash
curl "https://sparc.example.com/api/v1/ssp_documents/acme-hr-portal/components" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE"
```

```json
{
  "data": [
    {
      "id": 41,
      "uuid": "b0c1d2e3-4f56-4789-a0b1-c2d3e4f56789",
      "component_type": "software",
      "title": "Acme Crypto Module",
      "description": "The validated cryptographic module.",
      "purpose": null,
      "status_state": "operational",
      "cdef_document_id": null,
      "created_at": "2026-08-19T14:02:11Z",
      "updated_at": "2026-08-19T14:02:11Z"
    }
  ],
  "meta": { "page": 1, "pages": 1, "count": 1, "items": 25 }
}
```

---

## POST Create a Component

**Request body**

```json
{
  "ssp_component": {
    "component_type": "software",
    "title": "Acme Crypto Module",
    "description": "The validated cryptographic module.",
    "status_state": "operational"
  }
}
```

`component_type`, `title` and `description` are required. `uuid` is minted when
you do not supply one. Allowed types are the OSCAL `system-component` types:
`this-system`, `software`, `hardware`, `service`, `policy`,
`process-procedure`, `plan`, `guidance`, `standard`, `validation`.

Returns `201` with the created component.

---

## Recording a product validation (#998)

OSCAL models a third-party validation as a **pair** of components: the product,
and a separate component of type `validation` carrying the certificate, joined
by a link from the product to the validation. The certificate is an assertion
*about* the product, made by someone else, so it gets its own subject.

Create the product first, then the validation that points at it:

```bash
curl -X POST "https://sparc.example.com/api/v1/ssp_documents/acme-hr-portal/components" \
  -H "Authorization: Bearer YOUR_API_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "ssp_component": {
      "component_type": "validation",
      "title": "FIPS 140-2 certificate #4282",
      "description": "NIST CMVP validation of the Acme Crypto Module.",
      "validation_type": "fips-140-2",
      "validation_reference": "4282",
      "validation_details_href": "https://csrc.nist.gov/projects/cryptographic-module-validation-program/certificate/4282",
      "validates_component_id": 41
    }
  }'
```

A validation component reports a `validation` block; a component of any other
type does not carry the key at all. That distinction is deliberate — an empty
block means *"this validation asserts nothing yet"*, and an absent key means
*"this is not a validation"*. The two are different states and a missing key
would not tell them apart.

```json
{
  "data": {
    "id": 42,
    "uuid": "c1d2e3f4-5678-4901-b2c3-d4e5f6789012",
    "component_type": "validation",
    "title": "FIPS 140-2 certificate #4282",
    "validation": {
      "validation_type": "fips-140-2",
      "validation_reference": "4282",
      "validation_details_href": "https://csrc.nist.gov/…/certificate/4282",
      "validates_component_id": 41,
      "validates_component_uuid": "b0c1d2e3-4f56-4789-a0b1-c2d3e4f56789"
    }
  }
}
```

`GET .../components/:id` on the **product** reports the other side of the pair
as `validated_by`, so the claim can be followed in either direction.

On export the validation component carries `validation-type` and
`validation-reference` props and a `validation-details` link, and the product
carries a `validation` link back to it. Both survive a re-import.

**Refused, with 422:**

- a `validation_type` / `validation_reference` / `validation_details_href` on a
  component that is not of type `validation` — the fields mean nothing there,
  and storing them somewhere no exporter reads would be support in appearance
  only
- a `validates_component_id` naming the component itself
- a `validates_component_id` naming a component in another SSP

**Component definitions (CDEFs) support this only partly.** A CDEF exports
exactly one component, so it cannot carry a pair. See
[component-definitions.md](component-definitions.md).

---

## PATCH Update a Component

```json
{ "ssp_component": { "title": "Acme Crypto Module v2" } }
```

Only the keys you send are changed.

---

## DELETE a Component

Returns `204` with no body.

The `this-system` component is **refused with 422**: OSCAL requires the SSP to
describe the system itself, and deleting it would leave a document that cannot
be exported with no obvious way back. Change its title or description instead.

---

## Status Codes

| Code | Description |
|---|---|
| `200` | Read or update succeeded |
| `201` | Component created |
| `204` | Component deleted |
| `401` | Unauthorized -- missing or invalid token |
| `403` | Forbidden -- the token's user lacks `ssp.read` / `ssp.write` on the SSP's boundary |
| `404` | SSP or component not found, or the component belongs to a different SSP |
| `422` | Validation failed -- a missing required field, a validation claim on a non-validation component, a pairing pointing outside this SSP, or an attempt to delete `this-system` |

## Audit

Every mutation records an `AuditEvent`: `ssp_component_created`,
`ssp_component_updated`, `ssp_component_deleted`.
