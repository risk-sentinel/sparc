<!-- markdownlint-disable MD013 -->
# hdf-cli v3.5.1: `hdf-amendments → oscal-poam` emits an OSCAL POA&M that fails the NIST OSCAL 1.1.2 schema

> **Status: FILED upstream as [mitre/hdf-libs#236](https://github.com/mitre/hdf-libs/issues/236)**
> (2026-08-21). Contains no proprietary content — the input is the four-line synthetic
> fixture already committed at `tests/api/fixtures/sample.hdf-amendments.json`.
> Tracked on our side by the issue that ships this report.
> Follows the same shape as [`hdf-libs-3.4.1-oscal-sar-upstream-report.md`](hdf-libs-3.4.1-oscal-sar-upstream-report.md),
> which became [mitre/hdf-libs#184](https://github.com/mitre/hdf-libs/issues/184).

## Summary

`hdf convert --from hdf-amendments --to oscal-poam` exits `0` and emits a document
that is **not valid OSCAL Plan of Action and Milestones**.

- **Converter:** hdf-cli **3.5.1** (`hdf version` → `hdf version 3.5.1`), the version
  SPARC currently bundles.
- **Validated against:** **every OSCAL version SPARC carries a POA&M schema for —
  1.1.1, 1.1.2, 1.1.3, 1.2.0 and 1.2.1.** Not one of them accepts the output.
- **The document declares its own version as `"oscal-version": "1.1.2"`**, so
  validating it against 1.1.2 is what the document itself asks for. This is not a
  case of SPARC checking against the wrong schema.
- **Result:** `VALID=false` on all five. **3 violations on the 1.1.x line, 7–8 on
  the 1.2.x line** — the output gets *further* from valid on newer OSCAL, not
  closer.

The converter reports success, so a consumer has no signal that the document is
unusable until it reaches a schema-validating tool. This is the identical failure
mode to the `hdf → oscal-sar` path reported in mitre/hdf-libs#184 — and note that
`oscal-sar` was **fixed** by 3.5.1, while this path was not.

## OSCAL version matrix

The **same converter output** validated against every OSCAL version SPARC has a
POA&M schema seeded for:

| OSCAL version | Valid? | Errors | New on this version |
|---|---|---|---|
| **1.1.1** | ✗ | 3 | — |
| **1.1.2** | ✗ | 3 | — (the version the document declares) |
| **1.1.3** | ✗ | 3 | — |
| **1.2.0** | ✗ | **8** | `risks[].title`, `metadata.title`, `poam-items[].title` empty-string violations; `related-risks[].risk-uuid` rejected as a **disallowed additional property** |
| **1.2.1** | ✗ | **7** | same as 1.2.0 except `related-risks[].risk-uuid` is accepted again |

Two things follow:

1. **This is not a version mismatch.** The converter stamps its own output
   `"oscal-version": "1.1.2"` and that output fails the 1.1.2 schema. Upgrading
   the target OSCAL version does not fix it — 1.2.x rejects *more*, because 1.2.x
   applies the non-empty-string datatype to `title` fields the 1.1.x schemas left
   unconstrained.
2. **`related-risks[].risk-uuid` is rejected by 1.2.0 and accepted by 1.2.1**, from
   an unchanged document. Worth flagging to NIST separately if it is not
   deliberate; it is noted here because it is visible from this same reproducer.

> SPARC bundles schemas up to **1.2.1** (`OscalSchema::SUPPORTED_VERSIONS`). If NIST
> has published a later release, it is not covered by this matrix and should be
> added before filing.

## The three defects (1.1.x line)

| # | Location | Problem |
|---|---|---|
| 1 | `risks[]` | missing required `statement` |
| 2 | `risks[].props[]` | `value: ""` violates the OSCAL non-empty string datatype |
| 3 | `metadata.parties[].name` | `name: ""` violates the same datatype |

Verbatim validator output (1.1.2):

```
/plan-of-action-and-milestones/risks/0: missing required properties: statement
/plan-of-action-and-milestones/risks/0/props/0/value: does not match pattern
/plan-of-action-and-milestones/metadata/parties/0/name: does not match pattern
```

And on 1.2.1, from the same document:

```
/plan-of-action-and-milestones/risks/0/props/0/value: does not match pattern
/plan-of-action-and-milestones/risks/0/title: does not match pattern
/plan-of-action-and-milestones/risks/0: missing required properties: statement
/plan-of-action-and-milestones/metadata/title: does not match pattern
/plan-of-action-and-milestones/metadata/parties/0/name: does not match pattern
/plan-of-action-and-milestones/poam-items/0/title: does not match pattern
```

The empty-string defects are the same root cause throughout: the converter emits
`""` wherever it has no value to carry across, and OSCAL's string datatype requires
at least one non-whitespace character. 1.2.x simply applies that datatype in more
places, so the same emptiness surfaces as more violations.

**Defects 2 and 3 are the same class as defect 4 in the SAR report** — an empty
string emitted where OSCAL requires a non-empty one. That was introduced in 3.4.0
on the SAR path; it is present on the POA&M path in 3.5.1.

**Defect 1 is the same class as the `risk/statement` violation** that 3.4.0 fixed
for SAR. The fix was not applied to the POA&M emitter.

## Reproducer

Input — the complete file, four lines of content:

```json
{
  "overrides": [
    {
      "type": "poam",
      "controlId": "AC-2",
      "rationale": "Minimal HDF Amendments fixture exercising hdf-amendments -> oscal-poam (#663)."
    }
  ]
}
```

Command:

```bash
hdf convert --from hdf-amendments --to oscal-poam --input sample.hdf-amendments.json
# exit 0
```

Output (verbatim, uuids will differ):

```json
{
  "plan-of-action-and-milestones": {
    "uuid": "ef8eca5d-a294-4600-b5c9-274cf0947d48",
    "metadata": {
      "title": "",
      "last-modified": "2026-08-21T11:18:09Z",
      "version": "1.0.0",
      "oscal-version": "1.1.2",
      "parties": [
        { "uuid": "b13d1331-90fb-4e23-82fc-28d245a7c6ad", "type": "person", "name": "" }
      ]
    },
    "import-ssp": { "href": "#" },
    "risks": [
      {
        "uuid": "8b058708-4532-43e3-8a08-2579d3214733",
        "title": "",
        "description": "",
        "props": [
          { "name": "impacted-control-id", "value": "" },
          { "name": "override-type", "value": "poam" }
        ],
        "status": "open"
      }
    ],
    "poam-items": [
      {
        "uuid": "1a5328e1-0967-4eac-bd34-6923f0147539",
        "title": "",
        "description": "",
        "related-risks": [ { "risk-uuid": "8b058708-4532-43e3-8a08-2579d3214733" } ]
      }
    ]
  }
}
```

## A second failure mode: non-amendments input is accepted silently

The converter accepts **any JSON object** and emits a document for it. Given
`{"not_hdf":"at all"}`, `{}`, or `{"hello":"world"}` it exits `0` and produces:

```json
{
  "plan-of-action-and-milestones": {
    "uuid": "…",
    "metadata": { "title": "", "last-modified": "…", "version": "1.0.0", "oscal-version": "1.1.2" },
    "import-ssp": { "href": "#" },
    "poam-items": null
  }
}
```

`poam-items: null` is a **fourth** schema violation (`is not an array`), and this
shape is arguably worse than the first: a caller who submits the wrong file is told
the translation succeeded. Only a JSON **array** (`[]`) is rejected.

## What the empty fields mean in practice

Even setting the schema aside, the emitted document carries no usable content from
the input:

- `metadata.title` is `""` although the input names a control and a rationale
- `import-ssp.href` is `"#"`, a placeholder pointing nowhere
- `risks[].title`, `risks[].description`, `poam-items[].title`,
  `poam-items[].description` are all `""`
- the input's `rationale` text appears nowhere in the output
- `props[].value` for `impacted-control-id` is `""` although the input's
  `controlId` is `"AC-2"`

So the `controlId` and `rationale` the caller supplied are dropped.

## What SPARC does about it

SPARC validates every OSCAL document it emits and refuses to return an invalid one
(#831, extended to this path in #1017). `POST /api/v1/oscal/poam_from_amendments`
therefore answers **502 Bad Gateway** naming each violation, rather than a 200
carrying a document no OSCAL tool would accept.

502 rather than 422 is deliberate: the caller's input is fine and there is nothing
they can change to fix it. The fault is in the upstream converter SPARC depends on,
which is what Bad Gateway means.

**Consequence:** the `hdf-amendments → oscal-poam` translation is effectively
unavailable on the bundled converter until this is fixed upstream. That is stated in
`docs/api/endpoints/translations.md` and in the wiki API reference so a pipeline
owner learns it from the documentation rather than from a 502.

## Converter version matrix

**Only hdf-cli 3.5.1 was tested** — the version SPARC bundles today. The OSCAL
version matrix above is complete; this one is not. The SAR report's matrix was built
by running every release from 3.2.0 forward, and the same should be done here before
filing, so the upstream issue can say when each defect appeared rather than only
that it is present now.

| hdf-cli | Converts? | Schema errors (OSCAL 1.1.2) | Notes |
|---|---|---|---|
| **3.5.1** | ✓ exit 0 | **3** | `risks[].statement` missing; two empty-string datatype violations. Not yet compared against earlier releases. |

Worth establishing before filing:

1. Whether `risks[].statement` was ever emitted on this path, or whether 3.4.0's SAR
   fix simply never reached the POA&M emitter.
2. Whether the empty-string `props[].value` arrived in 3.4.0 here too, which would
   make it one regression across both emitters rather than two.
