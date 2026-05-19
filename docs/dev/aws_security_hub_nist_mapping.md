# AWS Security Hub → NIST 800-53 mapping (#491)

This doc covers the converter that translates AWS Security Hub control
identifiers (`IAM.3`, `S3.5`, `EC2.7`, ...) used by AWS Labs OSCAL
Component Definitions into NIST SP 800-53 rev5 control identifiers
(`ac-2.1`, `sc-7`, ...) used by SPARC's heatmaps, OSCAL exports, and
SSP cross-references.

## Why this exists

AWS Labs publishes OSCAL CDEFs at
[`awslabs/oscal-content-for-aws-services`](https://github.com/awslabs/oscal-content-for-aws-services)
keyed by **AWS Security Hub** control IDs, not NIST 800-53. Without a
translation layer, SPARC's downstream consumers see opaque `IAM.3`-style
identifiers and cannot:

- Group controls by NIST family on heatmaps
- Emit valid `control-id` references to NIST profiles in OSCAL exports
- Pull AWS-implementation evidence into SSP control inheritance sections

The converter closes that gap. See issue
[#491](https://github.com/risk-sentinel/sparc/issues/491) for the
original framing.

## How it's built

The composite mapping is assembled from two data sources:

| Layer | Source | Coverage | When used |
| --- | --- | --- | --- |
| **Primary** | `lib/data_mappings/aws_security_hub_to_nist.json` — scraped from the [AWS Security Hub User Guide](https://docs.aws.amazon.com/securityhub/latest/userguide/securityhub-controls-reference.html) | ~51% of SecHub controls have AWS-published NIST rev5 mappings | Always preferred when present |
| **Fallback** | `lib/data_mappings/mitre_aws_config_to_nist.json` — vendored from [`mitre/heimdall2`](https://github.com/mitre/heimdall2) | 106 AWS Config Rules → NIST (rev4); ~1–2% additional SecHub coverage | When AWS publishes no NIST mapping for a control but a Config rule MITRE knows about |

The composition is performed by
`AwsSecurityHub::CompositeMappingBuilder` (`lib/aws_security_hub/`)
during `bin/rails db:seed`. Each composed `ConverterEntry` row
carries:

- `source_id` = SecHub control ID (e.g., `IAM.3`)
- `target_id` = one NIST OSCAL ID (e.g., `ac-2.1`)
- `category` = `aws_direct` or `mitre_fallback` (provenance)
- `relationship` = `intersects`
- `remarks` = title, AWS Config rule, source, and (for fallback rows) the original MITRE rev4 IDs

One SecHub control may produce multiple rows (many-to-many). The
`(converter_id, source_id, target_id)` unique index prevents duplicates.

## How AWS Labs imports use it

`AwsLabsCdefImportService#enrich_with_nist_mappings!` runs after each
CDEF is parsed. For every `CdefControl` whose `control_id` matches the
SecHub shape (`Service.N`), the service writes four
`cdef_control_fields` rows:

| Field | Value | Purpose |
| --- | --- | --- |
| `aws_security_hub_id` | the original SecHub ID | provenance |
| `nist_oscal_ids` | comma-joined OSCAL IDs (sorted) | display + audit |
| `nist_primary_id` | the lowest-sorted NIST ID | grouping key |
| `nist_mapping_source` | `aws_direct` or `mitre_fallback` | tells you where the mapping came from |

The `control_id` column itself is **not mutated** — the SecHub ID
remains the row's canonical identifier; the NIST mapping is additive
metadata.

## Refresh workflow

AWS adds Security Hub controls regularly. When mappings drift (new
controls appear unmapped, or existing controls change their published
NIST mapping), refresh the data in this order:

```bash
# 1. Re-scrape AWS Security Hub docs (~80 service pages, ~2 min)
bundle exec rake mappings:scrape_aws_security_hub

# 2. Optional: re-vendor MITRE's Config Rule → NIST mapping
#    (Only if MITRE has updated their heimdall2 data)
bundle exec rake mappings:vendor_mitre_aws_config

# 3. Inspect the diff
git diff lib/data_mappings/

# 4. Re-seed the converter
#    (the seed loader is idempotent and only inserts if entries don't exist;
#    to fully refresh, manually destroy + reseed)
bin/rails console
> Converter.find_by(converter_type: "aws_security_hub_to_nist").destroy
> exit
bin/rails db:seed

# 5. Re-run AWS Labs imports to apply new mappings
bundle exec rake mappings:coverage_report   # before
# Trigger refresh via UI "Refresh from AWS Labs" button OR job:
bin/rails runner 'AwsLabsCdefRefreshJob.perform_now(force: true)'
bundle exec rake mappings:coverage_report   # after
```

Commit the diff to `lib/data_mappings/*.json` with a reference to the
upstream commit SHA (AWS docs page version timestamp; MITRE
heimdall2 commit SHA).

## Coverage report

Run `bundle exec rake mappings:coverage_report` to see:

- How many AWS Labs CDEFs are imported
- How many CdefControl rows have SecHub-shape IDs
- How many of those are mapped to NIST (covered)
- How many are unmapped (gap) — with up to 30 sample IDs

Use the output to decide whether to re-scrape (AWS may have added the
mapping upstream) or to hand-curate via the converter admin UI
(`/converters/...`).

## Gaps and limitations

- **Tag governance + alarm-based controls**: ~25 SecHub controls have
  no AWS Config rule AND no AWS-published NIST mapping. These are
  mostly CIS-only governance checks (`Backup.2`-`Backup.5` for tag
  presence; `CloudTrail.6`-`CloudTrail.7` and `CloudWatch.1`-`CloudWatch.12`
  for log-metric alarms). NIST 800-53 doesn't map cleanly to these;
  they remain unmapped intentionally.
- **MITRE rev4**: The fallback layer is NIST 800-53 rev4. The normalizer
  emits OSCAL-shaped IDs (`ac-2.1`, `ac-2_smt.j`) that are valid
  *notation* for both rev4 and rev5. Where rev4 and rev5 differ
  semantically (subpart letter renumbering), the fallback layer may
  point at a control element that no longer exists in rev5. Coverage
  reports flag these as candidates for manual review when they appear.
- **Many-to-many is one-way**: One SecHub → many NIST IDs is supported.
  Many SecHub → one NIST (i.e., reverse lookup) requires
  `ConverterEntry.where(target_id: ...)` queries; no convenience helper
  is provided yet.

## Code map

| Path | Role |
| --- | --- |
| `lib/aws_security_hub/nist_id_normalizer.rb` | Convert MITRE/AWS paren notation to OSCAL lowercase |
| `lib/aws_security_hub/mitre_mapping_porter.rb` | Parse MITRE's TS source, write SPARC envelope |
| `lib/aws_security_hub/control_scraper.rb` | Parse AWS Security Hub user-guide HTML |
| `lib/aws_security_hub/composite_mapping_builder.rb` | Merge primary + fallback into ConverterEntry-ready rows |
| `lib/data_mappings/mitre_aws_config_to_nist.json` | Vendored MITRE data (Apache-2.0 attribution) |
| `lib/data_mappings/aws_security_hub_to_nist.json` | Scraped AWS Security Hub data |
| `lib/tasks/aws_security_hub_mapping.rake` | `vendor_mitre_aws_config`, `scrape_aws_security_hub`, `coverage_report` |
| `db/seeds/converters.rb` | Idempotent seed loader |
| `app/services/aws_labs_cdef_import_service.rb` | `enrich_with_nist_mappings!` import hook |
| `LICENSES/MITRE-HEIMDALL2-LICENSE` | Apache-2.0 license text for vendored MITRE data |
| `docs/compliance/THIRD_PARTY_NOTICES.md` | Audit-trail attribution entry |
