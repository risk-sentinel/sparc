# Which severity is authoritative for gating

**Decided 2026-08-27 (#1064). Applies to every scanner output that reaches
`security_gate`.**

A vulnerability does not have one severity. It has as many as there are parties
willing to rate it, and they disagree — routinely, and by more than one band.
This file says which one SPARC gates on and why, so that a threshold breach
means something specific rather than "whichever source scored highest today".

---

## The rule

> **The severity that governs is the one assigned by the party who ships the
> code we are running.**

Concretely, by ecosystem:

| What the finding is against | Authoritative source | Why |
| --- | --- | --- |
| `pkg:rpm/redhat/*` — the UBI9 base and its OS packages | **Red Hat** | Red Hat backports fixes and assesses exploitability against their own build. An NVD base score describes upstream code we are not running. |
| `pkg:gem/*` — Ruby dependencies | **ruby-advisory-db / GHSA** | The ecosystem's own advisory data, which is what `bundler-audit` and Dependabot act on. |
| `pkg:golang/*` — the vendored `hdf` binary's dependencies | **Go vulnerability database / GHSA** | Same reasoning: the ecosystem that ships the code. |
| Anything else | **NVD** | Fallback, not preference. |

**This is a policy decision, not a tooling detail.** It is recorded here rather
than in a threshold file because it governs all of them.

## What it is not

It is **not** "take the lowest score". It is "take the score from whoever is
responsible for the artifact". Sometimes that is *higher* than NVD — a vendor
who knows their build ships a component in an exploitable configuration may rate
above the generic base score, and that rating governs too.

## Why max-of-all-sources is the wrong reading

Measured 2026-08-24 on `main@a8991ae7`, run `32728653582`. The container SBOM
carries 74 vulnerabilities, each with ratings from up to seven sources.
`cyclonedx_sbom2hdf` resolves them by taking the **maximum**, which is almost
always NVD's worst case:

| Severity | Max-of-all-sources | Vendor-authoritative |
| --- | --- | --- |
| critical | **3** | **1** |
| high | **25** | **3** |
| medium | 41 | 31 |
| low | 5 | 39 |

**45 of 74 findings disagree between the two readings.** Two examples on a Red
Hat image:

| CVE | Package | Red Hat | NVD | HDF impact via max-of-sources |
| --- | --- | --- | --- | --- |
| CVE-2026-31789 | `openssl-libs` | **low** (5.8) | critical (9.8) | **1.0** |
| CVE-2026-6653 | `libxml2` | **medium** (5.9) | critical (9.8) | **0.98** |

Gating on that would fail builds on findings Red Hat does not consider critical,
and — because the band is a ratchet that may only go down — would enshrine two
phantom criticals and twenty-two phantom highs permanently.

## How this is implemented

| Artifact | Severity source | Gated? |
| --- | --- | --- |
| `trivy-container-results.sarif` | Trivy's **vendor-preferred** severity — Red Hat's for RPMs | **yes** — `thresholds/trivy-container.yml` |
| `trivy-fs-results.sarif` | vendor-preferred | **yes** — `thresholds/trivy-fs.yml` |
| `*-sbom.cdx.json` (CycloneDX) | max-of-all-sources | **no** — inventory and licence evidence only |
| `grype-*.json` | Anchore, and see the ceiling below | **no** — inventory only |
| `bundler-audit-results.json` | ruby-advisory-db | **yes** — `thresholds/bundler-audit.yml` |

`trivy image --severity CRITICAL,HIGH` reports **4** findings for the image
where the SBOM path reports 28. Same image, same run.

## The grype ceiling — settled

`anchoregrype2hdf` caps `impact` at **0.5**, so no grype finding can reach a
high or critical band whatever its real severity. Two scanners, same image,
incompatible scales.

**Decision: grype is inventory-only and is not a gating input.** This is not a
workaround for the ceiling — it follows from the rule above. Grype's severity is
its own, not the vendor's, so it would not govern even if the scale were
correct. Its threshold files therefore carry only `error.total.max: 0`, which
gates converter *breakage* rather than findings.

Rebasing the ceiling was considered and rejected: it would make grype look like
a gate while still reporting a severity this policy does not recognise.

## Two constraints that limit what a band can express

**SARIF cannot express "critical".** `level` is `error`/`warning`/`note` only,
so Trivy's CRITICAL and HIGH both arrive at impact 0.7. `critical.max` is
therefore **inert** on any SARIF-derived scanner and the `high` band carries the
whole posture. Verified on CVE-2026-27820, tagged CRITICAL by Trivy and landing
at 0.7.

**Every band is a raw count.** Per #1067, `hdf amend apply` no-ops on the HDF v2
shape our converters emit, so no disposition currently suppresses anything. A
band cannot be justified by "these are dispositioned" until that is fixed.

## When this changes

Re-open the decision if any of these become true:

- a converter starts resolving severity per-source rather than by maximum, which
  would make the SBOM path gateable
- Trivy stops applying vendor-preferred severity by default
- SPARC ships on a base whose vendor does not publish its own ratings, leaving
  NVD as the only source

Related: #1048 (the gate that never ran) · #1064 (this decision) · #1067 (raw
counts) · #862 (SBOM-vs-image coverage) · `scan-artifact-inventory.md`
