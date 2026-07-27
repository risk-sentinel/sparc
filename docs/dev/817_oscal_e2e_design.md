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

| Slice | Content | Status |
|---|---|---|
| **S1** | ECS boundary fixtures — the 19 sparc-iac `AWS/CDEF/ECS/` CDEFs, sanitized and committed, plus a re-runnable sanitizer | **done** (`fff647b3`) |
| **S2** | Stages 1–3 — catalog import → ODPs → 3 baselines → profile resolution, each exported and schema-validated, each with reject cases | **done** — 21 examples, 0 failures, 1 pending (#827) |
| **S3** | Stage 4 — the full ECS CDEF set imported (JSON/YAML/XML/XCCDF) and assembled into a boundary | **done** — 10 examples |
| **S4** | Stage 5 — SSP, SAP, SAR, POA&M, Evidence; HDF ingestion for the assessment side | **done** — 45 examples total, 0 failures, 2 pending (#827, #831) |
| **S5** | Stage 6 — ATO package assembly + export, round-trip semantic equivalence, `samples/` demo output | **split out to #836** — blocked by #829 (JSON-only), #827 (XML invalid) and #828 (manifest/archive disagree) |
| **S6** | Negative matrix sweep — wrong-schema-for-type cross-product, malformed input, ODP constraint violation | **done** — 50 examples total, 0 failures, 2 pending |

**S6 as built.** Stages 1–5 each carry their own reject cases, so S6 covers only
what per-stage assertions structurally cannot: combinations *across* types.

- **Wrong-schema-for-type**, as a full cross-product: 7 models × 6 wrong schemas
  = 42 combinations, every one required to be rejected. A validator that ignored
  its `model_type` argument, or fell back to a permissive schema, would satisfy
  every positive assertion in the file and fail only here.
- A **control** first: each fixture must be valid against its *own* schema.
  Without it, a cross-type rejection could be explained by a bad fixture rather
  than by correct schema selection. This control immediately earned its keep —
  see below.
- **Malformed input** (`{}`, `null`, `[]`, right-key-empty-body) rejected for
  every model, and **rejected rather than raised**: an exception reaches an API
  caller as a 500, an invalid result as a 422, and #817 asks for deliberate
  rejection.
- **ODP constraint violation** — a selection value outside the baseline's
  allowed choices must never be previewed as an acceptable change.

**Fixture defect found by the control:** `small-resolved-profile-catalog.json`
carried `"uuid": "test-resource-uuid"` in its back-matter — not a UUID, so the
fixture was not valid OSCAL, and the two specs using it
(`document_conversion_job_spec`, `profile_resolved_catalog_parser_spec`) were
exercising invalid input. Replaced with a well-formed UUID; both dependent
specs re-run green (39 examples). Fixed here rather than filed because it is
test infrastructure, not product behaviour.

**S2 coverage as built:** catalog completeness (20 families, >2000 controls, no
empty family), JSON/YAML schema validity, XML well-formedness, XSD validity
(pending #827), payload survival; baseline selection resolving fully against the
catalog, cumulative LOW ⊂ MODERATE ⊂ HIGH (149/287/370), profile export validity,
resolution to a valid *catalog*, control carry-through; ODP import from JSON,
YAML **and** XML, non-destructive preview; plus reject cases for missing
metadata, non-UUID ids, wrong model type, empty imports, unsupported format,
empty file and malformed JSON.

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

**D1 — Which "FedRAMP" baselines? → RESOLVED: NIST rev5 L/M/H, labelled as
such.** FedRAMP's rev5 baselines live in `GSA/fedramp-automation`, which returns
**404** — checked anonymously and authenticated, and under `FedRAMP/` as well —
so they cannot be retrieved and committed as fixtures. The repo already ships
the **NIST** rev5 Low/Moderate/High baseline profiles, and stage 3 uses those,
naming them NIST throughout.

The spec says so in a comment at the point of use, because the failure mode here
is a *documentation* one: a test that silently calls a NIST baseline "FedRAMP"
lies about its own coverage, and the lie is invisible in a green run. If the
FedRAMP profiles become retrievable, swapping the fixtures is a one-line change
per level — the selection is driven entirely by the profile's `with-ids`.

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

## Bugs found

Filed as their own issues; **not** fixed on this branch.

| # | Found by | Detail |
|---|---|---|
| **#827** | Stage 1, XML validation | **Every OSCAL XML export is schema-invalid.** `OscalJsonToXmlConverter` emits children in JSON key order; the OSCAL XSD is an `xs:sequence` with a mandated order. `download_xml` is user-facing on seven document types. Undetected because no spec ever called `validate_xml` against a real export. |
| **#828** | Surveying `AtoPackageExportService` | **The ATO package silently omits documents whose export fails while the manifest still lists them** — verified: a raising SSP export yields an archive containing only `manifest.json`, whose document list still names `ssp.json`. Also ships `export_unvalidated` bytes. |
| **#829** | Surveying `AtoPackageExportService` | ATO package export is **JSON-only**, so #817's all-three-serializations requirement cannot be met. Blocked by #827 for the XML half. |
| **#830** | Surveying blob storage | No key-prefix logic anywhere — every attachment lands in the bucket root under a random key, so prefix-scoped IAM, lifecycle rules and per-tenant cleanup are all impossible. |
| **#831** | Stage 5, HDF ingestion | `sar_from_hdf` returns **schema-invalid OSCAL unchecked** — real hdf-cli 3.4.1 output is missing `reviewed-controls`, `finding/description` and `characterization/origin`, and no call site validates. Upstream half filed as [mitre/hdf-libs#184](https://github.com/mitre/hdf-libs/issues/184). |
| **#832** | Stage 5, POA&M round-trip | `PoamRisk` validates only `uuid`; every other column is nullable, so OSCAL-required fields (`title`, `description`, `statement`, `status`) and the `deadline` can all be blank. The #816 bug class at its source. |
| **#835** | CI run of the pipeline spec | CI has no `hdf` binary, so the HDF specs skip there; and hdf-cli is pinned at **three different versions** across the repo (3.4.1 / 3.2.0 / 3.3.2), straddling two behavioural changes in the converter. |

### A correction worth recording

The first version of #831 also claimed the POA&M translation was "dead" because
`hdf_to_oscal_poam` raises. **That was wrong** and has been withdrawn. Per MITRE,
hdf-libs handles OSCAL POA&M via **HDF Amendments**; the direct converter was
removed in 3.2.0 by design, and `TranslationsController#poam_from_hdf` already
returns a deliberate **501** naming the removal and pointing at the replacement.
The spec now pins both halves of that contract — raw HDF must refuse, amendments
must work — rather than treating the removal as breakage.

### On the `pending` marker

Stage 1's XSD assertion is marked `pending` against #827 rather than deleted or
softened. RSpec runs a pending example, expects it to fail, and **fails the
suite if it passes** — so the marker cannot outlive the bug, and the evidence
(the full XSD error list) stays visible in every run. Well-formedness and
payload survival are asserted separately and pass, so only XSD conformance is
deferred.

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
