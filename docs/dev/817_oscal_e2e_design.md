<!-- markdownlint-disable MD013 -->
# #817 — end-to-end OSCAL pipeline proof: slice plan

> **Audience: SPARC maintainers.** Design pass for #817. Written before any
> code, per `issue_rules.md`. Records the slices, the decisions taken, and the
> gaps found while surveying — gaps become their own issues and are **not**
> fixed in the #817 branch (see the testing-program rule in the PR for #825).

## What already exists

The survey matters, because #817 is easy to over-build. SPARC already has:

- **Per-service coverage** — every exporter and parser has its own spec
  (`spec/services/oscal_*_spec.rb`, `spec/services/*_parser_service_spec.rb`).
- **Cross-cutting export rules** — `spec/services/oscal_compliance_audit_spec.rb`
  checks UUIDs, hrefs, back-matter, metadata and versioning across exporters.
- **UUID/round-trip stability** — `spec/support/oscal_round_trip_stability.rb`.
- **A deep fixture library** — vanilla NIST rev4/rev5 catalogs in JSON/XML/YAML,
  NIST L/M/H baseline profiles, resolved-profile catalogs, ODP samples, SSP/SAP/
  SAR/POA&M examples, HDF results, and two STIG XCCDFs.

**So the gap #817 names is not "more unit coverage" — it is the absence of a
single test that drives the whole chain and fails loudly at a broken seam.** The
per-stage specs all pass today while nothing proves stage N's *output* is a
valid stage N+1 *input*. That framing keeps this work from duplicating what is
already green.

## Pipeline → SPARC surface

| # | Stage | Driven through |
|---|---|---|
| 1 | Vanilla NIST catalog | `CatalogImportService` → `ControlCatalog`/`ControlFamily`/`CatalogControl` |
| 2 | SPARC ODPs | `OdpImportService.parse` + `#apply` on the profile |
| 3 | 3 baselines + resolution | `ProfileDocument` + `OscalProfileExportService`, `OscalResolvedProfileCatalogService` |
| 4 | Boundary from ECS CDEFs | `CdefJsonParserService` / `CdefYamlParserService` / `CdefXccdfParserService` → `CdefDocument`, linked via `AuthorizationBoundary` / `BoundaryCdefDocument` |
| 5 | SSP / SAP / Evidence / Amendments / SAR / POA&M | the `*_json/yaml/xml_parser_service` family in, the `Oscal*ExportService` family out |
| 6 | ATO package | `AtoPackageService#create` (assemble) + `AtoPackageExportService#generate_zip` (bundle) |

Serialization fan-out for every document is `OscalExportFormatService.to_yaml`
/ `.to_xml`; schema validation is `OscalSchemaValidationService` against the
bundled schemas in `lib/oscal_schemas` (JSON) and `lib/oscal_xsd_schemas` (XSD).

## Slices

Each slice is one commit on the shared testing branch and leaves the suite
green.

| Slice | Content |
|---|---|
| **S1** | ECS boundary fixtures — the 19 sparc-iac `AWS/CDEF/ECS/` CDEFs, sanitized and committed, plus invalid variants and a spec that keeps them sanitized |
| **S2** | Stages 1–3 — catalog import → ODPs → 3 baselines → profile resolution, each exported and schema-validated in JSON/YAML/XML, each with a reject case |
| **S3** | Stage 4 — the full ECS CDEF set imported (JSON/YAML/XML/XCCDF) and assembled into a boundary |
| **S4** | Stage 5 — SSP, SAP, Evidence, Amendments, SAR, POA&M; HDF and XCCDF/SCAP ingestion for the assessment side |
| **S5** | Stage 6 — ATO package assembly + export, round-trip semantic equivalence, `samples/` demo output |
| **S6** | Negative matrix sweep — confirm every stage has an explicit reject assertion; unsupported format/type combinations rejected deliberately rather than crashing |

### Cost control

The vanilla rev5 catalog fixture is **10 MB / ~1 100 controls**. Importing it
per example would make the spec unusable in CI. The orchestrating spec therefore
imports it **once** (`before(:context)`) and drives the stages in order, with
each stage's assertions in its own example. Stage ordering is the point of the
test, so sequential execution is a feature, not a smell.

If the full-catalog import proves too slow for CI even once, the fallback is a
**committed subset catalog** covering every control family plus every control
selected by the three baselines — subset by *coverage*, never by convenience,
and the subset generation must be a committed script so it is reproducible.

## Decisions

**D1 — Which "FedRAMP" baselines?** The repo ships NIST rev5 L/M/H baseline
profiles, not FedRAMP's. FedRAMP's rev5 baselines live in GSA/fedramp-automation
and are US-Government public-domain, so they *can* be committed as fixtures.
**Decision: commit the real FedRAMP rev5 L/M/H baseline profiles as fixtures if
they can be retrieved; otherwise author FedRAMP-shaped profiles over the NIST
baselines and label them explicitly as test-authored.** A test that silently
calls a NIST baseline "FedRAMP" would be lying about its own coverage. Whichever
path is taken gets stated in the fixture README.

**D2 — Fixture provenance.** sparc-iac CDEFs are already generalized
(`arn:aws:...:<region>:<account>:...` placeholders, synthetic UUIDs, no real
account IDs). Only `mail.risk-sentinel.org` is org-specific. Sanitization is
therefore light, but it must be **enforced by a spec**, not by care at copy
time — otherwise the next refresh reintroduces whatever the source picks up.

**D3 — Invalid fixtures are authored, never generated at runtime.** Each invalid
variant is committed next to its valid twin with a one-line comment naming the
defect (wrong root element, missing required field, ODP constraint violation,
wrong schema for type). A runtime-mutated fixture makes failures unreproducible.

**D4 — No fabricated content to make a stage pass.** If a stage cannot produce
schema-valid output because required OSCAL content is missing, the fix is the
fixture or the seed, never a fallback in the exporter. This is the #816 lesson
(`risk/statement`, `finding/target`) and it is non-negotiable.

## Gaps found while surveying

Filed as their own issues; **not** fixed on this branch.

| Gap | Detail |
|---|---|
| ATO package export is JSON-only | `AtoPackageExportService::EXPORT_SERVICES` bundles `.json` members and validates JSON only. #817 asks for the assembled package in all three serializations, which the service cannot currently produce. |

## Acceptance mapping

| #817 criterion | Slice |
|---|---|
| One test drives catalog → … → ATO package | S2–S5 (orchestrator introduced in S2, extended per slice) |
| Every document exported + validated in JSON/YAML/XML | S2–S5 |
| Every importer exercised on appropriate types | S3 (JSON/YAML/XML/XCCDF), S4 (HDF, SCAP) |
| Both accept and reject assertions per step | every slice; swept in S6 |
| Round-trip semantic equivalence | S5 |
| Boundary = full ECS CDEF set | S1 + S3 |
| Fixtures + ATO demo committed | S1 + S5 |
| Green in CI | every slice |
