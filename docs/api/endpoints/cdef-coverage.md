# CDEF Coverage

Derive a boundary's deployed service inventory from its Terraform, and report
which OSCAL Component Definitions it needs (#904).

Answers the question a team standing up a new boundary cannot otherwise answer
without reading their Terraform by eye: *which CDEFs do we need?*

## Your Terraform is not stored

Terraform state contains plaintext secrets — database passwords, private keys,
session tokens, account identifiers — in `resources[].instances[].attributes`.

This endpoint reads three fields per resource: whether it is `managed`, its
`type`, and how many instances exist. A plan is read for `mode`, `type` and
`change.actions`. Resource **attributes are never read**.

Uploads are parsed in the request and discarded. No Active Storage blob is
created and nothing is attached to a record. When you save a run, what is
written is the derived census — service keys, Terraform resource **type** names
(`aws_db_instance`), counts and verdicts — plus each file's name and SHA-256
checksum. A type name identifies no account, region or secret.

## Verdicts

| verdict | meaning | what to do |
|---|---|---|
| `adopt` | Deployed, and AWS Labs publishes a CDEF | Vendor theirs |
| `keep_custom` | Deployed, only your CDEF covers it | Keep the overlay |
| `needs_custom` | Deployed, no CDEF anywhere | **Author one** |
| `stale_custom` | You maintain a CDEF nothing deploys | Retire or verify |

Only *custom* CDEFs can go stale. An unused AWS Labs CDEF arrived from upstream
and costs nothing to keep.

A finding with `"inferred": true` had its service name derived from the
Terraform resource type (`azurerm_storage_account` → `azurerm:storage`) because
no mapping rule matched. Inferred keys are namespaced with a colon so they can
never be confused with a known service. They are reported as gaps rather than
omitted — a boundary on an unmapped provider must not read as fully covered.

---

### POST Analyze

```
POST /api/v1/cdef_coverage/analyze
```

Multipart. Persists nothing, so it requires only `cdef.read`.

**Upload every state that makes up the boundary.** A `stale_custom` verdict says
"nothing you uploaded uses this CDEF", which is only true of the whole boundary
— analysing one state of several reports the others' services as unused. States
and plans may be mixed.

| Parameter | Description |
|---|---|
| `files[]` | One or more `.tfstate` or `terraform show -json` files (max 25) |

```bash
curl -X POST https://sparc.example.com/api/v1/cdef_coverage/analyze \
  -H "Authorization: Bearer $SPARC_TOKEN" \
  -F "files[]=@ecs.tfstate" \
  -F "files[]=@config.tfstate"
```

**Response** `200 OK`

```json
{
  "data": {
    "counts": { "adopt": 4, "keep_custom": 1, "needs_custom": 2, "stale_custom": 1 },
    "findings": [
      {
        "service": "ecs",
        "verdict": "adopt",
        "inferred": false,
        "resource_count": 7,
        "resource_types": ["aws_ecs_cluster", "aws_ecs_service", "aws_ecs_task_definition"],
        "cdef_documents": [{ "id": 12, "name": "Amazon ECS" }]
      },
      {
        "service": "azurerm:storage",
        "verdict": "needs_custom",
        "inferred": true,
        "resource_count": 3,
        "resource_types": ["azurerm_storage_account"],
        "cdef_documents": []
      }
    ],
    "unmapped_resource_types": [{ "resource_type": "azurerm_storage_account", "count": 3 }],
    "sources": [
      { "filename": "ecs.tfstate", "digest": "9f2c…", "format": "state", "resource_count": 41 }
    ],
    "report_token": "eyJfcm…"
  }
}
```

`report_token` is a signed, one-hour handle on this exact analysis. Pass it to
`POST /runs` to save without re-uploading.

**Errors** `422` — the message names the offending file:

```json
{ "error": "notes.json: not a Terraform state or plan. A state has a top-level \"resources\" array; a plan (terraform show -json) has \"resource_changes\"." }
```

---

### POST Save a run

```
POST /api/v1/cdef_coverage/runs
```

Requires `cdef.write`. Accepts **either** `report_token` from a previous analyze
**or** the `files[]` again. It does not accept a report body: a saved run is a
compliance artifact, and an unsigned payload would let a caller assert whatever
coverage they liked.

| Parameter | Description |
|---|---|
| `report_token` | Signed token from `analyze` (preferred) |
| `files[]` | Alternative to the token — re-analysed server-side |
| `authorization_boundary_id` | Optional. Authorized against **that** boundary |

**Response** `201 Created` — the run, with `findings` and `unmapped_resource_types`.

---

### GET Runs

```
GET /api/v1/cdef_coverage/runs
GET /api/v1/cdef_coverage/runs/:id
```

Requires `cdef.read`. Paginated, newest first. Non-admins see runs for their
boundaries plus unattached runs, matching what the UI shows them.

### DELETE a run

```
DELETE /api/v1/cdef_coverage/runs/:id
```

Requires `cdef.write`. Audit-logged.

---

## NIST 800-53

| Control | How |
|---|---|
| IA-2 | Bearer token required |
| AC-3 / AC-6 | `cdef.read` to analyse, `cdef.write` to save; saving to a boundary authorizes against that boundary |
| AU-12 | Analyse, save and delete are audit-logged; file content never reaches the audit record |
| CM-8 | The infrastructure component inventory this derives |
| SI-12 | Uploads are parsed in-request and never retained |
