# Security Scanning Pipeline

SPARC uses a unified GitHub Actions workflow (`.github/workflows/security.yml`) that consolidates all security scanning into a single pipeline with MITRE SAF CLI normalization.

## Workflow Triggers

| Trigger | When |
|---------|------|
| `pull_request` | Every PR |
| `push` to `main` | Every merge to main |
| `schedule` | Weekly — Mondays at 06:00 UTC |
| `workflow_dispatch` | Manual trigger with configurable inputs |

## Configurable Inputs (workflow_dispatch)

| Input | Default | Description |
|-------|---------|-------------|
| `run_semgrep` | `false` | Also run Semgrep SAST scan (Brakeman + CodeQL always run) |
| `rails_app_path` | `.` | Path to Rails application root |
| `dockerfile_path` | `./Dockerfile` | Dockerfile for container scanning |
| `org_metadata_file` | `.github/oscal-metadata.json` | OSCAL metadata for HDF enrichment |
| `fail_on_severity` | `none` | Severity threshold to fail the workflow |
| `upload_to_code_scanning` | `true` | Upload SARIF to GitHub Code Scanning tab |

## Pipeline Architecture

### Parallel Scan Jobs (1-9)

All scan jobs run concurrently:

| Job | Tool | Always On | Output Formats | Purpose |
|-----|------|-----------|---------------|---------|
| `secrets_scan` | Gitleaks | Yes | SARIF | Detect exposed secrets in git history |
| `brakeman_scan` | Brakeman | Yes | SARIF | Rails-specific static application security testing |
| `codeql_scan` | CodeQL | Yes | SARIF | Deep semantic code analysis (Ruby + JS/TS) |
| `semgrep_scan` | Semgrep | No (opt-in) | SARIF | Pattern-based static analysis with custom rules |
| `dependency_audit` | bundler-audit | Yes | JSON | Ruby dependency vulnerability check |
| `importmap_audit` | importmap audit | Yes | stdout | JavaScript dependency check |
| `trivy_fs_scan` | Trivy | Yes | SARIF + CycloneDX | Filesystem vulnerability/misconfig/secret scan |
| `trivy_container_scan` | Trivy | Yes | SARIF + ASFF + CycloneDX | Container image vulnerability scan |
| `sbom_generation` | cyclonedx-ruby | Yes | CycloneDX | Software Bill of Materials |

### Sequential Jobs (10-11)

| Job | Purpose |
|-----|---------|
| `normalize_hdf` | Convert all scan outputs to HDF via SAF CLI, inject OSCAL metadata |
| `bundle_results` | Create ZIP archive, generate summary, evaluate severity threshold |

## SAST Scanner Strategy

SPARC runs **two always-on SAST scanners** for maximum depth and breadth:

### Brakeman (always-on)
Rails-specific static analysis. Fast, purpose-built for Rails security patterns. Detects SQL injection, XSS, mass assignment, and Rails-specific vulnerabilities. Runs on every PR and push.

### CodeQL (always-on)
GitHub's semantic code analysis engine. Multi-language support (Ruby + JavaScript/TypeScript). Performs deep data-flow and control-flow analysis to find complex vulnerabilities like taint propagation, authentication bypasses, and injection flaws. Produces SARIF per language, merged into a single artifact.

### Semgrep (optional, via workflow_dispatch)
Pattern-based static analysis with Ruby/Rails rulesets. Good for custom rules and organization-specific patterns. Enable via the `run_semgrep` input when triggered manually. Uses `returntocorp/semgrep-action`.

All three produce SARIF output for consistent downstream HDF conversion.

> **Note:** If GitHub's default CodeQL setup is enabled on your repository, it should be disabled to avoid duplicate scanning. The `codeql_scan` job in this workflow replaces it with broader language coverage and HDF integration.

## SAF CLI HDF Conversions

The `normalize_hdf` job uses [MITRE SAF CLI](https://saf-cli.mitre.org/) via the `mitre/saf_action@v1` GitHub Action:

| Source | Format | SAF CLI Command | HDF Output |
|--------|--------|-----------------|------------|
| Gitleaks | SARIF | `convert sarif2hdf` | `gitleaks.hdf.json` |
| Brakeman | SARIF | `convert sarif2hdf` | `brakeman.hdf.json` |
| CodeQL | SARIF | `convert sarif2hdf` | `codeql.hdf.json` |
| Semgrep | SARIF | `convert sarif2hdf` | `semgrep.hdf.json` |
| Trivy FS | SARIF | `convert sarif2hdf` | `trivy-fs.hdf.json` |
| Trivy Container | ASFF | `convert trivy2hdf` | `trivy-container.hdf.json` |
| Trivy FS SBOM | CycloneDX | `convert cyclonedx_sbom2hdf` | `trivy-fs-sbom.hdf.json` |
| Trivy Container SBOM | CycloneDX | `convert cyclonedx_sbom2hdf` | `trivy-container-sbom.hdf.json` |
| Ruby SBOM | CycloneDX | `convert cyclonedx_sbom2hdf` | `sbom-ruby.hdf.json` |

The `-w` flag is used with `sarif2hdf` to include the raw SARIF in the HDF passthrough block.

## OSCAL Metadata Enrichment

After HDF conversion, each file is enriched with OSCAL-aligned metadata using `saf supplement passthrough write`. The metadata source is `.github/oscal-metadata.json`, which contains:

- Organization party information (OSCAL v1.1.2 format)
- Scanner and preparer role definitions
- Responsible party assignments

## Artifacts

| Artifact Name | Contents | Retention |
|--------------|----------|-----------|
| `gitleaks-sarif` | Gitleaks SARIF results | 90 days |
| `brakeman-sarif` | Brakeman SARIF results | 90 days |
| `codeql-sarif` | CodeQL SARIF results (merged multi-language) | 90 days |
| `semgrep-sarif` | Semgrep SARIF results (when enabled) | 90 days |
| `bundler-audit-json` | bundler-audit JSON results | 90 days |
| `trivy-fs-results` | Trivy FS SARIF + CycloneDX | 90 days |
| `trivy-container-results` | Trivy container SARIF + ASFF + CycloneDX | 90 days |
| `sbom-cyclonedx` | Ruby CycloneDX SBOM | 90 days |
| `hdf-results` | All HDF files with OSCAL metadata | 90 days |
| `security-scan-archive` | Combined ZIP of all results | 90 days |

### ZIP Archive Structure

```
security-scan-results.zip
  hdf/              # HDF files (Heimdall-compatible)
  sarif/            # Raw SARIF files (Gitleaks, Brakeman, CodeQL, Semgrep, Trivy)
  sbom/             # CycloneDX SBOMs
  asff/             # Trivy ASFF output
  bundler-audit-results.json
```

## Severity Threshold

Set `fail_on_severity` to gate the workflow:

| Value | Behavior |
|-------|----------|
| `none` (default) | Never fail — informational only |
| `critical` | Fail only on critical findings |
| `high` | Fail on high or critical |
| `medium` | Fail on medium, high, or critical |
| `low` | Fail on any finding |

## Error Handling

- All scan steps use `continue-on-error: true` — one scanner failure does not block others
- Missing artifacts produce `::warning::` annotations, not failures
- The severity threshold in `bundle_results` is the only hard failure point

## Heimdall Lite Compatibility

All HDF files are compatible with [MITRE Heimdall Lite](https://heimdall-lite.mitre.org/) for interactive visualization. Upload any `.hdf.json` file from the `hdf-results` artifact or the ZIP archive.
