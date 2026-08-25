# Scan artifact inventory — what is produced, and what assesses it

**Last measured: 2026-08-25, against run `32840183630` (`main` @ `cfa9ed77`)** —
the first run with CI-1's gate live. The converter column and the two new
sections at the end were re-measured for CI-2 (#962, #985, #990).

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
| `gitleaks-results.sarif` | `hdf convert --to hdf@2` | yes | `gitleaks.yml` — zero tolerance, all severities |
| `brakeman-results.sarif` | `hdf convert --to hdf@2` | yes | `brakeman.yml` — critical/high 0 |
| `codeql-results.sarif` | `hdf convert --to hdf@2` | yes | `codeql.yml` — critical/high 0 |
| `semgrep-results.sarif` | `hdf convert --to hdf@2` | yes, when the job runs | `semgrep.yml` — critical/high 0 |
| `trivy-fs-results.sarif` | `hdf convert --to hdf@2` | yes | `trivy-fs.yml` — critical/high 0 |
| `trivy-container-results.sarif` | `hdf convert --to hdf@2` | yes | `trivy-container.yml` — critical 0, high 4 (baseline, #1065) |
| `bundler-audit-results.json` | `bin/bundler_audit_to_hdf.rb` | yes | `bundler-audit.yml` — zero from medium up |
| `trivy-fs-sbom.cdx.json` | `cyclonedx_sbom2hdf` (saf) | inventory only | ungated — see #1064 |
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

## Every HDF must prove it ran — the canary control

Added by CI-2 (#962, #985, #990), and the reason the converter column above
changed.

**A zero-control HDF passes every band trivially.** saf compares `count > max`,
so against a document with no controls every count is `0` and nothing can
breach. Measured on run `32840183630`: `gitleaks`, `brakeman` and
`bundler-audit` were all zero-control documents sitting under all-zero bands.

That makes a scanner that ran and found nothing **byte-identical** to a scanner
that never ran. For the secrets scanner it is the highest-consequence vacuous
pass in the pipeline: "no secrets found" and "gitleaks is broken" are the same
green check.

CI-1 hardened the gate against *assessing zero files* and against *unparseable
input*. It did not harden it against a **parseable, valid, empty** document.
That is the hole CI-2 closes, with three things that only work together:

1. **`hdf convert` emits an execution record natively.** On a clean gitleaks
   SARIF it produces one control, `gitleaks-no-findings` — *"gitleaks ran and
   reported zero findings"* — where `saf convert sarif2hdf` produced an empty
   document. It also names the scanner: `profiles[0].name` is `gitleaks`,
   `CodeQL`, `Trivy` rather than saf's uniform `"SARIF"` (#990's finding, which
   is what made this evidence anonymous in the bucket).
2. **`bin/hdf_ensure_canary.rb` supplies the same** for the scanners still
   converted by saf. It is written **only** where the scanner's input existed
   and its conversion produced output — that pairing is what makes the canary
   evidence rather than decoration. Writing it unconditionally would manufacture
   the reassurance the gate exists to test, and make the assertion a tautology.
3. **`security_gate` asserts it.** Every assessed HDF must carry either findings
   or an execution record; zero controls fails, and unreadable JSON fails. Plus
   `docs/compliance/expected-hdfs.txt` declares which scanners must be present
   at all — "assessed at least one" catches the artifact vanishing wholesale,
   but not gitleaks alone quietly dropping out while eleven others still pass.

**An absent scanner is not a clean scanner, and an empty document is not a
clean scan.**

## Why the SARIF conversions moved, and why grype/cyclonedx did not

`hdf convert` is the strategic CLI (owner decision, 2026-08-25); saf remains
where hdf cannot yet do the job. Both halves are measured, not assumed.

**`--to hdf@2` is a deliberate down-pin.** hdf-libs 3.5.1 emits v3
(`baselines[]`) by default and `saf validate threshold` cannot read v3 at all,
so an unpinned convert would take every HDF out of reach of the gate. The v2
output is accepted by saf with `All validation tests passed`, and the finding
counts are unchanged (codeql 2/8, trivy-container 4/4), so CI-1's calibration
stands. The downgrade is lossy — it drops the top-level `tool` block — but
`profiles[0].name` still carries the scanner name.

> **Shelf life:** the down-pin is harmless only while **#1067** stands.
> Amendments currently no-op, so there is no `effectiveStatus` to lose. When
> #1067 is fixed, `--to hdf@2` would drop exactly the `effectiveStatus` that
> suppression depends on. Re-evaluate the pin when #1067 closes.

**grype and cyclonedx stay on saf.** Do not "finish the migration":

- `hdf convert` **cannot read our filesystem grype scans at all** —
  `invalid Grype JSON: cannot unmarshal string into Go struct field
  GrypeSource.source.target`. grype's `.source.target` is an *object* when
  `.source.type` is `image` and a plain *string* when it is `sbom-file`;
  hdf-libs types it as a struct only. `grype-fs.json` and `grype-ruby.json` are
  both `sbom-file`.
- For the container scan it converts, but **not like-for-like**: impact spread
  `0.3/0.5/0.7` via hdf against `0/0.3/0.5` via saf (whose `anchoregrype2hdf`
  caps at 0.5), and 104 controls against 79. That is a severity and count
  change, which belongs to **#1064** — where the whole grype/cyclonedx severity
  question is tracked — not to a converter swap.

### One trap the swap introduced, and how it is handled

`hdf convert` maps SARIF `codeFlows` onto HDF `result.backtrace`. That is richer
output, but `saf validate threshold` counts with **InSpec** semantics, where a
backtrace means *the control errored while executing* rather than *this check
failed*. So a correctly converted CodeQL result lands in saf's `error` bucket
and trips `error.total.max: 0` — the band CI-1 added to catch converter
**breakage**. Measured: 3 of codeql's 8 results carry codeFlows; no other
scanner emits any.

`security.yml` drops `backtrace` on the SARIF path only. The scoping is the
justification: SARIF has no concept of an execution error — every SARIF result
is a finding — so a backtrace there can only have come from a codeFlow, and
reading it as an execution error is always wrong. For a real InSpec HDF a
backtrace *would* mean an execution error. Verified that a genuine
`status: "error"` still trips the band, and a genuine high finding still
breaches its severity band.

**Do not "fix" this by relaxing `error.total`.** That band is the only thing
standing between a broken converter and a green gate.

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
