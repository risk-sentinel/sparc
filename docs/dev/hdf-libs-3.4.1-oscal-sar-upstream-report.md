<!-- markdownlint-disable MD013 -->
# hdf-cli v3.4.1: `hdf → oscal-sar` emits OSCAL Assessment Results that fail the NIST OSCAL 1.1.2 schema

> **Status: FILED upstream as [mitre/hdf-libs#184](https://github.com/mitre/hdf-libs/issues/184)**
> (2026-07-27). Contains no proprietary content — the reproducer is fully
> synthetic. Tracked on our side as #831.
> Follows the same shape as [`hdf-libs-3.2.0-upstream-report.md`](hdf-libs-3.2.0-upstream-report.md).

## Summary

`hdf convert --from hdf --to oscal-sar` exits `0` and emits a document that is
**not valid OSCAL Assessment Results**. Validated against the NIST OSCAL v1.1.2
Assessment Results JSON Schema (`oscal-ar-schema.json`), the output is missing
**three required properties** and emits **one property that violates the OSCAL
string datatype**.

The converter reports success, so a consumer has no signal that the document is
unusable until it reaches a schema-validating tool.

Four defects, all reproducible from a 40-line synthetic HDF input:

| # | Location | Problem | Since |
|---|---|---|---|
| 1 | `results[]` | missing required `reviewed-controls` | long-standing |
| 2 | `results[].findings[]` | missing required `description` | long-standing |
| 3 | `results[].risks[].characterizations[]` | missing required `origin` | long-standing |
| 4 | `results[].findings[].props[]` | `value: ""` violates the non-empty string datatype | **regression, new in 3.4.0** |

## Version matrix

We ran the **same minimal input** through every release from 3.2.0 forward and
validated each output against the OSCAL v1.1.2 AR schema. This is not a single
data point.

| Version | Converts? | Schema errors | Notes |
|---|---|---|---|
| **3.2.0** | ✗ exit 1 | — | `invalid HDF structure: missing baselines field` (the regression reported in mitre/hdf-libs#104, since resolved) |
| **3.3.2** | ✓ exit 0 | **4** | `reviewed-controls`, `finding/description`, `characterization/origin`, **`risk/statement`** |
| **3.4.0** | ✓ exit 0 | **4** | `risk/statement` **FIXED**; **empty `prop.value` introduced** |
| **3.4.1** | ✓ exit 0 | **4** | identical to 3.4.0 |

Two things follow, and both are actionable:

1. **Defects 1–3 have been present since the converter first worked** (3.3.2).
   They are not a recent regression, which is why they may not have been
   noticed — nothing in the pipeline validates the output.
2. **3.4.0 fixed one schema violation and introduced another.** `risk/statement`
   was correctly added; in the same release the finding `props` array gained
   `code` and `control-type` entries, and `code` is emitted with `value: ""`
   whenever the source control's `code` field is empty.

Concretely, for the same input:

```jsonc
// 3.3.2
"props": [ { "name": "nist", "value": "AC-3" } ]

// 3.4.0 / 3.4.1  — two new props, one of them invalid
"props": [
  { "name": "nist", "value": "AC-3" },
  { "name": "code", "value": "" },          // ← violates StringDatatype
  { "name": "control-type", "value": "technical" }
]
```

The `risk/statement` fix in 3.4.0 is the reason we think this report is worth
filing: schema conformance is clearly something the project acts on, and defect
4 is a fresh regression that a schema check in CI would have caught before
release.

### Scope — what this report is *not* about

To avoid conflating this with the 3.2.0 report: **the POA&M story is not in
dispute here.** The removal of the direct `hdf → oscal-poam` converter in 3.2.0
is understood to be permanent and by design, with OSCAL POA&M sourced from HDF
**Amendments** (`hdf convert --from hdf-amendments --to oscal-poam`, see
mitre/hdf-libs#104). We have verified that route works end to end on 3.4.1,
including the round trip back through `oscal-poam → hdf-amendments`.

Likewise, 3.4.1's refusal to convert a POA&M item whose risks carry no deadline
is a **correction we support** — 3.3.2 silently invented "conversion time + one
year", which was worse. This report concerns `hdf → oscal-sar` only.

## Environment

| | |
|---|---|
| hdf-cli | **3.4.1**, commit `b62c484`, built `2026-07-16T16:47:02Z` |
| Command | `hdf convert --max-size 50 --from hdf --to oscal-sar --json <input>` |
| Target schema | NIST OSCAL **v1.1.2** Assessment Results (`http://csrc.nist.gov/ns/oscal/1.1.2/oscal-ar-schema.json`) |
| Converter's own `oscal-version` | `1.1.2` (self-declared in the emitted metadata) |
| Exit code | `0` — no warning, nothing on stderr |

The converter declares `"oscal-version": "1.1.2"` in the document it emits, so
it is asserting conformance to the same schema it fails.

## Minimal reproducer

Fully synthetic; no organization-specific content. Committed at
`spec/fixtures/files/hdf/minimal-upstream-repro.hdf.json`, so anyone can
re-run this without reconstructing it from the report.

```json
{
  "platform": { "name": "minimal", "release": "1.0.0" },
  "version": "1.0.0",
  "statistics": {},
  "profiles": [
    {
      "name": "minimal-profile",
      "title": "Minimal profile",
      "version": "1.0.0",
      "sha256": "0000000000000000000000000000000000000000000000000000000000000000",
      "supports": [], "attributes": [], "groups": [],
      "controls": [
        {
          "id": "min-1",
          "title": "A control",
          "desc": "A description",
          "impact": 0.5,
          "refs": [],
          "tags": { "nist": ["AC-3"] },
          "code": "",
          "source_location": {},
          "results": [
            {
              "status": "failed",
              "code_desc": "expected something",
              "message": "it was not so",
              "start_time": "2026-06-01T00:00:00Z"
            }
          ]
        }
      ]
    }
  ]
}
```

### Reproduction

```bash
hdf convert --max-size 50 --from hdf --to oscal-sar --json minimal.hdf.json > out.json
echo $?          # 0
# validate out.json against oscal-ar-schema.json (v1.1.2) with any JSON Schema validator
```

Validation output:

```
/assessment-results/results/0: missing required properties: reviewed-controls
/assessment-results/results/0/findings/0: missing required properties: description
/assessment-results/results/0/findings/0/props/1/value: does not match pattern ^\S(.*\S)?$
/assessment-results/results/0/risks/0/characterizations/0: missing required properties: origin
```

---

## Defect 1 — `result` is missing `reviewed-controls`

**Schema:** `result` requires `["uuid", "title", "description", "start", "reviewed-controls"]`.

**Emitted:**

```json
{
  "uuid": "…", "title": "Minimal profile",
  "description": "Converted from HDF results",
  "start": "2026-06-01T00:00:00Z",
  "findings": [ … ], "observations": [ … ], "risks": [ … ]
}
```

`reviewed-controls` is absent entirely.

This is the most significant of the four: `reviewed-controls` is what states
*what was assessed*. An assessment result without it does not identify its own
scope, so a consumer cannot tell which controls the run covered — arguably the
primary purpose of an Assessment Results document.

The information is present in the source HDF: each control carries
`tags.nist` (here `["AC-3"]`), which is already used to populate the `nist`
property on the emitted finding. The same data could populate
`reviewed-controls.control-selections[].include-controls[].control-id`.

## Defect 2 — `finding` is missing `description`

**Schema:** `finding` requires `["uuid", "title", "description", "target"]`.

**Emitted:** `uuid`, `title`, `props`, `target`, `related-observations`,
`related-risks` — no `description`.

The source HDF control has a `desc` field (`"A description"`), which appears to
be dropped. The generated observation *does* carry a description
(`"[failed] expected something: it was not so"`), so descriptive text is being
synthesised elsewhere while the required field is left unset.

## Defect 3 — `characterization` is missing `origin`

**Schema:** `characterization` requires `["origin", "facets"]`.

**Emitted:**

```json
{ "facets": [ { "name": "impact", "system": "https://fedramp.gov", "value": "moderate" } ] }
```

`facets` is present and well-formed; `origin` is absent. `origin` identifies who
or what produced the characterization, and the converter already knows this —
the HDF `platform`/`profiles[].name` identify the generating tool, and OSCAL's
`origin.actors[]` with `type: "tool"` is the natural home for it.

## Defect 4 — empty `prop.value` violates the OSCAL string datatype (regression, 3.4.0)

**Schema:** `property` requires `["name", "value"]`, and `value` is
`StringDatatype`: *"A non-empty string with leading and trailing whitespace
disallowed"*, `pattern: ^\S(.*\S)?$`.

**Emitted:**

```json
{ "name": "code", "value": "" }
```

The converter maps the HDF control's `code` field to a property unconditionally.
When `code` is an empty string — common for controls that carry no inline test
code — it emits `value: ""`, which cannot satisfy a non-empty pattern.

**This is new in 3.4.0.** 3.3.2 emitted only the `nist` prop for the same input;
3.4.0 added `code` and `control-type`, and `code` carries the empty value.

The fix is to **omit the property** when the source value is empty. OSCAL props
are optional; an absent prop is correct, an empty one is invalid.

---

## Related: the validator and the converter disagree (carried over from 3.2.0)

Still present in 3.4.1, and worth resolving alongside the above:

`hdf validate --type results` requires a top-level `baselines` field, while
`hdf convert --from hdf --to oscal-sar` does not. So HDF that converts
successfully is rejected by the tool's own validator, and HDF that passes
validation is not the shape the converter documents. Consumers cannot use
`hdf validate` as a pre-flight check for `hdf convert`.

## Minor observation (not a schema violation)

The emitted `import-ap` is `{ "href": "#" }`. This passes the schema, but a
fragment-only reference points at nothing. If no assessment plan is known, a
comment in the docs on what consumers should expect here would help — currently
it looks like a populated field.

---

## Impact

Any pipeline that converts HDF to OSCAL and then validates — which is the point
of producing OSCAL — gets a document that fails on the first validating consumer,
with a `0` exit code and no diagnostic from the converter to explain why.

Because `oscal-version` is self-declared as `1.1.2`, downstream tooling has every
reason to trust the output and no reason to re-validate.

## What would unblock us

In rough priority order:

1. **`reviewed-controls` populated** from `tags.nist` (defect 1) — without it the
   document does not describe its own scope.
2. **`finding.description` populated** from the control `desc` (defect 2).
3. **`characterization.origin` populated** with the generating tool (defect 3).
4. **Empty props omitted** rather than emitted with `value: ""` (defect 4).
5. Failing all of the above, **a non-zero exit or a stderr warning** when the
   converter knowingly emits a document that does not satisfy the OSCAL version
   it declares. A loud failure is far more useful than a silent invalid document.

## Questions for maintainers

1. Is `hdf → oscal-sar` intended to emit schema-valid OSCAL 1.1.2, or a
   best-effort intermediate that consumers are expected to complete? The
   self-declared `oscal-version` suggests the former.
2. Is there a supported post-processing step that fills `reviewed-controls`,
   `finding.description` and `characterization.origin`?
3. **Is the converter validated against the NIST schemas in CI?** We suspect
   not: all four defects reproduce from a 40-line input, and 3.4.0 fixed
   `risk/statement` while introducing the empty `prop.value` in the same
   release. A single schema assertion in CI would have caught both.
4. Is the `hdf validate` / `hdf convert` disagreement on `baselines` intentional?

## Offer

If it is useful, we are happy to contribute the schema-validation test itself —
the reproducer is already reduced to 40 lines of synthetic HDF and the
assertion is one call to any JSON Schema validator against the bundled NIST
`oscal-ar-schema.json`.
