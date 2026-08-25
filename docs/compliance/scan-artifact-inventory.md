# Scan artifact inventory — what is produced, and what assesses it

**Last measured: 2026-08-24, against run `32728653582` (`main` @ `a8991ae7`).**

This file exists because #1048 found an orphan by accident. `security.yml`
produces a lot of artifacts, and until that issue nobody had asked the
systematic question: *which of these does anything actually assess?*

The answer was "none of them", for a reason nobody had looked for. Fixing the
one orphan without writing this down would have left the next one to be found
the same way — by chance, months later.

**Re-measure this table whenever a scanner is added, removed, or re-plumbed.**
A scanner whose output reaches no gate is a logger, not a gate.

---

## The rule

> **A green CI check proves the job passed, not that the scan was clean.**

Before citing any check as evidence of a clean result, confirm the step can
actually fail. Three things turn a scanner into a logger, and all three were
present here at once:

1. `continue-on-error` on a step nothing downstream assesses
2. a threshold that is inert (default-off, unsatisfiable, or never parsed)
3. an artifact that is collected but never converted

---

## Scanner artifacts and their gate status

| Artifact | Converted to HDF | Assessed by `security_gate` | Band |
| --- | --- | --- | --- |
| `gitleaks-results.sarif` | `sarif2hdf` | yes | `gitleaks.yml` — zero tolerance, all severities |
| `brakeman-results.sarif` | `sarif2hdf` | yes | `brakeman.yml` — critical/high 0 |
| `codeql-results.sarif` | `sarif2hdf` | yes | `codeql.yml` — critical/high 0 |
| `semgrep-results.sarif` | `sarif2hdf` | yes, when the job runs | `semgrep.yml` — critical/high 0 |
| `trivy-fs-results.sarif` | `sarif2hdf` | yes | `trivy-fs.yml` — critical/high 0 |
| `trivy-container-results.sarif` | `sarif2hdf` | yes | `trivy-container.yml` — critical 0, high 2 (baseline, #1065) |
| `bundler-audit-results.json` | `bin/bundler_audit_to_hdf.rb` | yes | `bundler-audit.yml` — zero from medium up |
| `trivy-fs-sbom.cdx.json` | `cyclonedx_sbom2hdf` | inventory only | ungated — see #1064 |
| `trivy-container-sbom.cdx.json` | `cyclonedx_sbom2hdf` | inventory only | ungated — see #1064 |
| `sbom-ruby.cdx.json` | `cyclonedx_sbom2hdf` | inventory only | ungated — see #1064 |
| `grype-ruby.json` | `anchoregrype2hdf` | inventory only | ungated — impact caps at 0.5 |
| `grype-fs.json` | `anchoregrype2hdf` | inventory only | ungated — impact caps at 0.5 |
| `grype-container.json` | `anchoregrype2hdf` | inventory only | ungated — impact caps at 0.5 |
| `trivy-container-asff.json` | **no longer converted** | no | superseded by the SARIF — see below |
| `license-inventory.json` / `.md` | n/a | no | licence evidence, not a finding stream |
| `syft-container-sbom.json` | n/a | no | input to the grype scans |
| `pipeline-metrics` | n/a | no | telemetry |
| `security-scan-archive` | n/a | no | the retained evidence bundle |
| `sparc-compliance-latest` | n/a | no | cross-repo publication to sparc-iac |

"Inventory only" is a deliberate decision with a reason recorded in the
threshold file, **not** an unassessed artifact. That distinction is the whole
point of this document.

---

## What was wrong, as of 2026-08-24

Recorded so the same shapes are recognisable next time.

| # | Defect | Effect |
| --- | --- | --- |
| 1 | `security_gate` ran `saf validate threshold -F amended -T …` | **`-F` is not a saf flag** — never has been, in any released version. oclif rejected the parse, `saf_action` printed it as a *Warning* and exited 0, and the next step wrote "Security gate passed". **No HDF was ever assessed.** |
| 2 | `threshold.yml` carried top-level `brakeman:` / `gitleaks:` / `codeql:` blocks | `saf validate threshold` reads a fixed path set and never looks up a scanner name. These read as strict policy and were parsed by nothing. |
| 3 | `compliance: min: 80` applied to finding-only HDFs | Compliance is `passed/(passed+failed)`, and SARIF/CVE converters emit **no passing controls**, so it is structurally 0. Unsatisfiable for all thirteen HDFs. |
| 4 | `low: max: -1` / `none: max: -1` meant to say "unlimited" | saf compares `count > max`, so `0 > -1` **fails**. Ungated must be written by *omitting* the key. |
| 5 | `bundler-audit-results.json` never converted | The original #1048 orphan — downloaded only to be copied into the archive zip. GHSA-mvxr-6m87-mv2q rode 85 green runs, 8 of them merges. |
| 6 | `trivy2hdf` writes a **directory**, not a file | `hdf-results/trivy-container.hdf.json/` failed the amend loop's `[ -f "$hdf" ]` test, so the container scan was skipped entirely. |
| 7 | `sarif2hdf` ignores SARIF `suppressions` | Brakeman emitted 5 results, **all 5 suppressed and 0 live**, and all 5 converted to `failed`. A `high: 0` band would have blocked every build on documented design decisions. Now filtered by `bin/sarif_drop_suppressed.rb`. |
| 8 | Amendment overrides keyed only on `cve_id` | #1001 re-keyed entries to GHSA ids (what grype reports) with the CVE in `also_known_as`, and nothing read that field. Gating on trivy's CVE-keyed output would have made dispositioned findings resurface as new. |
| 9 | `Evaluate severity threshold` was a second, weaker gate | `FAIL_ON_SEVERITY` defaults to `none`, so it was inert on every trigger but a manual dispatch — and when it ran it ignored dispositions entirely. Removed. |
| 10 | `cyclonedx_sbom2hdf` takes max-of-all-sources severity | On a Red Hat image it promotes Red Hat "low"/"medium" to NVD "critical": 45 of 74 findings disagreed. Tracked as #1064. |
| 12 | SARIF cannot express "critical" | `level` is error/warning/note only, so trivy's CRITICAL and HIGH both arrive as impact 0.7. `trivy-container.yml`'s `critical.max` is inert; the `high` band carries the whole posture. Measured on CVE-2026-27820, tagged CRITICAL by Trivy, impact 0.7 in the HDF. |
| 11 | `anchoregrype2hdf` caps impact at 0.5 | No grype finding can reach a high or critical band, whatever its real severity. Tracked as #1064. |

| 13 | `hdf amend apply` no-ops on our HDFs | **Dispositions in `sparc-findings.yml` suppress NOTHING.** `hdf amend` matches `baselines[].requirements[].id` (HDF v3); SAF's converters emit `profiles[].controls[].results[]` (v2), which has no `baselines` key, so `applyOverrideToDoc` returns immediately for every override. It reports "Merged output written" and exits 0. Measured: 0 of 12 amended HDFs contain a single `notApplicable`. Filed upstream as **mitre/hdf-libs#248**. |
| 14 | `saf validate threshold` exits **0** on unparseable input | Including `{"not":"hdf"}`. A rc-only gate would score a malformed HDF as a pass. `security_gate` now also requires saf's `All validation tests passed` line. |

---

## The disposition layer does not currently suppress anything

Recorded prominently because it changes how every band in `thresholds/` should
be read, and because it is invisible from the outside.

`docs/compliance/sparc-findings.yml` → `bin/sparc_findings_to_hdf_amendments.rb`
→ `hdf amend apply` is the mechanism by which an accepted or deferred finding is
supposed to stop counting against a threshold. **It does not work in this
pipeline, at three independent points:**

1. `hdf amend apply` requires HDF **v3** (`baselines[].requirements[].id`,
   setting `effectiveStatus` and appending `statusOverrides[]`). SAF's
   converters emit **v2** (`profiles[].controls[].results[].status`), which has
   no `baselines` key — so every override hits an early `return`. Silently.
2. `hdf convert --from hdf@2 --to hdf` produces **schema-invalid** v3 from SAF
   output (`descriptions: Invalid type. Expected: array, given: null`).
3. `hdf convert --from hdf --to hdf@2` is **lossy** and drops `effectiveStatus`,
   so even a forced round-trip cannot carry the amendment back to a v2 consumer
   — and `saf validate threshold` reads only v2.

Proved by construction: the same amendments document applied to a hand-built v3
document sets `effectiveStatus=notApplicable` correctly. The register, the
generator and the amendment schema are all fine; only the results shape differs.

**Consequence for the threshold files:** every band is applied to the RAW
finding count. A band cannot currently be justified by "these are
dispositioned". Filed upstream as **mitre/hdf-libs#248**.

---

## How to check this yourself

Do not read the YAML and infer. Download the artifacts and look:

```bash
# what the run produced
gh api repos/risk-sentinel/sparc/actions/runs/<run_id>/artifacts \
  --jq '.artifacts[].name' | sort

# what the gate actually assessed (must be run inside the repo)
gh run download <run_id> -n amended-hdfs -D /tmp/amended
gh run download <run_id> -n threshold-logs -D /tmp/thresholds
ls /tmp/amended                    # every file here was assessed
cat /tmp/thresholds/*.log          # and this is what each band said
```

The `security_gate` step summary prints one table row per HDF with the
threshold file applied and the result, and the job **fails if it assessed zero
files** — a gate that assessed nothing must never report success.
