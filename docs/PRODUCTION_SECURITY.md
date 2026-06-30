# SPARC Production Security Hardening Guide

Operator-facing hardening reference for SPARC v1.7.0+. Synthesizes every security-relevant env var, config setting, and deployment-layer requirement from `docs/ENVIRONMENT_VARIABLES.md`, `docs/dev/issue_rules.md`, `docs/compliance/`, sparc-iac, and container-build-sign into one readable guide.

**Use this doc when:**
- Standing up a new SPARC deployment
- Auditing an existing one for pen-test readiness
- Onboarding a new operator
- Answering "is feature X hardened?" questions

**Cross-references:**
- [`docs/ENVIRONMENT_VARIABLES.md`](ENVIRONMENT_VARIABLES.md) — full env-var catalog (this doc points; doesn't duplicate)
- [`docs/security/SCANNER_FINDINGS_AUDIT.md`](security/SCANNER_FINDINGS_AUDIT.md) — every scanner suppression with rationale (#525)
- [`docs/dev/issue_rules.md`](dev/issue_rules.md) — auth mode coverage matrix
- [`docs/compliance/nist-sp800-53-rev5-mapping.md`](compliance/nist-sp800-53-rev5-mapping.md) — NIST 800-53 control mapping
- `risk-sentinel/sparc-iac` — deployment infrastructure (DNS, ALB, ECS, RDS, security groups, GuardDuty)
- `risk-sentinel/container-build-sign` — base image, build pipeline, image signing

---

## 1. TL;DR — minimum-viable hardened SPARC

Copy-paste env-var block for a v1.7.0 production deployment with maximum hardening:

```bash
# ── Application URL (drives userdata subdomain + mailer links) ─────────────
SPARC_APP_URL=https://sparc.example.org

# ── Authentication: OIDC only, MFA enforced ────────────────────────────────
SPARC_ENABLE_OIDC=true
SPARC_OIDC_FORCE_MFA=true
SPARC_ENABLE_LOCAL_LOGIN=false
SPARC_API_AUTH=hybrid                 # OIDC JWT for humans + service tokens for automation
SPARC_OIDC_ISSUER_URL=https://your-idp.example.com/realms/main
SPARC_OIDC_CLIENT_ID=sparc-prod
SPARC_OIDC_CLIENT_SECRET=...          # from AWS Secrets Manager

# ── Upload validation (size + zip-bomb + executable deny) ──────────────────
SPARC_MAX_UPLOAD_MB=50                # also caps zip-based-format uncompressed total
SPARC_MAX_AVATAR_MB=2

# ── Rate limiting (Rack::Attack thresholds; tune to your traffic) ──────────
SPARC_RATE_LIMITING_ENABLED=true
SPARC_RATE_LIMIT_UPLOADS_PER_5MIN_PER_IP=30
SPARC_RATE_LIMIT_UPLOADS_PER_HOUR_PER_USER=100
SPARC_RATE_LIMIT_API_WRITES_PER_MINUTE=300
SPARC_RATE_LIMIT_LOGIN_FAILURES_PER_MIN=5
SPARC_RATE_LIMIT_SAFELIST_CIDRS=127.0.0.1,::1,10.0.0.0/8   # internal health checks + bastion

# ── Transport: TLS enforced ────────────────────────────────────────────────
FORCE_SSL=true

# ── Session timeout (NIST AC-11) ───────────────────────────────────────────
SPARC_SESSION_TIMEOUT_MINUTES=15

# ── Consent banner ─────────────────────────────────────────────────────────
SPARC_BANNER_ENABLED=true
SPARC_BANNER_MESSAGE=docs/banners/sample-consent-banner.html

# ── Master secret derivation (#372) ────────────────────────────────────────
SPARC_HASH=<32+ chars from AWS Secrets Manager>
```

**Post-upgrade verification checklist** — see [§16](#16-v170-hardening-checklist).

---

## 2. Threat model & SPARC's design assumption

SPARC is **designed for internal-network deployment**, not public-facing SaaS. The threat surface for "malicious uploaded file" is materially smaller than a public app because every uploader is an authenticated, vetted operator reachable only via controlled network.

| Defense layer | What stops the attack |
|---|---|
| Network perimeter | CIDR allowlist + VPN — only vetted operators reach the upload endpoint at all |
| Authentication | OIDC + MFA when `SPARC_OIDC_FORCE_MFA=true` (no anonymous uploads) |
| Ingest validation | Extension allowlist + magic-byte + executable-signature + syntactic parse (#509) + size + zip-bomb (#510) + XXE-safe XML (#511) |
| Runtime detection | GuardDuty Runtime Monitoring on the ECS task (sparc-iac default) — detect-and-destroy on container escape |
| Execution prevention | `disposition: "attachment"` everywhere, CSP enforce (#514), cookieless blob host (#515) |
| Rate limiting | Rack::Attack throttles (#513) for upload / login / API write floods |

**SPARC does NOT ship an in-app content-scanning adapter** (issue #512 closed as not-planned). Reason: consumer-side ownership of scanner choice. Operators run different stacks (GuardDuty, Defender, Prisma, ClamAV) — see [§6](#6-malware-scanning-integration-patterns) for integration patterns.

**NIST 800-53 SI-3 (Malicious Code Protection)** coverage: satisfied at the container-runtime + network-perimeter layers, not the app layer. Mapped in [`docs/compliance/nist-sp800-53-rev5-mapping.md`](compliance/nist-sp800-53-rev5-mapping.md).

---

## 3. Authentication & MFA

| Env var | Default | Recommended | Why |
|---|---|---|---|
| `SPARC_ENABLE_OIDC` | `false` | `true` | Delegates auth + MFA to your IdP (Okta, Keycloak, Entra ID) — avoids password storage |
| `SPARC_OIDC_FORCE_MFA` | `false` | `true` | Enforces MFA via ACR claim — covers IA-2(1), IA-2(2) |
| `SPARC_ENABLE_LOCAL_LOGIN` | `false` | `false` | Eliminates non-MFA password auth path |
| `SPARC_API_AUTH` | `local` | `hybrid` | OIDC JWT for humans (MFA via IdP) + SPARC tokens for service accounts |
| `SPARC_OIDC_ISSUER_URL` | (none) | required | Your IdP's issuer URL |
| `SPARC_OIDC_CLIENT_ID` | (none) | required | OIDC app registration ID |
| `SPARC_OIDC_CLIENT_SECRET` | (none) | required (from Secrets Manager) | Never commit; pull from AWS Secrets Manager (see [§13](#13-secret-management)) |
| `SPARC_ENABLE_USER_REGISTRATION` | `false` | `false` | Disable self-registration; provision via IdP |
| `SPARC_SESSION_TIMEOUT_MINUTES` | `60` | `15` | NIST AC-11 (device lock) — tighter for high-security tenants |

**Auth mode coverage matrix:** see [`docs/dev/issue_rules.md`](dev/issue_rules.md) for the full Local-vs-OIDC-vs-LDAP-vs-Hybrid breakdown across every NIST IA-* control.

**Avoid:** running `SPARC_ENABLE_LOCAL_LOGIN=true` without `SPARC_OIDC_FORCE_MFA=true` — the password path can bypass MFA enforcement.

---

## 4. Network segmentation (sparc-iac)

SPARC's "internal-network only" posture is enforced at the deployment layer, not the app. Required sparc-iac configuration:

| Control | Configuration | Cross-ref |
|---|---|---|
| **ALB CIDR allowlist** | Restrict listener to known operator CIDR ranges + VPN gateway | sparc-iac |
| **VPN gateway** | All operator access through corporate VPN; no public ingress | sparc-iac |
| **RDS isolation** | Security group denies all public ingress; reachable only from SPARC's task security group | sparc-iac |
| **S3 bucket policy** | Private; accessible only via SPARC's IAM role | sparc-iac |
| **GuardDuty Runtime Monitoring** | Enabled on the ECS task — detect-and-destroy on container escape | sparc-iac (default) |
| **GuardDuty EventBridge** | Routes findings to SQS / SNS for triage | sparc-iac |
| **userdata.* DNS + cert** | Separate hostname for blob downloads (see [§10](#10-session-security)) | sparc-iac #269 |
| **TLS cert** | ACM with SAN covering both main + userdata hostnames | sparc-iac #269 |

Cross-link: sparc-iac issues #268 (malware-scan deployment patterns) and #269 (userdata subdomain).

---

## 5. Upload validation layers

Every file upload goes through six layers before being stored. Each layer is independent — a bypass in one is caught by the next.

| Layer | What it catches | Implementation |
|---|---|---|
| **1. Extension allowlist** | Unsupported extensions (.exe, .sh, etc.) | `DocumentTypeRegistry#allowed_extensions` per document type |
| **2. Executable signature deny-list** | PE / ELF / Mach-O / Java class / WebAssembly / shebang scripts, even renamed | `FileUploadable#reject_if_executable_signature!` (#509) |
| **3. Magic-byte MIME cross-check** | Files with content not matching declared extension (e.g., zip mislabeled as .json) | `Marcel::MimeType.for` + `EXPECTED_MIME_BY_EXT` (#509) |
| **4. Syntactic structural parse** | Truncated / malformed JSON / YAML / XML | `JSON.parse` / `YAML.safe_load` / `XmlSecurity.parse` with 5s timeout (#509) |
| **5. Zip-bomb defense (zip-based formats)** | Files whose uncompressed total exceeds `SPARC_MAX_UPLOAD_MB` | `Zip::File.open(...).entries.sum(&:size)` (#510) |
| **6. XXE-safe XML parsing** | XML external entity attacks, billion-laughs entity expansion | `XmlSecurity.parse` (NONET + no NOENT/DTDLOAD/HUGE) (#511) |

| Env var | Default | Recommended | Why |
|---|---|---|---|
| `SPARC_MAX_UPLOAD_MB` | `50` | `50` (tune to your largest legitimate file) | Caps both raw upload size AND uncompressed zip-archive total — single knob |
| `SPARC_MAX_AVATAR_MB` | `2` | `2` | Avatar caps shouldn't compete with document caps |

**Reverse-proxy alignment:** nginx / ALB `client_max_body_size` should be `SPARC_MAX_UPLOAD_MB + ~10 MB` headroom (e.g., `60m` when `SPARC_MAX_UPLOAD_MB=50`). The proxy rejects oversized requests before they reach Puma.

---

## 6. Malware scanning integration patterns

SPARC does NOT ship an in-app content scanner (per the [§2 threat model](#2-threat-model--sparcs-design-assumption)). Operators wire up their own per their environment. Reference patterns:

### 6.1 AWS + GuardDuty Runtime Monitoring (sparc-iac default)

**What it covers:** detect-and-destroy on container escape; suspicious behavior in the running container.

**SPARC-side wiring:** none. Comes for free with the sparc-iac stack.

**Tradeoff:** runtime-only — doesn't scan blobs at ingest. The combined defense-in-depth from [§5](#5-upload-validation-layers) handles the ingest side; GuardDuty handles the post-storage behavioral side.

### 6.2 AWS + GuardDuty Malware Protection for S3 (opt-in upgrade)

**What it covers:** every blob scanned on PUT; tagged `GuardDutyMalwareScanStatus`.

**SPARC-side wiring:** none today; optional future hook tracked in #531 (post-v1.7.0) — single env var (`SPARC_GUARDDUTY_S3_BUCKET`), checks the tag before serving, 403 on `THREATS_FOUND`.

**Enable:** in your AWS account, turn on GuardDuty Malware Protection for the S3 bucket holding SPARC's ActiveStorage blobs. SPARC's task IAM role needs `s3:GetObjectTagging`.

### 6.3 Azure + Microsoft Defender for Cloud

**What it covers:** agentless runtime monitoring on container instances; equivalent to GuardDuty Runtime Monitoring.

**SPARC-side wiring:** none. Same model as GuardDuty Runtime — Defender catches escapes at the host layer.

### 6.4 Multi-cloud / on-prem + Prisma Cloud Defender

**What it covers:** agent-based runtime + ingest scanning. Defender agent runs on the ECS host or as a sidecar.

**SPARC-side wiring:** none. Defender enforces at the OS/network layer.

### 6.5 On-prem + ClamAV sidecar (air-gapped fallback)

**What it covers:** scan-on-ingest for tenants without managed cloud scanners.

**SPARC-side wiring:** none today. Tenants who need app-layer rejection at ingest can either:
- Run a ClamAV sidecar in their ECS task / docker-compose (sparc-iac patterns; container-build-sign #13 tracks an optional `+clamav` image variant)
- Add their own thin adapter following the #531 hook pattern

---

## 7. Transport security

| Env var | Default | Recommended | Why |
|---|---|---|---|
| `FORCE_SSL` | `true` | `true` | Forces HTTPS via `ActionDispatch::SSL`; marks all cookies secure |

**HSTS** is enabled by default in `config/environments/production.rb` with `max-age=1.year, includeSubDomains, preload`. The HSTS preload list submission is a sparc-iac concern (out of scope for this doc).

**Reverse-proxy body limit** — see [§5](#5-upload-validation-layers). Required for the upload-size cap to work end-to-end.

---

## 8. CSP & security headers

| Setting | State as of v1.7.0 | Source |
|---|---|---|
| Content-Security-Policy | **Enforcing** (#514). Per-request nonce on `script-src`. | `config/initializers/content_security_policy.rb` |
| X-Content-Type-Options | `nosniff` | `config/initializers/security_headers.rb` |
| X-Frame-Options | `SAMEORIGIN` | same |
| Referrer-Policy | `strict-origin-when-cross-origin` | same |
| Permissions-Policy | `camera=(), microphone=(), geolocation=()` | same |
| HSTS | `max-age=1.year; includeSubDomains; preload` | `config/environments/production.rb` |

**Inline scripts** in views carry `nonce="<%= content_security_policy_nonce %>"`. The CSP nonce generator emits a fresh `SecureRandom.base64(16)` per request (#514).

**Known gaps tracked in #528** (post-v1.7.0): `'unsafe-inline'` on `style-src` (Bootstrap inline-style refactor), remaining inline scripts → Stimulus refactor, `report-uri`/`report-to` collector, Trusted Types.

---

## 9. Rate limiting

| Env var | Default | Recommended | Why |
|---|---|---|---|
| `SPARC_RATE_LIMITING_ENABLED` | `true` | `true` (kill switch for emergencies) | Master toggle |
| `SPARC_RATE_LIMIT_UPLOADS_PER_5MIN_PER_IP` | `30` | `30` (tune per traffic) | Bulk-upload abuse from a single source |
| `SPARC_RATE_LIMIT_UPLOADS_PER_HOUR_PER_USER` | `100` | `100` | Compromised account flood |
| `SPARC_RATE_LIMIT_API_WRITES_PER_MINUTE` | `300` | `300` | Runaway API import scripts |
| `SPARC_RATE_LIMIT_LOGIN_FAILURES_PER_MIN` | `5` | `5` | Credential stuffing |
| `SPARC_RATE_LIMIT_SAFELIST_CIDRS` | `127.0.0.1,::1` | `127.0.0.1,::1,<internal-CIDRs>` | Internal health checks, NLB targets, bastion |

Throttle hits return HTTP `429` with `Retry-After` and `X-RateLimit-Bucket` headers. Hits log `[rack-attack] THROTTLED` to Rails.logger (ingested by CloudWatch in prod). See [`docs/ENVIRONMENT_VARIABLES.md`](ENVIRONMENT_VARIABLES.md#rate-limiting-513) for the full bucket-discriminator table and response shape.

---

## 10. Session security

### Host-only session cookie (DO NOT add `Domain=`)

SPARC relies on Rails' **host-only cookie default** (no `Domain=` attribute on `Set-Cookie`). Per RFC 6265 §5.1.3, this scopes the session cookie to exactly the app hostname — it is NOT sent to subdomains like `userdata.*`. Setting `domain:` explicitly in `config/initializers/session_store.rb` would broaden the cookie scope and defeat the [§10.2 cookieless blob host](#102-cookieless-blob-host) protection.

The initializer file (`config/initializers/session_store.rb`) exists as comment-only documentation of this constraint.

### Cookieless blob host (#515)

User-uploaded blobs (SSP/SAR/CDEF/POAM/Evidence) are served from a separate `userdata.<app-host>` hostname. Even if a future code change accidentally sets `disposition: "inline"` on a user-uploaded HTML/SVG, the browser script lives on the `userdata.*` origin and cannot read the session cookie.

| Env var | Default | Recommended | Why |
|---|---|---|---|
| `SPARC_APP_URL` | `http://localhost:3000` | `https://sparc.example.org` | Canonical app URL — drives userdata derivation + mailer links |
| `SPARC_USERDATA_HOST` | (derived as `userdata.<app-host>`) | (leave unset) | Override only for per-tenant subdomain patterns or split DNS |

**sparc-iac coordination required:** DNS + ALB rule + TLS cert for `userdata.*` (sparc-iac #269).

### Session timeout

| Env var | Default | Recommended |
|---|---|---|
| `SPARC_SESSION_TIMEOUT_MINUTES` | `60` | `15` (high-security) / `60` (default) |

NIST AC-11 (Device Lock) — tighter timeout for high-security tenants.

---

## 11. Audit & compliance

- **`audit_events` table** retains every state-changing action (NIST AU-2). Retention policy: indefinite by default; archival/purge is a sparc-iac concern.
- **`BackMatterResourceChange`** logs OSCAL back-matter mutations for federation traceability (NIST AU-10 non-repudiation; from #372).
- **NIST 800-53 mapping:** [`docs/compliance/nist-sp800-53-rev5-mapping.md`](compliance/nist-sp800-53-rev5-mapping.md) — central mapping document.
- **OSCAL CDEFs:** [`docs/compliance/oscal/cdefs/*.json`](compliance/) — per-area component definitions.
- **Conditional coverage** (auth mode deltas): see [`docs/dev/issue_rules.md`](dev/issue_rules.md#authentication-mode-deltas) for the IA-2/IA-2(1)/IA-2(2)/IA-5(1)/IA-8/IA-12 coverage matrix.

---

## 12. Secret management

| Secret | Source | Why |
|---|---|---|
| `SECRET_KEY_BASE` | AWS Secrets Manager (production) | Rails session signing key |
| `SPARC_HASH` | AWS Secrets Manager | Master secret for `SparcKeyDerivation` (#372) — derives per-feature keys for federation, HMAC signing, etc. Must be ≥32 chars. |
| `SPARC_OIDC_CLIENT_SECRET` | AWS Secrets Manager | OIDC app secret |
| `SPARC_DB_PASSWORD` | AWS IAM database auth OR Secrets Manager | RDS password |
| `SPARC_AWS_LABS_GITHUB_TOKEN` | AWS Secrets Manager (optional) | GitHub PAT for AWS Labs CDEF refresh (#466) — raises rate limit |
| `SPARC_SMTP_PASSWORD` | AWS Secrets Manager | SMTP relay password |

**AWS Secrets Manager integration:** see [`docs/ENVIRONMENT_VARIABLES.md`](ENVIRONMENT_VARIABLES.md#aws-secrets-manager-ecsec2-deployments) for the JSON injection format.

**AWS IAM database auth:** preferred over static `SPARC_DB_PASSWORD` for production RDS. See [`docs/ENVIRONMENT_VARIABLES.md`](ENVIRONMENT_VARIABLES.md#aws-iam-database-authentication).

**Rotation:** `SPARC_HASH` rotation requires running `bin/rails sparc:rotate_hash` with `OLD_SPARC_HASH` set — see federation docs and the rotation rake task. Rotation is supported but disruptive; coordinate with active sessions.

---

## 13. Image & dependency hygiene

| Layer | Owner | Reference |
|---|---|---|
| Base image (ruby:3.4.4-slim) CVEs | container-build-sign | container-build-sign #13 — audit + clearance |
| Image-signing (cosign / sigstore) | container-build-sign | SPARC CI consumes signed images via Trivy verification |
| App-level scanner suppressions | SPARC repo | [`docs/security/SCANNER_FINDINGS_AUDIT.md`](security/SCANNER_FINDINGS_AUDIT.md) — full inventory (#525) |
| Trivy CVE suppressions | SPARC repo | `.trivyignore` — 9 documented entries, all classified |
| Gem dependencies | SPARC repo | `Gemfile.lock` — Bundler-audit reports "No vulnerabilities found" as of v1.7.0 baseline |

**Patching cadence:** base image bumped via Dependabot or manual `docker pull && retag` — coordinate with container-build-sign team. Major version bumps require regression coverage; security patches apply within 30 days for HIGH/CRITICAL.

---

## 14. Recovery & DR

| Capability | Configuration |
|---|---|
| **RDS PITR** (point-in-time recovery) | sparc-iac — 7-day backup window default; tune per RTO/RPO target |
| **Blob backups** | S3 versioning + lifecycle policy — sparc-iac |
| **Soft-delete** | SPARC documents support soft-delete via `acts_as_paranoid`-style `deleted_at` column on most document tables. `bin/rails sparc:restore_document <type> <id>` to restore. |
| **Audit log retention** | `audit_events` table — never auto-purged; sparc-iac handles archival to cold storage |

---

## 15. sparc-validate posture

`risk-sentinel/sparc-validate` is the validation pipeline that runs OSCAL schema validation, KSI checks, and compliance-artifact validation against SPARC documents.

**Operator-facing recommendations:**
- Enable validation against every SSP / SAR / SAP / POAM / CDEF on import — built into SPARC; no env var to flip
- Review `sparc-validate` findings as part of the document lifecycle (started → in_progress → published)
- For pen-test prep: run `sparc-validate` against every published document; findings are documented in `audit_events` for traceability

See the `risk-sentinel/sparc-validate` repo for the full validation rule set and configuration. (sparc-validate-specific env vars are documented in its own README, not duplicated here.)

---

## 16. v1.7.0 hardening checklist

Post-upgrade verification. Run through this list after deploying v1.7.0 to confirm every hardening layer is active.

### Authentication
- [ ] `SPARC_ENABLE_OIDC=true` and `SPARC_OIDC_FORCE_MFA=true` set; local login disabled
- [ ] Test login: OIDC redirects to IdP, MFA challenge appears
- [ ] Test API: `Authorization: Bearer <invalid>` returns 401 with no info leak

### Network
- [ ] ALB CIDR allowlist restricts ingress to operator CIDRs + VPN
- [ ] RDS security group denies public ingress (sparc-iac verified)
- [ ] GuardDuty Runtime Monitoring enabled on the ECS task; findings route to EventBridge

### Upload validation
- [ ] Upload a `.exe` renamed to `.json` → rejected (executable signature deny)
- [ ] Upload a malformed JSON → rejected (syntactic check)
- [ ] Upload a synthetic 1 GB zip-bomb archive → rejected (size cap)
- [ ] `SPARC_MAX_UPLOAD_MB` matches nginx `client_max_body_size + headroom`

### CSP & headers
- [ ] `curl -sI https://sparc.example.org/` returns `Content-Security-Policy:` (NOT `-Report-Only`)
- [ ] Inline `<script>` tags have `nonce="..."` matching the CSP header
- [ ] X-Content-Type-Options, X-Frame-Options, Referrer-Policy, HSTS all present

### Rate limiting
- [ ] Brute-force login attempts return `429` after 5 failures (defaults)
- [ ] Bulk upload attempts return `429` after 30 / 5 min (defaults)
- [ ] Throttle hits visible in CloudWatch as `[rack-attack] THROTTLED` log lines

### Session & blob serving
- [ ] `Set-Cookie` from `/login` POST does NOT include `Domain=` attribute (regression-tested in `spec/initializers/session_store_spec.rb`)
- [ ] Blob download URLs use `https://userdata.<app-host>/rails/active_storage/blobs/...`
- [ ] Cross-origin fetch from `https://evil.example.com` to a blob URL does NOT include the SPARC session cookie

### Scanner findings
- [ ] [`docs/security/SCANNER_FINDINGS_AUDIT.md`](security/SCANNER_FINDINGS_AUDIT.md) review dates are within 90 days
- [ ] `.trivyignore` entries each have a `# Reviewed: YYYY-MM-DD` within the last release window

### Secrets
- [ ] No secrets in env (everything pulled from AWS Secrets Manager or IAM auth)
- [ ] `SPARC_HASH` is ≥32 chars and stored encrypted

### Documentation
- [ ] Operators have access to this doc + `docs/ENVIRONMENT_VARIABLES.md`
- [ ] Pen-test team has the scanner audit doc + the threat-model section ([§2](#2-threat-model--sparcs-design-assumption))

---

## Change log

| Version | Date | Changes |
|---|---|---|
| v1.7.0 | 2026-06-01 | Initial. Synthesizes #509 / #510 / #511 / #513 / #514 / #515 / #525 + cross-repo coordination. |
