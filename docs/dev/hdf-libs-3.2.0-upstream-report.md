# hdf-cli v3.2.0: `hdf → oscal-sar` now rejects standard HDF (`missing baselines field`) and the direct `hdf → oscal-poam` converter was replaced by `hdf-amendments → oscal-poam`

## Summary

After upgrading from **v3.1.0 → v3.2.0**, two HDF→OSCAL conversion paths that worked in 3.1.0 now fail on standard, scanner-produced HDF:

1. **`hdf → oscal-sar` regression** — the converter now hard-requires a top-level `baselines` field that standard HDF documents (e.g. InSpec exec-json / scanner output) do not contain, failing with `invalid HDF structure: missing baselines field`.
2. **direct `hdf → oscal-poam` removed** — there is no longer a converter from raw scanner HDF to OSCAL POA&M (`no converter found for: hdf → oscal-poam`). POA&M generation was **re-sourced** to a new `hdf-amendments → oscal-poam` converter (POA&M now derives from curated amendments, not raw findings); there is no route from raw scanner HDF to a POA&M. See Issue 2 for the verified converter catalog.

Both are breaking for downstream consumers that translate tenant scanner findings (HDF) into OSCAL Security Assessment Results / POA&M.

## Environment

```json
{
  "version": "3.2.0",
  "commit": "a5b6c9a",
  "date": "2026-05-26T01:17:46Z",
  "go_version": "go1.26.3",
  "os": "linux",
  "arch": "arm64"
}
```

- Worked under: **v3.1.0**
- Broken under: **v3.2.0** (also present on the v3.3.0 line per release notes — unverified)

---

## Issue 1 — `hdf → oscal-sar` requires `baselines` (regression)

### Input
A standard HDF document — detected by the CLI as `Legacy InSpec exec-json` (confidence 100%) — with top-level keys `platform, version, statistics, profiles`. There is **no top-level `baselines` field** in standard HDF; scanners (Trivy, Brakeman, SARIF→hdf, etc.) do not emit one.

### Reproduction
```console
$ hdf convert --to oscal-sar standard.hdf.json --json
Detected: Legacy InSpec exec-json 5.22.3 (confidence: 100%)
Error: no converter found for: legacyhdf → oscal-sar

$ hdf convert --from hdf@1 --to oscal-sar standard.hdf.json --json
Error: conversion failed: hdf-to-oscal-sar: invalid HDF structure: missing baselines field

$ hdf convert --from hdf@2 --to oscal-sar standard.hdf.json --json
Error: conversion failed: hdf-to-oscal-sar: invalid HDF structure: missing baselines field
```

### Expected
Standard HDF (no `baselines`) converts to OSCAL SAR, as it did in v3.1.0.

### Actual
`422`-class failure: `invalid HDF structure: missing baselines field`. No `--from` version avoids it, and there is **no flag to supply baselines** (`--catalog` exists only for `oscal-profile`).

### Confirmed workaround
Injecting a `baselines` field makes the conversion succeed:
```console
# add "baselines": [] to the HDF, then:
$ hdf convert --from hdf@1 --to oscal-sar standard+baselines.hdf.json --json
# exit 0 — valid OSCAL SAR produced
```
A non-empty `baselines` array yields richer output.

### Questions for maintainers
- Is requiring `baselines` on **input** intentional for `hdf-to-oscal-sar`? If so, what is the expected schema/shape, and how should callers populate it for scanner HDF that has no baseline concept?
- If it should be **optional/derivable**, can the converter default to an empty/synthesized baseline (the empty-array workaround) rather than erroring?
- Alternatively, a `--baseline <file>` / `--baselines` flag (parallel to `--catalog`) would let callers supply it explicitly.

---

## Issue 2 — direct `hdf → oscal-poam` removed; POA&M is now sourced from `hdf-amendments`

### Reproduction
```console
$ hdf convert --from hdf --to oscal-poam standard.hdf.json --json
Error: no converter found for: hdf → oscal-poam
The 'hdf' format can convert to: ckl, xccdf, xml, oscal-sar, cklb, hdf, csv

# no two-step route from raw scanner HDF either:
$ hdf convert --from oscal-sar --to oscal-poam sar.json --json
Error: no converter found for: oscal-sar → oscal-poam
```

### Clarification (verified against the 3.2.0 `hdf convert --help` catalog)
POA&M conversion did **not** disappear — it **moved source format**. The 3.2.0
converter catalog lists:

```
hdf-amendments → oscal-poam      # NEW — POA&M is produced from amendments
oscal-poam → hdf                 # unchanged — POA&M back to HDF
hdf → oscal-sar                  # unchanged (now requires `baselines`, see Issue 1)
```

So in 3.2.0 an OSCAL POA&M is generated from an **HDF *amendments*** document
(curated control dispositions/overrides), not from a raw scanner HDF results
document. There is genuinely **no route from raw scanner HDF → OSCAL POA&M**,
because `hdf` only converts to `ckl, xccdf, xml, oscal-sar, cklb, hdf, csv`
(none of which is `oscal-poam` or `hdf-amendments`). This reads as a deliberate
model change: a POA&M (planned remediation) now derives from dispositions, not
raw findings.

### Impact on SPARC
- `POST /api/v1/oscal/sar_from_hdf` — fixed via `baselines: []` injection (Issue 1).
- `POST /api/v1/oscal/poam_from_hdf` — calls the now-absent `hdf → oscal-poam`;
  returns **501 Not Implemented** until/unless an endpoint is added for the new
  `hdf-amendments → oscal-poam` path. (Follow-up, not a v1.9.0 blocker.)
- `POST /api/v1/hdf/amendments_from_oscal_poam` — uses `oscal-poam → hdf`, which
  still exists; **unaffected**.

### Questions for maintainers
- Was the direct `hdf → oscal-poam` intentionally replaced by
  `hdf-amendments → oscal-poam` in 3.2.0? Is sourcing POA&M from amendments
  (rather than raw scanner HDF) the intended model going forward?
- If a raw-HDF → POA&M path is still supported, what is the invocation?

---

## Impact

Downstream services that translate tenant scanner output (HDF) into OSCAL SAR for compliance pipelines are broken by the 3.2.0 upgrade until the `baselines` workaround is applied. We bumped 3.1.0→3.2.0 to clear a pinned CVE, so reverting is undesirable. The SAR path ships with the `baselines: []` workaround; raw-HDF → POA&M has no converter (POA&M was re-sourced to `hdf-amendments`), so `poam_from_hdf` returns 501 pending a decision on whether to expose the new amendments-sourced path.

## What would unblock us

- **SAR:** confirmation that `baselines: []` is a safe/intended workaround, or a converter change to make `baselines` optional, or a `--baseline` flag.
- **POA&M:** confirmation that `hdf-amendments → oscal-poam` is the intended replacement for the direct `hdf → oscal-poam`, so we can add a `poam_from_amendments` endpoint rather than re-sourcing raw scanner HDF.
