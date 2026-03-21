# SPARC Sample OSCAL Artifacts

> **DEMO/SAMPLE DATA ONLY** — All content in this directory is fictional and intended
> for testing, demonstration, and development purposes only. No real organizations,
> systems, or personnel are represented.

## Overview

This directory contains pre-generated OSCAL artifacts demonstrating two compliance
workflows supported by SPARC:

| Workflow | Directory | Description |
|----------|-----------|-------------|
| **Traditional NIST 800-53** | `nist-traditional-demo/` | Narrative-focused compliance per NIST SP 800-53 Rev 5 |
| **FedRAMP 20x** | `fedramp-20x-demo/` | Outcome-focused KSI validation with machine-readable evidence |

## Artifact Comparison

| Artifact | Traditional (800-53) | FedRAMP 20x | Key Difference |
|----------|---------------------|-------------|----------------|
| **System Security Plan** | `ssp-acme-cloud.json` | — | Narrative control implementations |
| **Assessment Plan** | `sap-acme-cloud.json` | — | Examine/interview/test methods |
| **Assessment Results** | `sar-acme-cloud.json` | — | Point-in-time findings |
| **Plan of Action** | `poam-acme-cloud.json` | — | Milestone-based remediation |
| **Component Definition** | `cdef-web-server.json` | — | Implementation narratives |
| **KSI Compliance Report** | — | `ksi-compliance-report.json` | Continuous validation status |
| **Machine Evidence** | — | `ksi-validation-evidence.json` | Automated scan/config data |

## Loading Sample Data

### Full Demo (Traditional + 20x)

```bash
bin/rails db:seed
# or explicitly:
SPARC_SEED_MODE=full bin/rails db:seed
```

### Traditional Only

```bash
SPARC_SEED_MODE=traditional bin/rails db:seed
```

### FedRAMP 20x Only

```bash
SPARC_SEED_MODE=20x bin/rails db:seed
```

## Regenerating Sample Files

Sample OSCAL files are generated from seeded database records using SPARC's
export services. To regenerate after schema or data changes:

```bash
# Generate all sample files
bin/rails samples:generate

# Or selectively:
bin/rails samples:generate_traditional
bin/rails samples:generate_20x
```

## Traditional vs. 20x: Key Differences

### Traditional NIST 800-53

- **Control-by-control** narrative descriptions
- **Point-in-time** assessments (annual)
- **Manual evidence** collection (screenshots, policy docs)
- **Milestone-based** remediation tracking (POA&M)
- **370 controls** at Moderate baseline

### FedRAMP 20x

- **Outcome-focused** Key Security Indicators (56 KSIs)
- **Continuous** validation (weekly for machine, quarterly for non-machine)
- **Machine-readable** evidence (JSON scan results, config exports)
- **Automated** compliance percentage tracking
- **11 security themes** instead of 20 control families

## File Format

All files are valid **OSCAL v1.1.2 JSON** unless otherwise noted. Traditional
artifacts conform to NIST OSCAL schemas. FedRAMP 20x artifacts use SPARC's
KSI export format.
