# Per-scanner security gate thresholds

`saf validate threshold` accepts **one HDF file and one threshold file** per
invocation (`-i <hdf> -T <threshold>`). It has no folder mode and no concept of
a per-scanner section inside a single threshold file — it reads a fixed set of
paths (`compliance.*`, `<status>.total`, `failed.<severity>.{min,max}`) and
ignores everything else.

That matters, because `docs/compliance/threshold.yml` used to carry top-level
`brakeman:` / `gitleaks:` / `codeql:` / `trivy-fs:` / `trivy-container:` blocks
which read as strict per-scanner policy and **were never parsed by anything**
(#1048). This directory makes that intent real: one file per HDF, applied by
the `security_gate` loop in `.github/workflows/security.yml`.

## How a file is chosen

For `amended/<name>.hdf.json`, the gate uses `thresholds/<name>.yml` if it
exists and `thresholds/default.yml` otherwise. A new scanner therefore gets the
conservative default until someone makes a deliberate decision about it.

## Why no `compliance.min`

`compliance` is `passed / (passed + failed + error)`. Finding-only HDFs — every
SARIF-derived scanner, and every SBOM/CVE converter we run — emit **no passing
controls at all**, so their compliance is structurally `0`. The previous global
`compliance: min: 80` was unsatisfiable by construction for all thirteen of our
HDFs; it is not carried forward. Compliance minimums belong on profile-style
HDFs (InSpec baselines), not on scanner output.

## Baselines are a ratchet

Where a band is set above zero it records a **measured** residual, with the date
and commit it was measured on. Those numbers may only ever go **down**. Raising
one is a policy change and needs the same review as any other compliance
decision — say so on the PR rather than editing it quietly.

## Severity source

Severity here means the HDF `impact` bucket (`>=0.9` critical, `>=0.7` high,
`>=0.4` medium, `>=0.1` low). What produces that impact differs per converter,
and the converters do not agree with each other — see **#1064**. In particular
the CycloneDX path takes the maximum rating across up to seven sources
(NVD, Red Hat, GHSA, Ubuntu, …) rather than the OS vendor's rating for the OS
vendor's own image, and `anchoregrype2hdf` caps impact at `0.5`. Read each
file's own comment before trusting its numbers.
