# Converters API

Framework converters are the lookup tables that map source framework
identifiers — CCI, CIS Safeguards, OVAL test types, STIG SV/V-IDs, AWS Config
rules, AWS Security Hub controls — to NIST SP 800-53 control ids.

Added in [#1011](https://github.com/risk-sentinel/sparc/issues/1011). Before it,
every refresh and import could be triggered only from a browser: the surface
most obviously wanted by automation was the one with no API. Found by the
missing-endpoint axis of
[#995](https://github.com/risk-sentinel/sparc/issues/995).

## Base URL

```
https://sparc.example.com/api/v1/converters
```

Addressable by **slug** (what the web routes use) or numeric id.

## Authorization

**Reads are open to any authenticated caller.** #919 removed `converters.read`
deliberately — it was granted to seven roles and enforced by no code, which
advertises an access boundary that does not exist. Writes require
`converters.write`; instance admins bypass.

## Three refresh actions became one endpoint

The web UI has `refresh_cci`, `refresh_aws_config` and
`refresh_aws_security_hub`. They differ only in which `converter_type` each will
accept, and each refuses the other two. A caller already knows the converter's
type — it is on the record — so three paths that each reject two thirds of the
collection is a UI affordance, not an API.

`POST …/:id/refresh` picks the service from
`ConverterRefreshJob::SERVICE_BY_TYPE`. A type with no registered service is
refused by name, and the response lists the types that do have one.

**Refresh is asynchronous and answers `202 Accepted`, not `200`.** The work has
not happened when the response is written; the converter goes to `processing`
and you poll `show`. Reporting `200` for work that has not run is exactly the
shape #995 exists to stop.

## Endpoints

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/v1/converters` | List, filterable by `converter_type` and `status` |
| `POST` | `/api/v1/converters` | Create a converter |
| `GET` | `/api/v1/converters/:id` | Show one, with `error_message` when a refresh failed |
| `PATCH`/`PUT` | `/api/v1/converters/:id` | Update attributes |
| `DELETE` | `/api/v1/converters/:id` | Delete, reporting how many entries went with it |
| `POST` | `/api/v1/converters/:id/refresh` | Re-vendor the mapping in the background |
| `GET` | `/api/v1/converters/:id/export` | The converter with every entry inline |
| `GET` | `/api/v1/converters/:converter_id/entries` | List entries, filterable by `source_id` / `target_id` |
| `POST` | `/api/v1/converters/:converter_id/entries` | Add a mapping row |
| `DELETE` | `/api/v1/converters/:converter_id/entries/:id` | Remove a mapping row |

### Converter fields

| Field | Type | Notes |
|---|---|---|
| `name` | string | Required |
| `converter_type` | string | `cci_to_nist`, `cis_to_nist`, `scap_oval_to_nist`, `stig_to_nist`, `aws_config_to_nist`, `aws_security_hub_to_nist`, `custom` |
| `status` | string | `draft`, `complete`, `deprecated`, `processing`, `failed` |
| `source_framework`, `target_framework`, `version`, `description` | string | |

`refreshable` on the response says whether `POST …/refresh` will work for this
converter, so a caller does not have to know the service map.

### Entry fields

| Field | Type | Notes |
|---|---|---|
| `source_id` | string | Required — e.g. `CCI-000001` |
| `target_id` | string | Required — e.g. `AC-1` |
| `relationship` | string | Required — `equal`, `equivalent`, `subset`, `superset`, `intersects` |
| `category`, `remarks` | string | |

A `source_id`/`target_id` pair is unique within a converter; a duplicate is
refused with `422`.

`index` is filterable because the question a caller has is usually "what does X
map to", and paging thousands of rows to answer it is not an answer.

## Status Codes

| Status | Description |
|---|---|
| `200 OK` | Read, update, delete or export succeeded |
| `201 Created` | Converter or entry created |
| `202 Accepted` | Refresh enqueued — poll `show` for the outcome |
| `401 Unauthorized` | Missing or invalid Bearer token |
| `403 Forbidden` | Caller lacks `converters.write` |
| `404 Not Found` | No such converter or entry |
| `409 Conflict` | A refresh is already running for this converter |
| `422 Unprocessable Entity` | Validation failed, the type cannot be refreshed, or the body carried a field this endpoint does not accept |

## Audit

`converter_created`, `converter_updated`, `converter_deleted`,
`converter_refresh_started`, `converter_exported`, `converter_entry_created`,
`converter_entry_deleted`.

## NIST 800-53 Controls

- **AC-3** Access Enforcement · **AU-12** Audit Record Generation
- **CM-6** Configuration Settings
