# SPARC's Own Compliance Posture

_How SPARC implements the controls it asks you to document, where that evidence
lives, and how to consume it. This page is about **SPARC the product**, not about
using SPARC to document **your** system — for that, start at
[Getting Started](Getting-Started)._

SPARC is built to be deployed into a FedRAMP or DoD authorization boundary, so
the first question a prospective operator or assessor asks is the one this page
answers: what does SPARC implement itself, what does it hand to the
infrastructure layer, and what does it inherit from the cloud provider?

The artifacts behind every number here ship in the repository and are linked
throughout. Nothing on this page is a claim you have to take on trust — each one
points at the file it came from.

> **SPARC is not the authority for its own authorization.** It is a translation
> engine (see [Adopting OSCAL](Adopting-OSCAL)). These artifacts are inputs to an
> authorization package assembled by the operator who deploys it, alongside
> infrastructure and organizational evidence SPARC neither holds nor asserts.

---

## The baseline, and what is actually covered

**NIST SP 800-53 Rev 5, HIGH impact.** HIGH was chosen because
[sparc-iac](https://github.com/risk-sentinel/sparc-iac) committed to it for
FedRAMP readiness, HIGH is a superset of Moderate and Low, and targeting it once
removes rework for lower-baseline customers.

The Rev 5 HIGH baseline resolves to **370** controls and enhancements across 18
families. Measured 2026-09-16, the mapping document lists **313** controls, of
which **286** are HIGH baseline controls:

| | Count |
|---|---|
| HIGH baseline controls and enhancements | 370 |
| Listed in SPARC's mapping | 313 |
| — of those, HIGH baseline controls | 286 |
| — of those, outside the baseline (PM, PT, enhancements beyond HIGH) | 27 |
| **HIGH baseline controls not yet listed** | **84** |

That last row is stated rather than rounded away. The mapping is a live document
and the gap is tracked; a control absent from it is not a control silently
claimed.

Of the 313 listed, by implementation status:

| Status | Count |
|---|---|
| Implemented | 150 |
| Planned | 101 |
| Partial | 31 |
| CSP Inherited | 29 |
| N/A | 2 |

These tables are recomputed from the document's own rows by
`spec/compliance/control_mapping_spec.rb`, which fails the build when the
summary and the rows disagree — they had drifted by 66 controls before that
check existed.

---

## Who owns which control

Every control in the mapping carries a **Responsibility**, because "SPARC is
compliant" is not a meaningful claim on its own — most of a HIGH baseline is not
application code.

| Responsibility | Meaning | Count |
|---|---|---|
| Hybrid | Shared across two or more of the below | 104 |
| Application (SPARC) | Implemented in this repository's code | 75 |
| Organizational Policy | Requires policy documents the deploying organization owns | 70 |
| Infrastructure (sparc-iac) | Terraform / IaC in the sparc-iac repository | 35 |
| CSP Inherited | Cloud service provider responsibility (AWS/Azure) | 28 |
| N/A | Does not apply to this system type | 1 |

The split matters when you read the evidence. SPARC's repository can only ever
demonstrate the **Application** portion and its half of the **Hybrid** rows.
`sparc-iac` carries the infrastructure side and publishes its own CDEFs; policy
and CSP rows are yours and your provider's respectively.

The two repositories are wired together rather than merely adjacent: on every
push to `main`, SPARC's security workflow publishes a `sparc-compliance-latest`
artifact — HDF-normalized scan results, the OSCAL CDEFs, a CycloneDX SBOM, and a
manifest carrying the run ID and git SHA — and notifies `sparc-iac` by
`repository_dispatch`, which combines them with the infrastructure CDEFs to
produce a complete SSP.

---

## Where the evidence lives

All of it is in the repository, versioned with the code it describes. `docs/` is
the right home for technical reference that ships next to the code; this page is
the route to it.

| Artifact | What it is |
|---|---|
| [`docs/compliance/nist-sp800-53-rev5-mapping.md`](https://github.com/risk-sentinel/sparc/blob/main/docs/compliance/nist-sp800-53-rev5-mapping.md) | The control mapping — 313 rows, each with Responsibility, Status, an implementation narrative, and the source files that implement it |
| [`docs/compliance/oscal/cdefs/`](https://github.com/risk-sentinel/sparc/tree/main/docs/compliance/oscal/cdefs) | 5 OSCAL component definitions, 71 implemented requirements — the machine-readable form |
| [`docs/compliance/README.md`](https://github.com/risk-sentinel/sparc/blob/main/docs/compliance/README.md) | The process guide: how these are maintained, and the sparc-iac split |
| [`docs/compliance/sparc-findings.yml`](https://github.com/risk-sentinel/sparc/blob/main/docs/compliance/sparc-findings.yml) | Live CVE and scanner-finding dispositions, with review cadence by severity |
| [`docs/compliance/thresholds/`](https://github.com/risk-sentinel/sparc/tree/main/docs/compliance/thresholds) | Per-scanner severity bands the CI security gate evaluates every pull request against |

Control implementations in the code carry inline NIST control comments naming
the controls they satisfy, so the mapping's "Source Files" column can be read in
both directions.

---

## The five component definitions

These are the same artifact type SPARC ingests — which makes them directly
useful rather than merely informative.

| Component definition | Implemented requirements |
|---|---|
| `component-definition-authentication.json` | 20 |
| `component-definition-security-scanning.json` | 18 |
| `component-definition-audit.json` | 13 |
| `component-definition-session-mgmt.json` | 11 |
| `component-definition-config-mgmt.json` | 9 |
| **Total** | **71** (59 distinct control ids) |

They are emitted at `OscalSchema::DEFAULT_VERSION` — the OSCAL version SPARC
itself exports at, currently **v1.2.2** — and validated against the bundled NIST
schema for that version on every build, so the stamp cannot fall behind the
product.

### Loading them into SPARC

If you run SPARC, you can inherit SPARC's own implementation statements into
your SSP rather than retyping them:

1. Download the five files from
   [`docs/compliance/oscal/cdefs/`](https://github.com/risk-sentinel/sparc/tree/main/docs/compliance/oscal/cdefs),
   or take the `cdefs/` directory out of the published `sparc-compliance-latest`
   artifact.
2. Import them as component definitions — see
   [Component Definitions](User-Guide-Component-Definitions) for the import flow,
   or `POST /api/v1/cdef_documents` for the API path
   ([API Reference](API-Reference)).
3. On your SSP, use **Import CDEF components** to pull the components into the
   plan. The implementation prose arrives with them, attributed to SPARC as the
   providing component.

What you inherit is SPARC's claim about SPARC. Your assessor will still expect
your own statement of how the deployed instance is configured — inheritance
carries the provider's narrative, not your configuration.

---

## Keeping it honest

Three mechanisms exist specifically because compliance documentation rots
quietly:

- **The security gate.** Every pull request is evaluated against the per-scanner
  thresholds in `docs/compliance/thresholds/`, after applying the dispositions in
  `sparc-findings.yml`. Dispositions have a severity-based review cadence — HIGH
  30 days, MEDIUM 60, LOW 120 — and a stale disposition blocks the merge.
- **The version drift check.** A shipped CDEF that declares an OSCAL version
  other than the one SPARC exports at fails the build. The five files sat at
  v1.1.2 for three releases after the product moved to v1.2.2, and nothing
  objected, because v1.1.2 was still a valid bundled schema.
- **The statistics check.** The mapping's summary tables are recomputed from its
  own rows on every build.

When security-critical code changes, the relevant CDEF and the mapping row are
updated in the same change as the code. That is a repository rule, not a
convention — see [Contributing](Contributing) for the process.

---

## Related

- [Adopting OSCAL](Adopting-OSCAL) — the decisions a boundary makes on the way in
- [Architecture](Architecture) — how SPARC is built
- [Authentication and MFA](Authentication-and-MFA) — the IA-family implementation in detail
- [RBAC](RBAC) and [Data Isolation](Data-Isolation) — the AC-family implementation
- [Component Definitions](User-Guide-Component-Definitions) — working with CDEFs
- [Configuration Reference](Configuration) — the settings that change posture
