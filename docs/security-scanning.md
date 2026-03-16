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
| `sast_scanner` | `brakeman` | SAST tool: `brakeman`, `codeql`, or `semgrep` |
| `rails_app_path` | `.` | Path to Rails application root |
| `dockerfile_path` | `./Dockerfile` | Dockerfile for container scanning |
| `org_metadata_file` | `.github/oscal-metadata.json` | OSCAL metadata for HDF enrichment |
| `fail_on_severity` | `none` | Severity threshold to fail the workflow |
| `upload_to_code_scanning` | `true` | Upload SARIF to GitHub Code Scanning tab |

## Pipeline Architecture

### Parallel Scan Jobs (1-7)

All scan jobs run concurrently:

| Job | Tool | Output Formats | Purpose |
|-----|------|---------------|---------|
| `secrets_scan` | Gitleaks | SARIF | Detect exposed secrets in git history |
| `sast_scan` | Brakeman/CodeQL/Semgrep | SARIF | Static application security testing |
| `dependency_audit` | bundler-audit | JSON | Ruby dependency vulnerability check |
| `importmap_audit` | importmap audit | stdout | JavaScript dependency check |
| `trivy_fs_scan` | Trivy | SARIF + CycloneDX | Filesystem vulnerability/misconfig/secret scan |
| `trivy_container_scan` | Trivy | SARIF + ASFF + CycloneDX | Container image vulnerability scan |
| `sbom_generation` | cyclonedx-ruby | CycloneDX | Software Bill of Materials |

### Sequential Jobs (8-9)

| Job | Purpose |
|-----|---------|
| `normalize_hdf` | Convert all scan outputs to HDF via SAF CLI, inject OSCAL metadata |
| `bundle_results` | Create ZIP archive, generate summary, evaluate severity threshold |

## SAF CLI HDF Conversions

The `normalize_hdf` job uses [MITRE SAF CLI](https://saf-cli.mitre.org/) via the `mitre/saf_action@v1` GitHub Action:

| Source | Format | SAF CLI Command | HDF Output |
|--------|--------|-----------------|------------|
| Gitleaks | SARIF | `convert sarif2hdf` | `gitleaks.hdf.json` |
| SAST scanner | SARIF | `convert sarif2hdf` | `sast.hdf.json` |
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

## SAST Scanner Options

### Brakeman (default)
Rails-specific static analysis. Fast, no additional setup. Runs on every PR.

### CodeQL
GitHub's semantic code analysis. Deeper analysis, slower. Best for scheduled runs. Requires `actions: read` permission.

### Semgrep
Pattern-based static analysis with Ruby/Rails rulesets. Good for custom rules. Uses `returntocorp/semgrep-action`.

All three produce SARIF output for consistent downstream processing.

## Artifacts

| Artifact Name | Contents | Retention |
|--------------|----------|-----------|
| `gitleaks-sarif` | Gitleaks SARIF results | 90 days |
| `sast-sarif` | SAST scanner SARIF results | 90 days |
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
  sarif/            # Raw SARIF files
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
