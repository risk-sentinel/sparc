<!-- markdownlint-disable MD013 -->

# SPARC Compliance Documentation

This directory contains NIST SP 800-53 Rev 5 compliance documentation for the
SPARC application, targeting the **HIGH baseline** (370 controls, 20 families).

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
   - `cdefs/` — OSCAL component definitions (5 files, 46 controls)
   - `sbom/` — CycloneDX SBOM for supply chain evidence
   - `oscal-metadata.json` — System ID and party metadata
   - `manifest.json` — File inventory with run ID and git SHA for traceability

3. **`repository_dispatch` notification** — After publishing the artifact, SPARC sends a
   `sparc-compliance-updated` event to `Rebel-Raiders/sparc-iac` with the `run_id` in
   the payload. sparc-iac can then download the artifact via the GitHub REST API:
   ```bash
   # List artifacts for the run
   gh api repos/Rebel-Raiders/sparc/actions/runs/{run_id}/artifacts
   # Download the compliance bundle
   gh api repos/Rebel-Raiders/sparc/actions/artifacts/{artifact_id}/zip > compliance.zip
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

CDEFs in `oscal/cdefs/` follow OSCAL v1.1.2 component-definition format. When
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

---

## Baseline Selection Rationale

**NIST SP 800-53 Rev 5 HIGH** (370 controls) was selected because:

- sparc-iac committed to HIGH baseline for FedRAMP readiness
- HIGH is a superset of Moderate (325) and Low (135)
- Targeting HIGH once eliminates rework for lower-baseline customers
- Aligns with DoD Impact Level requirements

The resolved profile catalog is maintained at:
`https://raw.githubusercontent.com/usnistgov/oscal-content/main/nist.gov/SP800-53/rev5/json/NIST_SP-800-53_rev5_HIGH-baseline-resolved-profile_catalog.json`

---

## References

- [NIST SP 800-53 Rev 5](https://csrc.nist.gov/publications/detail/sp/800-53/rev-5/final)
- [OSCAL Component Definition Model](https://pages.nist.gov/OSCAL/concepts/layer/implementation/component-definition/)
- [sparc-iac FedRAMP 20x Docs](https://github.com/Rebel-Raiders/sparc-iac/tree/main/docs/FedRAMP_20x)
- [SAF CLI](https://saf-cli.mitre.org/)
