# #1108 — OSCAL 1.2.3 conformance sweep

**Status:** done for v1.17.2. #1105's decision is the adoption in `7efee101`:
1.2.3 is supported and is `OscalSchema::DEFAULT_VERSION`, alongside 1.2.2, and
`oscal_version` stays per document.

This sweep re-runs #1106's audit against 1.2.3. It answers the three questions
#1108 asked:
- what changed in the schemas (shape and enforcement form);
- what changed in the Metaschema vocabularies;
- whether every SPARC export still conforms under both releases.

## 1. Enumeration enforcement, 1.2.2 → 1.2.3

Measured from the NIST JSON schemas bundled per release
(`lib/oscal_schemas_bundle/v1.2.2` and `v1.2.3`). Each enumeration is classed by
form:
- **enforced:** a bare `enum`, or one under `allOf`;
- **advisory:** `anyOf: [string, {enum}]`, so any string passes.

| Model | Enums (1.2.2 / 1.2.3) | Enforced / advisory in 1.2.3 | Form changes | Value changes |
|---|---|---|---|---|
| catalog | 11 / 11 | 4 / 7 | 0 | 0 |
| profile | 15 / 15 | 8 / 7 | 0 | 0 |
| component-definition | 17 / 17 | 6 / 11 | 0 | 2 |
| system-security-plan | 18 / 18 | 7 / 11 | 0 | 1 |
| assessment-plan | 33 / 33 | 10 / 23 | 0 | 1 |
| assessment-results | 33 / 33 | 10 / 23 | 0 | 1 |
| plan-of-action-and-milestones | 33 / 33 | 10 / 23 | 0 | 1 |
| mapping | 24 / 24 | 15 / 9 | 0 | 0 |

**No `anyOf` → `allOf` transition in any model**, and no enumeration was added or
removed. The value changes are all additions to advisory lists:

- `system-component.type` (SSP, SAP, SAR, POA&M and CDEF) adds `region`, `zone`
  and `resource-container`.
- `defined-component.type` (CDEF) adds `network`, `region`, `zone` and
  `resource-container`.

Both lists are advisory, so no document changes validity. The required fields
and cardinalities are unchanged; `7efee101` measured this across all eight
models.

## 2. Metaschema vocabularies

Compared from the tracked conformance datasets
(`lib/oscal_conformance/1.2.2` and `1.2.3`), which carry the constraints JSON
Schema cannot express. Of 1,103 entries, **one rule differs**:

| Model | Rule | 1.2.2 | 1.2.3 | Effect |
|---|---|---|---|---|
| catalog | prop `status` values | **enforced:** `withdrawn`, `Withdrawn` | **advisory:** `withdrawn`, `reserved`, `deprecated`, `conditional`, `superseded`, `modified`, `experimental` | **Retired by 1.2.3** (relaxed). SPARC emits `withdrawn` (`OscalCatalogExportService::WITHDRAWN_PROP`), which is valid in both. |

No rule was tightened, so 1.2.3 introduces no new non-conformance and newly
enforces nothing.

## 3. SPARC's documents under both releases

`spec/integration/oscal_1_2_3_conformance_sweep_1108_spec.rb` runs every
committed OSCAL document through three checks: the tracked 1.2.3 schema, and the
1.2.2 and 1.2.3 conformance vocabularies, with the document re-declared at each
version. The documents cover all seven export models:
- the end-to-end SSP, SAP and SAR samples;
- the demo samples;
- the custom-controls catalog and profile;
- the five compliance CDEFs.

The same spec pins the vocabulary diff in section 2, so if a regenerated dataset
gives a different answer, the spec fails.

| Finding | Kind | Disposition |
|---|---|---|
| The end-to-end samples and the five compliance CDEFs | Conform under both | None needed |
| `docs/api/samples/custom-controls-catalog.json` carried `priority` and `impact-level` props with no `ns` | Existing (both releases) | Removed: a catalog sets neither; a profile does (#1235) |
| `samples/nist-traditional-demo/*` and `samples/ato-package-demo/*` (generated in March 2026 and September 2026): props and parts with no `ns` (`implementation-status`, `severity`, `assessment-schedule`), and a POA&M missing `risk.statement` and `finding.target` | Existing (both releases); the current exporters no longer produce these | Regenerated on a disposable database with the current exporters |
| **SSP export:** a leveraged authorization's `party-uuid` resolved to no party when it came from a legacy `SspLeveragedAuthorization` (its stored `party_uuid`) or from a boundary authorization's metadata. Found in the regenerated demo SSP | Existing (both releases); the **one exporter defect** the sweep found | Fixed: `OscalSspExportService#declare_leveraged_parties!` declares every referenced party (`spec/services/oscal_ssp_export_leveraged_party_1108_spec.rb`) |

**No regression for 1.2.2:** every document that conforms under 1.2.3 also
conforms under 1.2.2. The one vocabulary difference only widens what 1.2.3
accepts.
