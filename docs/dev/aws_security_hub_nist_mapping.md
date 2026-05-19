# AWS Security Hub → NIST 800-53 mapping (#491, #494)

This doc covers the two decoupled converters that translate AWS
Security Hub control identifiers (`IAM.3`, `S3.5`, `EC2.7`, ...) used
by AWS Labs OSCAL Component Definitions into NIST SP 800-53 rev5
control identifiers (`ac-2.1`, `sc-7`, ...) used by SPARC's heatmaps,
OSCAL exports, and SSP cross-references.

## Why this exists

AWS Labs publishes OSCAL CDEFs at
[`awslabs/oscal-content-for-aws-services`](https://github.com/awslabs/oscal-content-for-aws-services)
keyed by **AWS Security Hub** control IDs, not NIST 800-53. Without a
translation layer, SPARC's downstream consumers see opaque `IAM.3`-style
identifiers and cannot:

- Group controls by NIST family on heatmaps
- Emit valid `control-id` references to NIST profiles in OSCAL exports
- Pull AWS-implementation evidence into SSP control inheritance sections

See [#491](https://github.com/risk-sentinel/sparc/issues/491) for the
original framing and [#494](https://github.com/risk-sentinel/sparc/issues/494)
for the v1.6.5 decoupled architecture (this doc).

## Architecture (v1.6.5)

Two first-class converters with a runtime two-hop chain:

```
┌─────────────────────────────────────────────────────────────┐
│ Converter A: "AWS Config Rule → NIST 800-53"                │
│   converter_type = "aws_config_to_nist"                     │
│   Source: mitre/heimdall2 AwsConfigMappingData (vendored)   │
│   Refresh UI: /converters/:id → "Refresh from MITRE"        │
│   ~106 source rules → ~432 ConverterEntry rows              │
│   Editable: yes (extends MITRE's coverage)                  │
└─────────────────────────────────────────────────────────────┘
                            ▲
                            │ chained at import time
                            │ via SecHub → Config Rule bridge
                            │
┌─────────────────────────────────────────────────────────────┐
│ Converter B: "AWS Security Hub → NIST 800-53 rev5"          │
│   converter_type = "aws_security_hub_to_nist"               │
│   Source: AWS Security Hub User Guide (scraped)             │
│   Refresh UI: /converters/:id → "Refresh from AWS docs"     │
│   Direct mappings only (~303 SecHub → ~2 168 rows)          │
│   `remarks` stashes aws_config_rule for runtime chain       │
│   Editable: yes                                             │
└─────────────────────────────────────────────────────────────┘
```

## Two-hop chain at import time

`AwsLabsCdefImportService#enrich_with_nist_mappings!` runs after each
CDEF is parsed. For every `CdefControl` whose `control_id` matches the
SecHub shape (`Service.N`):

```
1. Direct lookup in aws_security_hub_to_nist
     found → use those NIST ids; source = "aws_direct"
2. Else, pull aws_config_rule from the bridge
     (lib/data_mappings/aws_security_hub_to_nist.json, memoized once
     per import run)
3. Lookup that Config Rule in aws_config_to_nist
     found → use those NIST ids; source = "via_config_rule"
4. Else → leave unmapped (will show in coverage report)
```

The chain is computed at **import time**, not seed time. Hand-curating
`aws_config_to_nist` *automatically* benefits every Sec Hub control
referencing that Config Rule on the next CDEF import.

## CdefControlField rows written per enriched control

| Field | Value | Purpose |
| --- | --- | --- |
| `aws_security_hub_id` | the upstream SecHub ID | provenance |
| `nist_oscal_ids` | comma-joined OSCAL IDs (sorted) | display + audit |
| `nist_primary_id` | the lowest-sorted NIST ID | grouping key |
| `nist_mapping_source` | `aws_direct` or `via_config_rule` | chain provenance |
| `aws_config_rule` | the Config Rule name (when via_config_rule only) | chain audit |

The `control_id` column itself is **not mutated** — the SecHub ID
remains the row's canonical identifier; NIST is additive metadata.

## Refresh workflow

### Via UI (recommended)

Operators with `converters.write` see refresh buttons on each converter's
show page:

- `/converters/<aws_config_to_nist_id>` → **Refresh from MITRE**
  → triggers `ConverterRefreshJob` → `AwsConfigRefreshService`
- `/converters/<aws_security_hub_to_nist_id>` → **Refresh from AWS docs**
  → triggers `ConverterRefreshJob` → `AwsSecurityHubRefreshService`

Both refreshes:
- Set `converter.status = "processing"` and stamp `metadata_extra.refresh_stage`
- Auto-refresh the view every 3 seconds via `<meta http-equiv="refresh">`
- Replace only rows authored by that service (category=`mitre_vendored`
  for AWS Config, category=`aws_direct` for AWS Sec Hub) — operator
  hand-edits with other category values are preserved
- Audit-log a `converter_refresh_started` event

### Via rake (shell-only)

```bash
bundle exec rake mappings:vendor_mitre_aws_config   # AWS Config
bundle exec rake mappings:scrape_aws_security_hub   # AWS Sec Hub
bin/rails db:seed                                   # rebuild converter rows
```

## Coverage report

```bash
bundle exec rake mappings:coverage_report
```

Reports, against the live database:

- Imported AWS Labs CDEFs
- Total CdefControl rows
- Unique SecHub-shaped control_ids referenced
- **Direct matches** (via aws_security_hub_to_nist)
- **Chained matches** (via aws_config_to_nist)
- **Unmapped** (with a sample of up to 30 IDs)
- Converter inventory summary
- Actionable next steps for each gap

## Gaps and limitations

- **Tag governance + alarm-based controls**: ~25 SecHub controls have
  no AWS Config rule AND no AWS-published NIST mapping. These are
  mostly CIS-only governance checks (`Backup.2`-`Backup.5`,
  `CloudTrail.6`-`CloudTrail.7`, `CloudWatch.1`-`CloudWatch.12`).
  NIST 800-53 doesn't map cleanly to these.
- **MITRE rev4**: The fallback layer is NIST 800-53 rev4. The normalizer
  emits OSCAL-shaped IDs (`ac-2.1`, `ac-2_smt.j`) valid for both
  revisions. Where rev4 and rev5 differ semantically (subpart letter
  renumbering), the chain may surface a rev4-only element.

## Code map

| Path | Role |
| --- | --- |
| `app/models/converter.rb` | `aws_config_to_nist` + `aws_security_hub_to_nist` in TYPES + TYPE_LABELS |
| `app/helpers/converters_helper.rb` | Type badge colors |
| `app/controllers/converters_controller.rb` | `refresh_aws_config`, `refresh_aws_security_hub` actions |
| `app/views/converters/show.html.erb` | Refresh buttons + modals per converter type |
| `app/jobs/converter_refresh_job.rb` | Dispatcher by converter_type → service |
| `app/services/aws_config_refresh_service.rb` | Re-vendor MITRE + reload converter (stage stamps, transactional) |
| `app/services/aws_security_hub_refresh_service.rb` | Re-scrape AWS docs + reload converter (same shape) |
| `app/services/aws_labs_cdef_import_service.rb` | Two-hop enrichment at import time |
| `lib/aws_security_hub/nist_id_normalizer.rb` | MITRE/AWS paren notation → OSCAL lowercase |
| `lib/aws_security_hub/mitre_mapping_porter.rb` | Parse MITRE TS, write SPARC envelope |
| `lib/aws_security_hub/control_scraper.rb` | Parse AWS Security Hub user-guide HTML |
| `lib/aws_security_hub/aws_config_mapping_loader.rb` | ConverterEntry rows from MITRE doc |
| `lib/aws_security_hub/aws_security_hub_mapping_loader.rb` | ConverterEntry rows from AWS scrape; also builds SecHub→ConfigRule bridge |
| `lib/data_mappings/mitre_aws_config_to_nist.json` | Vendored MITRE data (Apache-2.0) |
| `lib/data_mappings/aws_security_hub_to_nist.json` | Scraped AWS Sec Hub data |
| `lib/tasks/aws_security_hub_mapping.rake` | `vendor_mitre_aws_config`, `scrape_aws_security_hub`, `coverage_report` |
| `db/seeds/converters.rb` | Idempotent seed: section 4 (AWS Config), section 5 (AWS Sec Hub) |
| `db/migrate/20260519000000_cleanup_v164_mitre_fallback_rows.rb` | One-time v1.6.4 → v1.6.5 cleanup |
| `LICENSES/MITRE-HEIMDALL2-LICENSE` | Apache-2.0 license text for vendored data |
| `docs/compliance/THIRD_PARTY_NOTICES.md` | Attribution audit trail |
