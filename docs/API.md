# REST API

REST API under the `Api::V1::` namespace at `/api/v1/`.

## SSP Documents

| Endpoint | Method | Description |
| -------- | ------ | ----------- |
| `/api/v1/ssp_documents/convert` | POST | Upload and convert an SSP Excel file |
| `/api/v1/ssp_documents/update_fields` | PUT | Update SSP control fields |
| `/api/v1/ssp_documents/export` | GET | Export SSP as JSON |

## SAR Documents

| Endpoint | Method | Description |
| -------- | ------ | ----------- |
| `/api/v1/sar_documents/convert` | POST | Upload and convert a SAR Excel file |
| `/api/v1/sar_documents/update_fields` | PUT | Update SAR control fields |
| `/api/v1/sar_documents/export` | GET | Export SAR as JSON |

## Authentication

API endpoints respect the same authentication settings as the web UI. When
authentication is disabled (no `SPARC_ENABLE_*` variables set), all API
endpoints are publicly accessible.

## Examples

### Upload an SSP

```bash
curl -X POST http://localhost:3000/api/v1/ssp_documents/convert \
  -F "file=@path/to/your/ssp.xlsx"
```

### Export an SSP as JSON

```bash
curl http://localhost:3000/api/v1/ssp_documents/export?id=1
```
