<!-- markdownlint-disable MD013 -->

# SPARC Compliance Documentation

This directory contains NIST SP 800-53 Rev 5 compliance documentation for the
SPARC application, targeting the **HIGH baseline** (370 controls). The control
mapping currently lists 313 controls across 20 families, 286 of them from the
HIGH baseline — see its Summary Statistics for the measured coverage.

> **Reading this from outside the repository?** The public entry point is
> [SPARC's Compliance Posture](https://github.com/risk-sentinel/sparc/wiki/Compliance-Posture)
> on the wiki — what SPARC implements, what it hands to `sparc-iac`, what is
> inherited from the CSP, and how to load these CDEFs into SPARC and inherit
> them into your own SSP. This directory is the technical reference behind it.

---

## Directory Structure

```
docs/compliance/
├── README.md                                 # This file
├── nist-sp800-53-rev5-mapping.md             # Central control mapping document
└── oscal/
    └── cdefs/
        ├── component-definition-authentication.json
        ├── component-definition-audit.json
        ├── component-definition-config-mgmt.json
        ├── component-definition-security-scanning.json
        └── component-definition-session-mgmt.json
```

## How This Connects to sparc-iac

SPARC's compliance story spans two repositories:

| Repository | Responsibility | Controls Covered |
|---|---|---|
| **sparc** (this repo) | Application-level controls | ~100 (AC, AU, IA, CM, SC, SI, RA) |
| **sparc-iac** | Infrastructure controls (Terraform) | ~41 (via CDEFs for ECS, EC2, Azure) |
| **AWS/Azure CSP** | Physical and environmental | ~87 (PE family, inherited) |
| **Organizational** | Policy and procedural | ~54 (AT, PS, PL, PM families) |

```
SPARC App CDEFs ─────┐
                     ├──> sparc-iac SSP Assembly ──> FedRAMP Package
sparc-iac CDEFs ─────┘
                     │
Security scan HDF ───┘ (via sparc-compliance-latest artifact + repository_dispatch)
```

### Integration Points

1. **Application CDEFs** (`docs/compliance/oscal/cdefs/`) document what SPARC the app
   implements. sparc-iac's SSP assembly script downloads and merges these with
   infrastructure CDEFs to produce a complete SSP.

2. **`sparc-compliance-latest` artifact** — Published by the `publish_for_sparc_iac` job
   in `.github/workflows/security.yml` on every push to `main`. Bundles:
   - `hdf/` — HDF-normalized scan results (Brakeman, CodeQL, Trivy, Gitleaks, etc.)
   - `cdefs/` — OSCAL component definitions (5 files, 71 implemented requirements)
   - `sbom/` — CycloneDX SBOM for supply chain evidence
   - `oscal-metadata.json` — System ID and party metadata
   - `manifest.json` — File inventory with run ID and git SHA for traceability

3. **`repository_dispatch` notification** — After publishing the artifact, SPARC sends a
   `sparc-compliance-updated` event to `risk-sentinel/sparc-iac` with the `run_id` in
   the payload. sparc-iac can then download the artifact via the GitHub REST API:
   ```bash
   # List artifacts for the run
   gh api repos/risk-sentinel/sparc/actions/runs/{run_id}/artifacts
   # Download the compliance bundle
   gh api repos/risk-sentinel/sparc/actions/artifacts/{artifact_id}/zip > compliance.zip
   ```
   **Required secret:** `SPARC_IAC_DISPATCH_TOKEN` — a GitHub PAT with `contents:read`
   on sparc and `contents:write` on sparc-iac.

4. **System ID** in `.github/oscal-metadata.json` (`"system-id": "sparc-application"`)
   allows sparc-iac to correlate application evidence with the correct SSP.

---

## Maintaining This Documentation

### When to Update the Central Mapping

Update `nist-sp800-53-rev5-mapping.md` when:

- A new security feature is implemented (add the control mapping)
- An existing control implementation changes (update the code location)
- A control's status changes (e.g., from "Planned" to "Implemented")
- Infrastructure changes affect shared-responsibility controls

### Adding Inline Compliance Comments

When touching security-critical code, add or update the NIST control reference
comment block at the top of the file or module:

```ruby
# NIST 800-53 Controls:
#   AC-2 Account Management (role assignment enforcement)
#   AC-3 Access Enforcement (authorize_permission! gates)
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
```

**Currently annotated files:**

- `app/controllers/concerns/authentication.rb` (IA-2, AC-11, AC-12, IA-11)
- `app/controllers/concerns/authorization.rb` (AC-2, AC-3, AC-5, AC-6)
- `app/controllers/concerns/api_authentication.rb` (IA-2, IA-5, SC-13)
- `app/models/user.rb` (AC-2, IA-4, IA-5)
- `app/models/api_token.rb` (IA-5, SC-13)
- `app/models/audit_event.rb` (AU-2, AU-3, AU-9, AU-12)
- `app/models/sparc_config.rb` (CM-6, CM-7, AC-7, AC-11, IA-5)
- `app/services/ldap_auth_service.rb` (IA-2, IA-5)
- `app/controllers/omniauth_callbacks_controller.rb` (IA-2, IA-8)
- `config/environments/production.rb` (SC-8, SC-13, SC-28)

### Updating OSCAL CDEFs

CDEFs in `oscal/cdefs/` follow the OSCAL component-definition format at
`OscalSchema::DEFAULT_VERSION` — the version SPARC itself exports at, currently
**v1.2.2**. `spec/compliance/cdef_artifacts_spec.rb` fails if a shipped CDEF
declares anything else, so the stamp cannot fall behind the product again. When
updating, ensure:

1. Each `implemented-requirement` has a unique UUID
2. The `remarks` field references specific code files and line ranges
3. The `source` field points to the NIST HIGH baseline resolved profile catalog
4. Run validation: `OscalSchemaValidationService.validate!(:component_definition, data)`

### Security Scanning Evidence

SPARC's CI pipeline (`.github/workflows/security.yml`) automatically generates
evidence for these controls on every PR:

| Control | Scanner | Output |
|---|---|---|
| RA-5 Vulnerability Scanning | Trivy FS + Container, CodeQL | SARIF + HDF |
| SI-2 Flaw Remediation | Trivy CVE, bundler-audit | SARIF + HDF |
| SI-3 Malicious Code Protection | Gitleaks, Trivy Container | SARIF + HDF |
| SI-10 Input Validation | Brakeman SAST | SARIF + HDF |
| CM-8 System Component Inventory | CycloneDX SBOM | JSON + HDF |

All results are normalized to HDF via SAF CLI and enriched with OSCAL metadata
from `.github/oscal-metadata.json`.

### Which SBOM gates the build, and why (#873)

Three SBOMs are produced, and they are **not interchangeable**:

| SBOM | Producer | Used for |
|---|---|---|
| `sbom-ruby.cdx.json` | cdxgen | Ruby dependency scanning |
| `trivy-container-sbom.cdx.json` | Trivy (CycloneDX) | **SAF/HDF pipeline and the license inventory** |
| `syft-container-sbom.json` | Syft (syft-json) | **The Grype `--fail-on` gate** |

The container **gate** consumes the **Syft** SBOM. Grype is Syft's sibling and
reads its native format losslessly; a Syft SBOM of the image reproduces a direct
`grype <image>` scan exactly — 207 findings each, zero delta in both directions
when measured on the shipped image.

The Trivy CycloneDX SBOM cannot drive the gate correctly, and was doing so until
#873. Measured on the same image:

- It conveys no `sourceRpm` mapping. Red Hat files advisories against the
  **source** package (`sqlite-libs` ships from `sqlite`), so without it Grype
  cannot map binary to source, falls back to CPE/NVD matching, and **117
  findings — 18 of them Critical/High — become invisible to the gate**. Deleting
  `metadata.sourceRpm` from a Syft SBOM reproduces exactly that loss, which is
  what identifies it as the mechanism.
- It also lists packages that are **not in the final image** — versions carried
  by superseded layers — which surface as phantom findings, including
  "Criticals" for gem versions the image does not contain.

Trivy's SBOM is still generated and still feeds SAF/HDF and the license
inventory, where its richer license metadata is the reason it exists. It simply
no longer decides whether the build passes.

A guard in `trivy_container_scan` fails the job if the Syft SBOM stops carrying
`sourceRpm` mappings or a resolvable `distro` block, because the failure mode
this fixes was **silent**: the gate stayed green while seeing under half the
image, so the only symptom was an absence.

> **Method trap.** Grype auto-discovers `.grype.yaml` from the working
> directory. A stray one silently applies ignore rules and contaminates
> measurements. Always pass `--config` explicitly and keep the CWD clean.

---

## Deviations (FedRAMP FP / RA / OR)

A finding in `sparc-findings.yml` that cannot simply be remediated carries a
`deviation:` block. This uses the FedRAMP deviation vocabulary and the OSCAL
risk lifecycle — **do not invent terms here**, because these entries become
POA&M and SAR evidence.

### Deviation types

| Type | Meaning | Requires |
|---|---|---|
| `false_positive` | The finding is **wrong** — the scanner misidentified the package or version | Must **not** carry mitigating factors; there is nothing to mitigate |
| `risk_adjustment` | The finding is **right** and we are not exploitable — the affected package is present, but the vulnerable code cannot be reached | At least one `mitigating_factors` entry |
| `operational_requirement` | A weakness that must remain open | `operational_justification` |

Calling a real, correctly-identified CVE a "false positive" asserts something
untrue in an auditable artefact. If the package is genuinely present at the
affected version, it is a **risk adjustment**, not a false positive.

### How a deviation gates the build

The deviation's `risk_status` — **not** the disposition — decides the emitted
HDF status. the threshold files need no knowledge of deviations:

| `risk_status` | HDF status | Effect |
|---|---|---|
| `deviation-requested` | `failed` | Counts toward the scanner's threshold file. A CRITICAL breaches `failed.critical.max: 0` → **build red** |
| `deviation-approved` | `notApplicable` | Suppressed from the residual → build green |

An unapproved deviation on a critical is *supposed* to be loud. An approved one
is a signed-off risk decision.

### The approval flow

Approval is an Authorizing Official decision, so it must be a real, attributable
act — never something the PR asserts about itself.

```
1. PR adds the deviation as `deviation-requested`
2. Amendments emit `failed` → CRITICAL breaches threshold → build RED
3. Red blocks the merge for anyone without admin rights
4. An authorised approver (admin/maintain) approves
5. The approval is recorded: who, when, which PR, and by what mechanism
6. Gate goes GREEN → merge
```

`scripts/ci/check_deviation_approvals.rb` enforces this. It does **not** trust
the approval fields: an entry marked `deviation-approved` must be corroborated
against a real approving review by someone holding `admin`/`maintain`.
Hand-editing the YAML cannot satisfy it, because the review either exists in the
API or it does not.

### `approval_mechanism` — how the approval was obtained

| Value | Strength |
|---|---|
| `review` | **Strong.** An authorised reviewer submitted an approving review — a distinct, attributable act |
| `approve-deviation-comment` | **Strong.** An authorised user issued `/approve-deviation` on the PR — also distinct and attributable, and it works when the admin is the author |
| `admin-merge-bypass` | **Weaker.** An admin merged past the red gate |

**Why the bypass path exists:** GitHub does not permit anyone to approve their
own pull request. In a single-admin repository the admin is usually also the
author, so the review path is structurally unreachable and the only route is an
admin merge. Rather than let that happen silently, the register must *declare*
it. The gate then verifies the named approver holds authority — but it cannot
verify a separate approval event occurred, and it says so loudly in the log.

This is deliberately recorded in the evidence so the artefact states the
strength of its own provenance.

### `/approve-deviation` — the route that works when the admin is the author

**A comment is not a review**, so GitHub's self-approval restriction does not
apply to it, while it remains a distinct act with an author and a timestamp.
That is what makes it a real replacement for the bypass rather than a relabel.

```
1. PR adds the deviation as `deviation-requested`  → gate RED
2. An admin comments  /approve-deviation           → works even as the author
3. The workflow verifies the commenter holds admin/maintain,
   flips the state, stamps who/when/which-PR/mechanism, and pushes
4. The push re-fires the FULL pipeline, so nothing is left stale
5. Everything re-evaluates against the approved state → GREEN
```

The gate corroborates each mechanism against the artefact it names — a `review`
against the PR's review list, an `approve-deviation-comment` against its comment
list. A register entry claiming either without the matching evidence fails.

**Two properties hold this up, and neither is optional:**

- **The command lives in its own workflow, which never touches the PR's code.**
  `issue_comment` is a privileged trigger — secrets and write access are in
  scope — so it is kept out of `deviation-approval.yml` entirely, because that
  file checks out the PR head in order to push back to it. The command runs
  from `deviation-approve-command.yml`, where:

  - the checkout has **no `ref`**, so it is the default branch, and the Ruby
    version, the bundle and the approval scripts all come from there;
  - the PR's findings file is read through the **Contents API** as data, never
    fetched as a git ref, so no untrusted object reaches the workspace;
  - the resulting commit is written through the Contents API too, **server
    side**, so nothing is checked out even in order to commit it.

  Two weaker attempts preceded this, and CodeQL was right to reject both.
  Restoring only the scripts from base does not help: `ruby/setup-ruby` reads
  the checked-out `.ruby-version` and bundler reads checked-out config long
  before any of our code runs. Nor does arguing that the ref expression is
  empty on this trigger — the analysis is static, and a security property that
  cannot be seen in the file is not one worth relying on.
- **`types: [created]` only.** An edited comment must not manufacture an
  approval retroactively.

**The push uses a GitHub App token, not `GITHUB_TOKEN`.** A `GITHUB_TOKEN` push
does not trigger workflow runs, so the approval would land with every other
check left stale. The step refuses rather than degrading when
`SPARC_DEVIATION_APP_ID` / `SPARC_DEVIATION_APP_PRIVATE_KEY` are absent.

#### Provisioning the App

The push needs a credential that **triggers workflow runs**, which `GITHUB_TOKEN`
does not. One GitHub App, one permission.

1. **Create it.** GitHub → the `risk-sentinel` org → *Settings* → *Developer
   settings* → *GitHub Apps* → **New GitHub App**.
   - *Name*: anything unambiguous, e.g. `SPARC Deviation Approval`
   - *Homepage URL*: the repository URL (unused, but required)
   - **Untick *Webhook → Active*.** The App is never called; it only issues
     tokens. Leaving it on means GitHub retries deliveries to nothing.
   - *Repository permissions*: **Contents → Read and write**. That is the only
     one. It needs no issues, no pull-requests, no metadata beyond the default.
   - *Where can this GitHub App be installed*: **Only on this account**
2. **Record the App ID** shown after creation — a short number, not a secret.
3. **Generate a private key** on the same page. It downloads a `.pem` once; if
   it is lost, generate another and delete the old one.
4. **Install it.** *Install App* → the `risk-sentinel` account → **Only select
   repositories** → `sparc`. *Creating the App does not install it*, and an
   uninstalled App mints no token.
5. **Add two repository secrets** (repo → *Settings* → *Secrets and variables* →
   *Actions*):

   | Secret | Value |
   |---|---|
   | `SPARC_DEVIATION_APP_ID` | the numeric App ID from step 2 |
   | `SPARC_DEVIATION_APP_PRIVATE_KEY` | the **entire** `.pem`, including the `-----BEGIN` and `-----END` lines and the trailing newline |

**If the key is pasted without its header/footer lines the token mint fails with
a signing error**, which reads like a permissions problem and is not one.

Until both secrets exist the workflow **refuses** rather than falling back to
`GITHUB_TOKEN` — a token that pushes without re-triggering anything would land
the approval and leave every other check stale, which is how a gate stops
meaning anything.

**Why an App rather than a PAT:** it is not tied to a person, it rotates
cleanly, and its reach is one permission on one repository. A PAT is accepted as
a fallback (`security.yml` already uses `SPARC_IAC_DISPATCH_TOKEN` for
cross-repo dispatch) but carries its holder's access with it.

`admin-merge-bypass` is **not yet retired**. It cannot be proven redundant until
this flow has run on `main`, and the entries approved that way still depend on
it being understood.

### What went wrong before this existed

PR #863 merged eight deviations marked `deviation-approved` — including
CVE-2026-51302 at CVSS 10.0 — recording an approval that never happened. The
gate correctly failed (`reviewDecision` was `REVIEW_REQUIRED`; the only review
was a `COMMENTED`), but `enforce_admins: false` let the merge proceed anyway.
All eight were suppressed from the threshold residual on the strength of a claim
nobody had made. That is the failure mode this whole flow exists to prevent, and
why the mechanism is now declared rather than assumed.

---

## Baseline Selection Rationale

**NIST SP 800-53 Rev 5 HIGH** (370 controls and enhancements) was selected because:

- sparc-iac committed to HIGH baseline for FedRAMP readiness
- HIGH is a superset of Moderate (325) and Low (135)
- Targeting HIGH once eliminates rework for lower-baseline customers
- Aligns with DoD Impact Level requirements

The resolved profile catalog is maintained at:
`https://raw.githubusercontent.com/usnistgov/oscal-content/main/nist.gov/SP800-53/rev5/json/NIST_SP-800-53_rev5_HIGH-baseline-resolved-profile_catalog.json`

---

## CI/CD Compliance Pipeline

### PR Checks (`compliance.yml`)

When PRs touch compliance-relevant files (`docs/compliance/**`, `.github/oscal-metadata.json`,
security-critical controllers/concerns/initializers), the `Compliance Check` workflow:

1. Validates all 5 CDEF JSON files parse correctly
2. Checks completeness (all expected CDEFs present)
3. Uploads CDEFs as a PR artifact for review

### Main Branch (`security.yml → publish_for_sparc_iac`)

On merge to main, the `publish_for_sparc_iac` job:

1. Bundles CDEFs + HDF scan results + SBOMs + OSCAL metadata + manifest
2. Uploads as `sparc-compliance-latest` GitHub artifact (90-day retention)
3. Syncs to S3 under the canonical evidence layout (#741, sparc-iac#537):
   `s3://<security-artifacts-bucket>/<EVIDENCE_BOUNDARY>/{<date>,latest}/sparc/`,
   where the archive's own subdirectories (`hdf/ sarif/ asff/ sbom/ grype/`) are the
   `<source>` level. The boundary comes from the `EVIDENCE_BOUNDARY` org variable —
   `risk-sentinel` as of sparc-iac#715 — and the emit refuses to run if it is unset
   (#1153). Per-commit traceability rides the dispatch `git_sha`, not the key.
4. Fires `repository_dispatch: sparc-compliance-updated` to sparc-iac

### AWS OIDC Trust Policy

The S3 upload uses GitHub Actions OIDC federation. The IAM role
(`sparc-iac-github-actions`) trust policy must allow the SPARC repo:

```json
{
  "Effect": "Allow",
  "Principal": {
    "Federated": "arn:aws:iam::<AWS_ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
  },
  "Action": "sts:AssumeRoleWithWebIdentity",
  "Condition": {
    "StringLike": {
      "token.actions.githubusercontent.com:sub": [
        "repo:risk-sentinel/sparc-iac:*",
        "repo:risk-sentinel/sparc:ref:refs/heads/main"
      ]
    }
  }
}
```

### Required GitHub Secrets/Variables

| Name | Type | Purpose |
|------|------|---------|
| `AWS_ROLE_ARN` | Secret | IAM role ARN for OIDC assumption |
| `AWS_REGION` | Variable | AWS region (default: us-east-1) |
| `COMPLIANCE_S3_BUCKET` | Variable | S3 bucket for artifact storage |
| `SPARC_IAC_DISPATCH_TOKEN` | Secret | PAT for cross-repo dispatch to sparc-iac |

---

## References

- [NIST SP 800-53 Rev 5](https://csrc.nist.gov/publications/detail/sp/800-53/rev-5/final)
- [OSCAL Component Definition Model](https://pages.nist.gov/OSCAL/concepts/layer/implementation/component-definition/)
- [sparc-iac FedRAMP 20x Docs](https://github.com/risk-sentinel/sparc-iac/tree/main/docs/FedRAMP_20x)
- [SAF CLI](https://saf-cli.mitre.org/)
