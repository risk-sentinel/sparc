# GitHub Actions Secrets & Variables Inventory

Reference table for the org-level housekeeping refactor. Captures every
`secrets.X` / `vars.X` reference currently used by `risk-sentinel/sparc`
workflows, where each one is consumed, and a recommended target scope
(org / enterprise / repo / environment) for the refactor.

**Last inventory:** 2026-05-25
**Source command:** `grep -rnE '(secrets|vars)\.[A-Z_]+' .github/`
**Variables:** 0 (all rotated to secrets via #543 / PR #544)
**Secrets:** 8 distinct names across 2 workflows

---

## Summary table

| Name | Type | Files using it | Refs | Today's scope | Recommended target |
|---|---|---|---|---|---|
| `AWS_ACCOUNT_ID` | secret | security.yml | 1 | repo | **Org** |
| `AWS_REGION` | secret | build-sign-publish.yml, security.yml | 7 (with `\|\| 'us-east-1'` fallback) | repo | **Org** (or keep repo if regions diverge per app) |
| `AWS_ROLE_ARN` | secret | build-sign-publish.yml, security.yml | 3 | repo | **Org** (one role per env-scoped permissions, see notes) |
| `COMPLIANCE_S3_BUCKET` | secret | security.yml | 1 | repo | **Org** (single bucket policy) OR **environment** (per env) |
| `DOCKERHUB_TOKEN` | secret | build-sign-publish.yml | 2 | repo | **Org** |
| `DOCKERHUB_USERNAME` | secret | build-sign-publish.yml | 2 | repo | **Org** |
| `ECR_REGISTRY` | secret | build-sign-publish.yml | 8 (with `if: env.HAS_ECR == 'true'` gate) | repo | **Org** |
| `SPARC_IAC_DISPATCH_TOKEN` | secret | security.yml | 2 (`HAS_DISPATCH_TOKEN` gate + repository_dispatch call) | repo | **Repo** (peer-to-peer; or **org** if every repo dispatches to sparc-iac) |

**Net recommendation:** promote 7 of the 8 to **org level**. `SPARC_IAC_DISPATCH_TOKEN` is a judgment call — see notes.

---

## Per-secret detail

### `AWS_ACCOUNT_ID`

- **Purpose:** AWS account ID embedded in Trivy ASFF (AWS Security Finding Format) output for compliance reporting.
- **Used in:**
  - `security.yml:492` — `AWS_ACCOUNT_ID: ${{ secrets.AWS_ACCOUNT_ID }}` on the Trivy container scan step
- **Sensitivity:** medium. Not a credential, but reveals account identity and is a recon target.
- **Org-level rationale:** all risk-sentinel repos run in the same AWS account; defining once at the org saves repeating the value across repos and prevents drift if the account changes.
- **Migration risk:** **low.** Pure read; no caller-side compatibility concerns.

### `AWS_REGION`

- **Purpose:** AWS region for OIDC role assumption and ASFF output.
- **Used in:**
  - `build-sign-publish.yml:156` — `aws-region` on initial OIDC step (build-and-push job)
  - `build-sign-publish.yml:296` — same on sign-verify-attest job
  - `security.yml:491` — Trivy ASFF env var
  - `security.yml:1408` — OIDC step for compliance S3 upload (HAS_DISPATCH_TOKEN gated)
  - `security.yml:1528` — OIDC step for pipeline-performance chart upload (main-only gated)
  - `security.yml:1536, 1539` — `--region` flag on `aws s3 cp` commands
- **Fallback in code:** every reference is `secrets.AWS_REGION || 'us-east-1'`, so the secret being absent doesn't break CI.
- **Sensitivity:** **low.** Region strings like `us-east-1` are not sensitive.
- **Org-level rationale:** consistency. Every workflow that touches AWS uses the same region; org-level secret eliminates per-repo configuration drift.
- **Migration risk:** **low.**

### `AWS_ROLE_ARN`

- **Purpose:** IAM role assumed via OIDC (`aws-actions/configure-aws-credentials@v6`) for all AWS-touching steps.
- **Used in:**
  - `build-sign-publish.yml:155` — OIDC role-to-assume (build-and-push)
  - `build-sign-publish.yml:295` — OIDC role-to-assume (sign-verify-attest)
  - `security.yml:1407` — OIDC for compliance S3 upload
  - `security.yml:1527` — OIDC for pipeline-performance upload
- **Sensitivity:** medium-high. Reveals the role ARN; combined with the OIDC trust policy this is exploitable if the trust policy is too loose (tracked by `risk-sentinel/sparc-iac#281`).
- **Org-level rationale:** one shared OIDC role for the whole org reduces IAM sprawl. Alternative: keep per-repo roles for least-privilege.
- **Migration risk:** **medium.** If a single org-level role is used, the trust policy must allow every org repo's OIDC subject. Coordinate with `sparc-iac#281`.

### `COMPLIANCE_S3_BUCKET`

- **Purpose:** S3 bucket name for uploading compliance artifacts (HDF, SBOM, OSCAL exports).
- **Used in:**
  - `security.yml:1416` — `BUCKET="${{ secrets.COMPLIANCE_S3_BUCKET }}"` in the S3 upload step (HAS_DISPATCH_TOKEN gated)
- **Sensitivity:** medium. Bucket name is an enumeration target.
- **Org-level rationale:** if every repo uploads to the same bucket, org-level. If buckets differ per environment (dev/staging/prod), use **environment-scoped secrets** instead — let the workflow declare `environment: production` and pick up the right value.
- **Migration risk:** **low** if single-bucket; **medium** if per-env.

### `DOCKERHUB_TOKEN` + `DOCKERHUB_USERNAME`

- **Purpose:** Docker Hub credentials for image push (and login for `docker/login-action`).
- **Used in:**
  - `build-sign-publish.yml:148-149` — login on build-and-push
  - `build-sign-publish.yml:289-290` — login on sign-verify-attest
- **Sensitivity:** **high** (TOKEN). Username is low.
- **Org-level rationale:** every container repo in the org publishes to the same `risksentinel/*` Docker Hub namespace. One org-level token replaces per-repo duplication.
- **Migration risk:** **low.** Same value, just hoisted.

### `ECR_REGISTRY`

- **Purpose:** ECR registry URL (e.g., `<acct>.dkr.ecr.<region>.amazonaws.com`) for image push + sign.
- **Used in:**
  - `build-sign-publish.yml:128, 278` — `HAS_ECR` env var (presence check)
  - `build-sign-publish.yml:168` — fallback in compute-tags step
  - `build-sign-publish.yml:198, 314, 333, 358, 382` — push/sign/verify/attest steps (gated by `HAS_ECR`)
- **Sensitivity:** medium (embeds account ID).
- **Org-level rationale:** every container repo uses the same ECR registry.
- **Migration risk:** **low.**

### `SPARC_IAC_DISPATCH_TOKEN`

- **Purpose:** GitHub fine-grained PAT (or GitHub App token) used to send `repository_dispatch` to `risk-sentinel/sparc-iac`.
- **Used in:**
  - `security.yml:1299` — `HAS_DISPATCH_TOKEN` env var (presence check; every dispatch step is gated on this)
  - `security.yml:1430` — `token:` on `peter-evans/repository-dispatch@v4`
- **Sensitivity:** **high.** Token has cross-repo write capability.
- **Org-level rationale:** depends. If only `sparc` dispatches to `sparc-iac`, repo-level is fine and tighter. If every container/app repo will dispatch (deploys, compliance updates, etc.), org-level avoids creating N near-identical PATs.
- **Migration risk:** **medium.** The token's permission scope (which repos it can dispatch to) is a separate concern from where the secret lives. If promoted to org, ensure the PAT is scoped to only the dispatch-receiver repos to avoid blast radius creep.

---

## Suggested migration order

1. **Phase 1 — easy wins (low-risk, value-additive):**
   - `AWS_REGION`, `DOCKERHUB_TOKEN`, `DOCKERHUB_USERNAME`, `ECR_REGISTRY`, `AWS_ACCOUNT_ID` → org level
2. **Phase 2 — coordinated with IaC:**
   - `AWS_ROLE_ARN` → org level, after `risk-sentinel/sparc-iac#281` tightens the trust policy
3. **Phase 3 — judgment call:**
   - `COMPLIANCE_S3_BUCKET` → org level OR environment-scoped, depending on bucket strategy
   - `SPARC_IAC_DISPATCH_TOKEN` → org level OR keep per-repo
4. **Phase 4 — cleanup:**
   - Delete the per-repo copies once org-level values are confirmed working (org-level secrets take precedence when both exist, so the migration is safe to do in stages)

## Cutover playbook (per secret)

1. Add the secret at org level with the same value as repo level
2. (Org-level takes precedence — no workflow change needed yet)
3. Run a workflow that uses it; confirm green
4. Delete the repo-level copy
5. Run the workflow again; confirm still green (now using org-level only)

## Sister-repo audit reminder

This inventory is **for `risk-sentinel/sparc` only**. The same audit should be run on:

- `risk-sentinel/sparc-iac` — likely uses the same AWS_*, plus its own IaC-specific secrets
- `risk-sentinel/container-build-sign` — base image signing pipeline
- `risk-sentinel/sparc-validate` — validation pipeline

Use the same `grep` command in each repo's `.github/` and consolidate findings before promoting org-level secrets.

## Re-inventory cadence

Re-run this audit:

- Before any major-version release of SPARC
- When a new workflow is added or a workflow is significantly restructured
- When the org gains a new repo that may share secrets
- Quarterly as a hygiene check

Update **Last inventory** date at the top of this file each time.

---

## Cross-references

- #543 / PR #544 — the original vars→secrets rotation
- #545 — pre-public-flip hardening checklist (parallel workstream)
- `risk-sentinel/sparc-iac#281` — OIDC trust policy tightening (gates AWS_ROLE_ARN promotion)
- `docs/PRODUCTION_SECURITY.md` — operator hardening guide
- `docs/security/SCANNER_FINDINGS_AUDIT.md` — scanner suppression inventory
