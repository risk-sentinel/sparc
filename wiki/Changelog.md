# Changelog

All notable changes to SPARC are documented here. Versions follow semantic versioning. Links reference the [risk-sentinel/sparc](https://github.com/risk-sentinel/sparc) repository. Full release notes (with verification evidence) live on each version's [GitHub release page](https://github.com/risk-sentinel/sparc/releases).

---

## v1.15.5 -- Catalog Lineage, Boundary Roster Authorization (2026-08-08)

An integrity release. The through-line: **catalogs are the source of truth, and a document that has drifted from its catalog should say so before you publish it, not after.**

- **Catalog lineage, and control membership** ([#911](https://github.com/risk-sentinel/sparc/issues/911)) — a document whose catalog has moved on is reconciled before it can be edited and refused before it can be published, instead of drifting silently from the catalog it claims to follow. A control now answers directly whether it is actually in your baseline, rather than leaving you to infer it. Control identifiers are canonicalised on **every** write path, so the same control cannot enter the system under two spellings. The NIST OSCAL reference set ships inside the image, so lineage and reconciliation work without reaching an external host at runtime.
- **Authorization-boundary rosters require write permission to modify** — a caller without write access on a boundary could change its membership. Roster mutations are now permission-checked, with a request spec asserting that an unauthorized caller is refused.
- **Deferred data migrations actually run, and fail loudly** — they could previously be skipped without surfacing an error, leaving a migration silently unapplied and no one any the wiser.
- **The control source identifier is separate from the NIST reference** ([#912](https://github.com/risk-sentinel/sparc/issues/912)) — a control's originating identifier and its NIST 800-53 reference are distinct fields rather than one overloaded value.
- **A blank control identifier no longer raises an error when deriving a control family** ([#913](https://github.com/risk-sentinel/sparc/issues/913)) — eight call sites guarded this inconsistently; they are now consistent.
- **Evidence upload feedback is unmistakable** ([#902](https://github.com/risk-sentinel/sparc/issues/902), [#903](https://github.com/risk-sentinel/sparc/issues/903)) — and the UI no longer solicits collection provenance it does not use.
- **The admin data-migrations table is reachable by keyboard** — the scrollable region is focusable, satisfying WCAG 2.1 `scrollable-region-focusable`.
- Also: [#915](https://github.com/risk-sentinel/sparc/issues/915) was reviewed and closed with the current behaviour intentionally retained.

**Behaviour changes:** publishing is now **blocked** on a document whose catalog lineage is unreconciled — previously it proceeded. Control identifiers are rewritten to canonical form on every write path, so an identifier stored in a non-canonical spelling will read back canonicalised.

[Full release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.15.5).

## v1.15.4 -- Consistent Collections, Catalog API, Provisioning Credentials (2026-08-04)

A usability and consistency release. The through-line: **the same task looked different on every screen**, and several things the UI offered could not actually be completed. Sixteen list screens now behave identically, and the gaps found while proving that are fixed rather than filed.

- **One way to browse everything** ([#887](https://github.com/risk-sentinel/sparc/issues/887), [#888](https://github.com/risk-sentinel/sparc/issues/888)) — every collection screen opens as cards with a list toggle, remembers the choice per screen, and offers search, removable filter chips and paging in the same places. Search reached five screens that previously could only be scrolled: control mappings, converters, evidence, federation peers and authoritative sources. A component definition is now findable by its regions, control IDs, capabilities and check IDs, so `us-east` or `AC-2` finds what a title search never would — and the API answers that query identically, which it did not before.
- **Six defects found by testing that work, all fixed in the same release.** The card view first shipped with none of the row's actions, so View, Copy, OSCAL export and Delete vanished from the screen users land on. Searching silently discarded any active filter. `download_oscal_validated` — the route every OSCAL export dropdown's JSON option points at — returned **500** on a schema-invalid document in all seven document types, where its three sibling routes degraded to an explanation. Bulk delete was lost on the boundary card view.
- **Catalog families and controls over the API** ([#895](https://github.com/risk-sentinel/sparc/issues/895)) — CRUD for both, with guidance parameters enumerated to their leaves rather than accepted wholesale, and PATCH that merges rather than replaces.
- **Readable, stable URLs for catalogs, families and controls** ([#881](https://github.com/risk-sentinel/sparc/issues/881)) — addresses you can read, share and keep.
- **SPARC-issued provisioning credentials, a break-glass exemption and a last-admin guard** ([#877](https://github.com/risk-sentinel/sparc/issues/877), [#878](https://github.com/risk-sentinel/sparc/issues/878)) — an admin creating a user now hands over a temporary password that SPARC generates and the user must replace at first sign-in, so no one types a colleague's password into a form. The last remaining Instance Admin can no longer be demoted or disabled.
- **An invalid avatar could lock an account out** ([#857](https://github.com/risk-sentinel/sparc/issues/857), [#892](https://github.com/risk-sentinel/sparc/issues/892)) — the stored image was re-validated on every save, so a bad avatar blocked sign-in *and* blocked an admin from deactivating, disabling or re-credentialing the account. Validation now applies to the image being attached.
- **`SPARC_AUTH_BOUNDARY_ROLES` was not actually configurable** ([#875](https://github.com/risk-sentinel/sparc/issues/875), [#890](https://github.com/risk-sentinel/sparc/issues/890)) — a database enum overrode the setting. The roster also gained an API.
- **Evidence uploads enforce their type server-side** ([#868](https://github.com/risk-sentinel/sparc/issues/868)) — the UI had been able to bypass the executable guard.
- **Container advisories are visible again** ([#873](https://github.com/risk-sentinel/sparc/issues/873)) — the image build gates on a Syft SBOM so RHEL advisories surface rather than being silently missed.
- **UBI9 base refreshed 9.7 → 9.8** — the release scan found six HIGH CVEs whose fixes were already sitting in the current base, so they were taken rather than deferred: gnutls (4), libacl and glib2. Total image findings fall from 207 to 155 with nothing new introduced. Every High that remains is either unfixable upstream (curl, postgresql) or a Ruby default-gem shadow the bundle already overrides.
- Also: inline consent-banner content ([#867](https://github.com/risk-sentinel/sparc/issues/867)), guides that open without discarding work plus field-level help ([#870](https://github.com/risk-sentinel/sparc/issues/870)), and personnel management that stays on the roster screen while you build it ([#869](https://github.com/risk-sentinel/sparc/issues/869)).

**Behaviour changes:** `POST /api/v1/users` **no longer accepts `password` / `password_confirmation`** — and does so silently, since unpermitted parameters do not raise. An existing client still receives `201` while the password it chose is ignored; the account is created with a SPARC-issued temporary password instead. Collection screens now default to **cards** rather than a table, and are paged at 24 items. `SPARC_BANNER_ENABLED` is retired in favour of `SPARC_BANNER_HTML`.

[Full release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.15.4).

## v1.15.3 -- Control Identifier Consistency, Fail-Closed Database Password, POA&M Generator (2026-07-28)

An integrity and consistency release. The through-line: **the same control could be identified two different ways depending on which document you exported, and nothing would ever tell you.**

- **One canonical control identifier** ([#852](https://github.com/risk-sentinel/sparc/issues/852)) — SPARC carried a dozen ad-hoc control-id transformers, none of which reconciled zero-padding, so `AC-02` and `ac-2` were different strings for one control. A mapping wrote `ac-2-(1)` while every other document wrote `ac-2.1`, and **no validator would ever flag it** because `id-ref` is a plain string in the mapping schema — so mapping entries silently linked to nothing. A control selection of `ac-2` matched nothing against a stored `AC-02`, producing an **empty SAP reported as success**. Normalisation covers form, not vocabulary: `CCI-000213` is normalised in shape and never translated into a NIST control.
- **A missing database password no longer connects anyway** ([#849](https://github.com/risk-sentinel/sparc/issues/849)) — a `SPARC_DB_*` block without a password connected with none at all, so against a server on `trust` auth the app booted, passed health checks and served traffic on an unauthenticated database. Production now refuses to start unless `SPARC_DB_ALLOW_EMPTY_PASSWORD=true` makes it a decision.
- **PIV sign-in behind an ALB** ([#850](https://github.com/risk-sentinel/sparc/issues/850)) — `CGI.unescape` decodes `+` as a space, and base64 uses `+` as data, so every `+` in a gateway-verified certificate was deleted. The corruption passed every internal check; only OpenSSL rejected it.
- **POA&M generator** ([#843](https://github.com/risk-sentinel/sparc/issues/843)) — the terminal artifact of an ATO was the one document with no in-app generator. A SAR's open risks become POA&M items, and anything that cannot form a valid entry is **skipped with a reason** rather than completed on the author's behalf.
- **Standalone SAP generation** ([#844](https://github.com/risk-sentinel/sparc/issues/844)), **structured object-storage keys** ([#830](https://github.com/risk-sentinel/sparc/issues/830)) so prefix-scoped IAM and per-tenant retention are possible, and a **cross-boundary evidence disclosure** ([#851](https://github.com/risk-sentinel/sparc/issues/851)) closed.

**Behaviour changes:** production refuses to start without a database password; exports emit unpadded control ids (`ac-2`, not `ac-02` — both legal, unpadded is what makes cross-document linkage work); new blobs use structured keys while existing ones keep theirs.

[Full release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.15.3).

## v1.15.2 -- OSCAL Export Conformance, POA&M Integrity, Credential Recovery (2026-07-28)

A correctness and integrity release. The through-line: SPARC could produce documents that were not valid OSCAL, and only find out much later — or never. Each fix moves the failure to the point of entry, and none of them fills a gap by inventing content.

- **Every OSCAL XML export was schema-invalid** ([#827](https://github.com/risk-sentinel/sparc/issues/827)) — the converter emitted children in JSON key order while each OSCAL assembly is an `xs:sequence` with a mandated order, so all seven document types failed their XSD. Ordering was the first of five defects, all the same mistake of treating a *per-type* schema fact as global: attributes (`name` is an attribute of `<prop>` but an element of `<party>`), markup-line vs markup-multiline prose, `xs:simpleContent` text values, and array naming. The ordering table is now generated from the same XSDs the validator uses, with a drift spec so it cannot rot.
- **The ATO package** ([#828](https://github.com/risk-sentinel/sparc/issues/828), [#829](https://github.com/risk-sentinel/sparc/issues/829)) — the manifest was built from the boundary's associations while the archive was built from exports that could fail, so a failed export was skipped silently while the manifest went on naming the missing file. Both now derive from the same results and cannot disagree; omissions are stated with their reason. The package also ships **JSON, YAML and XML** instead of JSON only, each validated against the schema matching its serialization.
- **POA&M integrity** ([#832](https://github.com/risk-sentinel/sparc/issues/832), [#840](https://github.com/risk-sentinel/sparc/issues/840)) — `PoamRisk` validated only `uuid`, and HDF aggregation wrote findings with no OSCAL `target`, so a single aggregation run made the whole POA&M non-exportable. Both are now validated at the point of entry. A `deadline` is required as a SPARC rule: a POA&M with no time commitment is not a plan. Nothing is defaulted or synthesised — pre-existing rows are found with `bin/rails sparc:poam:audit_risks` / `audit_findings`, which deliberately offer no auto-fix.
- **`sar_from_hdf` returned schema-invalid OSCAL unchecked** ([#831](https://github.com/risk-sentinel/sparc/issues/831)) — a consumer got a `200` and a document no OSCAL tool would accept. It now validates first and answers **502** when the upstream converter output does not conform.
- **A forgotten password was unrecoverable** ([#841](https://github.com/risk-sentinel/sparc/issues/841)) — no admin reset, no self-service flow, and the change screen requires the *current* password. Admins can now issue a **temporary password** (works with no outbound mail; the user must replace it at first sign-in) or an **emailed one-time link**. The same release stops the break-glass admin credential drifting out of sync with Secrets Manager.
- **RDS connection from `DB_CREDENTIALS`** ([#834](https://github.com/risk-sentinel/sparc/issues/834)) — `DATABASE_URL` is rendered at deploy time and pins the password, so rotations did nothing until the next redeploy. SPARC now reads the structured secret at boot, so a rotated password takes effect on the next task restart with no IaC change. Database credentials are also redacted from logs by default. See [Configuration](Configuration#database).

**Behaviour changes:** `sar_from_hdf` answers 502 until a fixed hdf-libs is pinned ([mitre/hdf-libs#184](https://github.com/mitre/hdf-libs/issues/184)); POA&M imports reject incomplete risks and findings; incomplete pre-existing POA&M rows are unsaveable until completed; the ATO package contains 3x the files.

[Full release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.15.2).

## v1.15.1 -- PIV/CAC Login Fix (2026-07-27)

Restores smart-card sign-in, which failed on every browser despite a working card, and supersedes the v1.15.0 image (published unsigned when its build stopped before the signing step).

- **PIV/CAC login** ([#824](https://github.com/risk-sentinel/sparc/issues/824)) — the client certificate forwarded by the TLS proxy was rejected as unreadable, so users who selected their certificate and entered their PIN were told "No smart card certificate was presented". The certificate is now reassembled from the forwarded header regardless of how the proxy encodes it (URL-escaped, header-folded, or with the PEM markers stripped), and diagnostics record the certificate's *shape* only — never the certificate itself.
- **Consent banner persistence** — acceptance is remembered for the browser session. Re-firing on every page load was interposing between the certificate-bearing request and `/auth/piv`, which is what made PIV login impossible; session scope keeps the AC-8 notice without breaking authentication.

[Full release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.15.1).

## v1.15.0 -- HDF Aggregation: Re-occurrence Lifecycle + Amendment Approval + Document Aggregation (2026-07-26)

Extends HDF triage from a per-scan worklist into an audit-ready, ATO-integrated flow. Scans are tied to the component they assessed, kept as history with a re-occurrence lifecycle, gated by an approval + ODP-validity flow, and folded into the boundary's assessment documents.

- **Audit-ready scan history + re-occurrence lifecycle** ([#811](https://github.com/risk-sentinel/sparc/issues/811)) — each ingest records its **Target / CDEF** and **Scope** (target-specific vs boundary-wide), and findings are kept per-scan-run as history (`current` flag) rather than overwritten. Every finding carries a lifecycle status — new / carried_forward / **re_failed** (failing again at worse severity) / expired / superseded — computed against the prior current scan. The triage board defaults to the current scan with an *Include history* toggle, a Component column, lifecycle badges, and a re-failed banner.
- **Amendment approval + ODP validity** ([#809](https://github.com/risk-sentinel/sparc/issues/809)) — a disposition is a proposed amendment that only suppresses a finding once **approved** (by an admin or a role granted the new `amendment.approve` permission) *and* within its **validity window**. The window comes from the boundary profile's ODP, else a new admin **Remediation Timelines** SLA table (baseline × NIST criticality → days); an active POA&M for the control means no expiry. Amendments record both decider and approver.
- **Aggregate into SSP / SAP / SAR / POA&M** ([#809](https://github.com/risk-sentinel/sparc/issues/809)) — an **Aggregate** action (sync or async job) maps findings to controls via their HDF `tags.nist`, writes a non-destructive `hdf_scan_result` annotation on SSP/SAP/SAR controls, and opens POA&M items for un-suppressed failures.
- **Signed HDF package export** ([#809](https://github.com/risk-sentinel/sparc/issues/809)) — a single HMAC-SHA256 signed bundle (amendments + findings + dispositions), keyed from `SPARC_HASH`, that a consumer can archive or feed downstream. Full `Api::V1` surface for every new action. See [User Guide: HDF Amendment Triage](User-Guide-HDF-Amendment-Triage).

[Full release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.15.0).

## v1.14.0 -- HDF Amendment Triage (Scanner Finding Disposition) (2026-07-25)

Turn raw scanner output into auditable disposition decisions. SPARC becomes the translation engine + human-in-the-loop UI between a tenant's scanners and their CI security gate.

- **HDF ingest + triage + amendments export** ([#447](https://github.com/risk-sentinel/sparc/issues/447)) — upload scanner findings in Heimdall Data Format (single scan or a `saf convert` bundle), triage each failed control into one of the seven HDF v3.4.0 override kinds (falsePositive / waiver / poam / vendorDependency / inherited / riskAdjustment / operationalRequirement) with an evidence / POA&M / attestation / risk-assessment linkage and provenance hash, then export a deterministic per-boundary **HDF Amendments** document your CI applies with `hdf amend apply` before its `saf validate threshold` gate. Ingest is idempotent by `(boundary, control_id)` so dispositions survive re-scans; the export validates itself via `hdf amend verify`. The #244 severity policy is enforced (no waiver/downgrade on CRITICAL). New models `ScanRun` / `ScannerFinding` / `FindingDisposition` / `RiskAssessment`; full `Api::V1` surface + a boundary-scoped triage UI. See [User Guide: HDF Amendment Triage](User-Guide-HDF-Amendment-Triage).
- **Follow-on** — aggregating consumer HDF evidence + amendments into SSP / SAP / SAR / POA&M is tracked in [#809](https://github.com/risk-sentinel/sparc/issues/809).

[Full release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.14.0).

## v1.13.2 -- Phishing-Resistant Authentication Enforcement (2026-07-25)

The **enforcement layer** over the MFA foundation from v1.13.0 and v1.13.1 — the controls an operator uses to *require* strong authentication org-wide. All new controls are **off by default**: existing deployments upgrade with no behaviour change and no configuration required.

- **Mandatory FIDO2 enrolment gate** ([#802](https://github.com/risk-sentinel/sparc/issues/802)) — `SPARC_REQUIRE_FIDO2` both enables FIDO2 and sets who must enrol a key before using the app (`off` / `local` / `all`). Users without a key are redirected to security-key management until they enrol; the break-glass admin and service accounts are exempt.
- **Require phishing-resistant sign-in** ([#805](https://github.com/risk-sentinel/sparc/issues/805)) — `SPARC_REQUIRE_AUTH_METHODS` is an allowlist of accepted login methods (e.g. `oidc,piv`). Anyone authenticating by a method not on the list is signed out with a clear message.
- Certificate-policy filtering for accepted smart cards, and the last raw-XML upload path closed.

[Full release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.13.2).

## v1.13.1 -- Configuration Simplification, TLS/Storage Posture, Help Center (2026-07-24)

A configuration-simplification and documentation release: **reduce what operators must set** by inferring and deriving configuration rather than requiring it. Nothing that worked before stops working — legacy variables remain honoured as fallbacks except where called out as breaking.

- **Configuration simplification** ([#785](https://github.com/risk-sentinel/sparc/issues/785), [#789](https://github.com/risk-sentinel/sparc/issues/789), [#791](https://github.com/risk-sentinel/sparc/issues/791), [#793](https://github.com/risk-sentinel/sparc/issues/793)) — prompted by a real deployment setting ~97 env vars, about half redundant. Enable-flags are inferred from credential presence, `DATABASE_URL` becomes the single preferred database source, and `SPARC_STORAGE_URL` the single object-storage variable.
- **Breaking posture changes to review before upgrading** — database `sslmode` floored at `require` in production (SC-8); object storage defaults to local disk and **production refuses to boot on it**, because an ECS/EKS container filesystem is ephemeral and uploads are silently lost on redeploy (CP-9, SI-12); the rate-limiting kill switch was **removed** in favour of a CIDR safelist; document approval now defaults on.
- **PIV/CAC identity mapping is configurable** ([#790](https://github.com/risk-sentinel/sparc/issues/790)) — `SPARC_PIV_IDENTITY_SOURCE` selects how identity is extracted rather than assuming one DoD certificate shape. Proven end to end against both DoD and non-DoD shapes.
- **In-app Help Center and User Guides** ([#781](https://github.com/risk-sentinel/sparc/issues/781), [#784](https://github.com/risk-sentinel/sparc/issues/784)) — the guides ship both as wiki pages with screenshots and in-app at `/help`.

[Full release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.13.1).

## v1.13.0 -- FIDO2 + PIV Authentication (App-Native MFA) (2026-07-21)

SPARC's first **app-native multi-factor authentication** — phishing-resistant and DoD-ready. A FIDO2 security key or a CAC/PIV smart card + PIN is now a complete, single-step login.

- **FIDO2 / WebAuthn passwordless sign-in** ([#779](https://github.com/risk-sentinel/sparc/issues/779)) — register a security key (YubiKey, Feitian, Token2, platform authenticators) with a PIN and sign in with no password; possession + knowledge in one ceremony satisfies MFA on its own. Authenticator-agnostic, usernameless with an email-first fallback; lockout recovery is an admin key-reset (no self-service codes by design). Enable with `SPARC_FIDO2_ENABLED`. See [Authentication and MFA](Authentication-and-MFA) and [User Guide: Security Keys](User-Guide-Security-Keys).
- **PIV / CAC smart-card sign-in** ([#779](https://github.com/risk-sentinel/sparc/issues/779)) — accepts a DoD PIV/CAC certificate, delivering **NIST IA-2(12) "Acceptance of PIV Credentials"**. The mTLS handshake + DoD PKI validation happen at the gateway (ALB/nginx, [sparc-iac#559](https://github.com/risk-sentinel/sparc-iac/issues/559)); SPARC consumes the validated cert, maps the EDIPI/email to a user, and fails closed unless the gateway attests verification. Enable with `SPARC_ENABLE_PIV`.
- **FIDO U2F** — covered for free via WebAuthn back-compat (non-resident second factor).

[Full release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.13.0).

## v1.12.3 -- Outbound-TLS Trust: LDAP Verify, Custom-CA, Proxy Egress (2026-07-20)

Hardening release. SPARC can now run in a locked-down enterprise or DoD environment (private CAs, a mandated TLS egress proxy, a verified LDAPS directory) **without weakening any verification** — closing the three gaps found by the v1.12.2 outbound-TLS audit.

- **LDAP verifies the directory server certificate** ([#773](https://github.com/risk-sentinel/sparc/issues/773)) — `simple_tls`/`start_tls` now verify with `VERIFY_PEER` by default (previously `VERIFY_NONE`, leaving bind credentials MITM-open). Supply the directory CA via `SPARC_LDAP_CA_FILE` or the container trust store; `SPARC_LDAP_TLS_VERIFY=false` is an env-gated, loudly-logged opt-out for legacy internal directories.
- **Custom / private-CA container trust** ([#774](https://github.com/risk-sentinel/sparc/issues/774)) — trust a private, corporate-proxy, or DoD-PKI CA via a runtime mount (`SPARC_EXTRA_CA_CERTS`, default `/rails/certs`) or a build-time bake (`certs/` → `update-ca-trust`). Folds into the OpenSSL trust store so **every** outbound client benefits (Net::HTTP, AWS SDK, and the LDAP default store); public CAs stay trusted.
- **Proxy-aware outbound HTTP** ([#775](https://github.com/risk-sentinel/sparc/issues/775)) — all outbound calls honor `HTTPS_PROXY`/`HTTP_PROXY`/`NO_PROXY` scheme-strictly via a shared `SparcHttp` client.

[Full release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.12.3).

## v1.12.2 -- Evidence API, hdf-cli 3.4.1, Boundary/Organization Management (2026-07-20)

A feature + fix patch release bundling eight PRs. Highlights:

- **Evidence API** ([#756](https://github.com/risk-sentinel/sparc/issues/756)) — evidence is fully manageable over REST (create, update, file-upload, associate with controls); document-scoped control links drive **OSCAL back-matter** via the durable `/artifacts/:uuid` resolver. Uploads guarded by an executable-signature deny-list + size cap (SI-10); `collected_at`/`collected_by` server-recorded (AU-10). See [API Reference §Evidence](API-Reference#evidence-v1122).
- **hdf-cli 3.2.0 → 3.4.1** ([#764](https://github.com/risk-sentinel/sparc/issues/764)) — moves the HDF↔OSCAL bridge off two silent data-corruption defects (fabricated POA&M expiry dates; conversion-time-stamped SARs) and drops the obsolete `baselines` injection. POA&M inputs to the amendments path now require `risks[].deadline`.
- **Boundary & organization management** ([#770](https://github.com/risk-sentinel/sparc/issues/770)) — configurable environments (`SPARC_ENVIRONMENTS_LIST`, six RMF defaults); a unified boundary Personnel Roster (admin-assigned + legacy memberships, AC-3); organization↔boundary association with an org-admin/instance-admin authorization matrix (AC-3/AC-6); and three UI fixes (CDEF filter on the environment form, uniform clickable Artifact Summary tiles, boundary-scoped artifact management). See [RBAC](RBAC#organization--boundary-assignment) and [Configuration](Configuration).
- **SonarCloud reliability** ([#762](https://github.com/risk-sentinel/sparc/issues/762)) — 9 fixes (keyboard-operable summary chips, no page-scroll on Space, table row headers, bounded STIG-parser regex); remaining findings triaged FP/won't-fix.
- **Admin: Create User** ([#755](https://github.com/risk-sentinel/sparc/issues/755)) over the shared provisioning service.
- **Security & deps** — `rails-html-sanitizer` 1.7.1 remediates an XSS advisory (GHSA-cj75-f6xr-r4g7, [#767](https://github.com/risk-sentinel/sparc/pull/767)); the scanner-findings audit was reconciled against the UBI9 prod image ([#777](https://github.com/risk-sentinel/sparc/pull/777)); GH Actions + AWS SDK bumps ([#768](https://github.com/risk-sentinel/sparc/pull/768)/[#769](https://github.com/risk-sentinel/sparc/pull/769)).

[Full release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.12.2).

## v1.12.1 -- UBI9 UTF-8 Locale Hotfix (2026-07-18)

Production hotfix for the v1.12.0 UBI9 image. Fixes **HTTP 500 on all full-layout pages** (including `/login`) whenever `SPARC_HEADER_TEXT` (the rules-of-behavior header) — or any operator env var rendered into a page, including the consent banner — contained **non-ASCII characters**. Root cause: UBI9 minimal ships no UTF-8 locale, so Ruby tags `ENV[]` values as BINARY (ASCII-8BIT) and rendering them into the UTF-8 layout raised `Encoding::CompatibilityError`; the prior Debian base set `LANG=C.UTF-8` implicitly, masking it. Adds `LANG`/`LC_ALL=C.UTF-8` to both build stages plus a **build-time guard** asserting `Encoding.default_external == UTF-8` so it can't silently regress ([#750](https://github.com/risk-sentinel/sparc/issues/750)). [Release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.12.1).

## v1.12.0 -- UBI9 Production Base-Image Cutover (2026-07-17)

Migrates the production image from Debian `ruby:slim` to **Red Hat UBI9** (Iron Bank / DISA-aligned), compiling Ruby + jemalloc from source and retiring the recurring Debian `perl`/`glibc` CVE-disposition treadmill ([#742](https://github.com/risk-sentinel/sparc/issues/742)). Multi-arch (amd64 + arm64), signed and SBOM-attested. **Known issue** (fixed in v1.12.1): non-ASCII header/banner text returns HTTP 500 on this image. [Release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.12.0).

## v1.11.1 -- Boundary-Scoped Document Access + Scan Tooling Hardening (2026-07-16)

Security release. Enforces **boundary-scoped access** across SSP, SAR, SAP, POA&M, Evidence, and CDEF — authenticated users only see and act on documents in the authorization boundaries they can access; global (nil-boundary) documents remain open. The web UI now enforces the same rules as the API via `BoundaryScopedDocument` (NIST AC-3) ([#738](https://github.com/risk-sentinel/sparc/issues/738), [#739](https://github.com/risk-sentinel/sparc/issues/739)). Adds evidence validity guards (system-recorded UTC provenance), SSP metadata enrichment sourced from canonical SPARC locations ([#737](https://github.com/risk-sentinel/sparc/issues/737)), and supply-chain/scan tooling hardening ([#743](https://github.com/risk-sentinel/sparc/issues/743)). [Release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.11.1).

## v1.11.0 -- Public-Surface Hardening + SonarCloud Remediation + Accessibility (2026-07-13)

Public-surface hardening plus the SonarCloud code-quality remediation and a large accessibility pass; no database migrations. **One behavior change** (opt-out via config): the **Controls layer is now gated behind authentication, secure-by-default** — Control Catalogs, Baselines, and Mappings are no longer public. A new `SPARC_PUBLIC_CATALOGS` flag (default `false`) lets deployments that front SPARC with their own network auth opt back into public sharing (#726, NIST AC-3). [Release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.11.0).

## v1.10.2 -- ODP Tooling, Artifact Lifecycle & CSP Hardening (2026-07-11)

Feature + hardening release. Adds **bulk ODP (Organization-Defined Parameter) import** for baselines/profiles — upload values as JSON / YAML / XML and preview a non-destructive diff (changed / unchanged / unknown / invalid) before applying, via `POST /api/v1/profile_documents/:id/parameters/import/{preview,confirm}`. Includes artifact-lifecycle and CSP hardening. [Release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.10.2).

## v1.10.1 -- OSCAL-Aligned Control-Field Naming (2026-07-02)

Maintenance release. Standardizes internal control-field naming to neutral, OSCAL-aligned identifiers for closer alignment with the OSCAL standard. A transparent data migration updates existing records automatically on deploy — **no operator action required**. [Release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.10.1).

## v1.10.0 -- Environment Header, Durable Artifact References & Index Search (2026-06-30)

Minor release. Adds a configurable **site-wide environment header bar** to label a deployment and its rules-of-use, via `SPARC_HEADER_TEXT` / `SPARC_HEADER_TEXT_COLOR` / `SPARC_HEADER_HIGHLIGHT_COLOR` (WCAG-passing defaults; operator colors honored as-is) ([#682](https://github.com/risk-sentinel/sparc/issues/682)). Also adds durable artifact references and document index search. [Release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.10.0).

## v1.9.1 -- POA&M-from-Amendments + Security Remediations (2026-06-28)

Cleanup on v1.9.0. Restores OSCAL POA&M generation under hdf-cli 3.2.0 via the new `POST /api/v1/oscal/poam_from_amendments` endpoint (`hdf convert --from hdf-amendments --to oscal-poam`) — the supported replacement for the removed direct `hdf → oscal-poam` converter ([#663](https://github.com/risk-sentinel/sparc/issues/663)). Ships as a full API-first surface (shared service + audit event + request/contract specs + INVENTORY/Postman entries), plus security remediations and an accessibility fix. [Release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.9.1).

## v1.9.0 -- Document Review & Approval Workflow (2026-06-26)

Minor release. Adds a **document review & approval workflow** — a new `Approvable` model, review queue, and `BaselineReviewService` / `DocumentApprovalService`, gated by `SPARC_REQUIRE_DOCUMENT_APPROVAL` (default off, so existing publish flows are unchanged until an org opts in) ([#640](https://github.com/risk-sentinel/sparc/issues/640), #630–634). Also adds **authoritative sources & federation** — add/import an authoritative source, plus a release-validation gate (API-coverage + nav CSP sweep) ([#657](https://github.com/risk-sentinel/sparc/issues/657), [#646](https://github.com/risk-sentinel/sparc/issues/646)). [Release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.9.0).

## v1.8.10 -- Container CVE Baseline, SCA SBOM Producer & API Pending Fix (2026-06-11)

First release since v1.8.6. Bundles a **container CVE-baseline remediation** (openssl patch, Ruby default-gem CVE pins, oauth2 bump; #621), an **org-wide SCA SBOM producer** that emits CycloneDX to S3 on push-to-main + daily via the shared container-build-sign workflows (#619), and a fix for **API-created documents stuck in `pending`** — metadata-only API creates now resolve to `completed`, with a new `StuckDocumentReaperJob` failing genuinely-stalled parses (#618). [Release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.8.10).

## v1.8.6 -- UI Accessibility (WCAG 2.1 AA) + UI Test Net (2026-06-03)

Accessibility + test-infrastructure release. Ships the **Section 508 / WCAG 2.1 AA** burndown ([#599](https://github.com/risk-sentinel/sparc/issues/599), [#602](https://github.com/risk-sentinel/sparc/issues/602)): a WORM (Write-Once, Read-Many) color architecture where semantic helper keys and single-source `.sparc-status` / `.sparc-heading` components own all contrast — views carry no badge/heading hex. **0 axe color-contrast / select-name / label / meta-refresh violations** across the 20 core pages in both light and dark themes. Adds the **UI Test Net** ([#572](https://github.com/risk-sentinel/sparc/issues/572)): Layer 2 Playwright post-deploy smoke and Layer 3 axe-core accessibility ratchet. Dependency patches incl. **puma 8.0.1 → 8.0.2** (PROXY-protocol-v1 injection hardening, [#601](https://github.com/risk-sentinel/sparc/issues/601)). [Release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.8.6).

## v1.8.5 -- Chromium OAuth Login Fix + DB-Enforced Email Uniqueness (2026-05-29)

Patch release. Restores SSO login in Chromium browsers — the global CSP `form-action 'self'` was blocking the OmniAuth → IdP redirect (Chromium enforces `form-action` on every redirect hop; Firefox does not), so login now relaxes `form-action` to the **configured IdP origins only** ([#593](https://github.com/risk-sentinel/sparc/issues/593)). Adds **database-enforced case-insensitive email uniqueness** via a functional `UNIQUE` index on `LOWER(email)`, plus two base-image `perl` CVE dispositions. [Release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.8.5).

## v1.8.4 -- API Session-from-Token Cookie Bridge (2026-05-27)

Closes [#573](https://github.com/risk-sentinel/sparc/issues/573) (Layer 2 prerequisite of the UI-testing umbrella [#572](https://github.com/risk-sentinel/sparc/issues/572)). Adds `POST /api/v1/sessions/from_token`, which exchanges a SPARC API Bearer token (or OIDC JWT) for a Rails session cookie so headless test runners (Playwright, Cypress, Chromium) can drive the UI as an authenticated user without scraping the login form. [Release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.8.4).

## v1.8.3 -- Deferred Data Migrations (2026-05-27)

Architectural fix removing the deploy kill-loop class of bug. Any `ActiveRecord::Migration` marked `include DeferredDataMigration` registers at `db:migrate` time (fast — no data work) and runs its body post-boot via an in-Puma Solid Queue job. The container binds its port and passes ECS health checks within seconds even on multi-minute data migrations. [Release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.8.3).

## v1.8.2 -- Critical: Back-Matter Promotion UUID Collision Fix (2026-05-27)

Production hotfix. `back_matter_resources.uuid` carries a **global** unique index, but v1.8.0's promotion stored the source OSCAL uuid directly as `BMR.uuid` — two documents legitimately referencing the same source uuid (common across SSP/SAR/SAP/CDEF for shared NIST 800-53 references) crashed the second INSERT mid-migration. Resolves the `Uuid has already been taken` deploy failure. [Release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.8.2).

## v1.8.1 -- Login OIDC Tab CSP Regression Hotfix (2026-05-27)

Production hotfix. The v1.7.0 CSP ([#514](https://github.com/risk-sentinel/sparc/issues/514)) enforced `script-src` with no `'unsafe-inline'`; the login page's tab switching used inline `onclick=` handlers (not nonce-exempt), so users with both local + OIDC/LDAP enabled could not click the Okta/LDAP tabs. Tab handlers moved to nonce'd scripts. Also captures `login_failure` reason codes. [Release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.8.1).

## v1.8.0 -- CdefMutationService + Back-Matter Promotion (2026-05-27)

Minor release. Every CDEF mutation now funnels through **`CdefMutationService`**, which validates the post-mutation OSCAL against the NIST component-definition v1.1.2 schema **before** the transaction commits — an invalid result is rejected pre-commit instead of silently persisting. OSCAL back-matter is **promoted** out of the legacy `import_metadata["back_matter"]` stash to first-class `BackMatterResource` rows across SSP / SAR / SAP / Profile / POA&M, with `BackMatterResourceChange` audit rows on mutation. Bundles [#498](https://github.com/risk-sentinel/sparc/issues/498), [#581](https://github.com/risk-sentinel/sparc/issues/581), [#582](https://github.com/risk-sentinel/sparc/issues/582), [#583](https://github.com/risk-sentinel/sparc/issues/583), [#584](https://github.com/risk-sentinel/sparc/issues/584). [Release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.8.0).

## v1.7.4 -- Nested-Route id-or-slug + RBAC Permission Gating (2026-05-26)

Patch release closing the last two API contract-drift bugs from the [#433](https://github.com/risk-sentinel/sparc/issues/433) test suite. The `authorization_boundaries` controller and every nested controller under it now accept **either an id or a slug** in the URL ([#574](https://github.com/risk-sentinel/sparc/issues/574)), plus RBAC permission-gating fixes. [Release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.7.4).

## v1.7.3 -- API Contract + Compliance Drift Bundle (2026-05-26)

Patch release fixing five prod drift bugs surfaced by the [#433](https://github.com/risk-sentinel/sparc/issues/433) content-style tests. Notably, five `#update` endpoints (cdef_documents, control_catalogs, control_mappings, profile_documents, and the SSP/SAR/SAP/POA&M document base) now return the **detailed** serialization so callers can read-after-write to confirm a change ([#555](https://github.com/risk-sentinel/sparc/issues/555)). [Release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.7.3).

## v1.7.2 -- Pagination + Processing-Banner Trap + CI Fix (2026-05-24)

Patch release. `Api::V1::BaseController#paginate` now reads `params[:items]` / `params[:per_page]` (previously ignored, so every index returned the default) with a clamp at `MAX_PAGINATION_LIMIT = 200` to block `?items=999999` DoS attempts ([#549](https://github.com/risk-sentinel/sparc/issues/549)). Includes a processing-banner fix and a critical CI workflow fix that unblocks image publication. [Release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.7.2).

## v1.7.1 -- Prod Bug Fixes Unblocking API Test Suite (2026-05-24)

Patch release covering three prod issues surfaced during [#433](https://github.com/risk-sentinel/sparc/issues/433) API testing against `sparc.risk-sentinel.org`. Headline: recovers the `cloned_from_id` column on `cdef_documents` (lost on databases that crossed the [#470](https://github.com/risk-sentinel/sparc/issues/470) squash boundary), fixing a 500 on every `/api/v1/cdef_documents` verb ([#537](https://github.com/risk-sentinel/sparc/issues/537)). [Release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.7.1).

## v1.6.6 -- Hotfix: SeedRunner Converters Version Bump (2026-05-19)

Two-line deploy hotfix ([#495](https://github.com/risk-sentinel/sparc/pull/495)). v1.6.5 added new `converters` seed sections but did not bump `SeedRunner::CURRENT_VERSIONS["converters"]`, so production deploys skipped the section and the new `aws_config_to_nist` Converter never appeared. Bumps `converters` `1.2.0 → 1.3.0`. [Release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.6.6).

## v1.6.5 -- Decoupled AWS Converters with Refresh UI (2026-05-19)

Cleans up the v1.6.4 AWS Labs bootstrap initializer (`ApplicationRecord` autoload `NameError` + 3×-per-boot firing, [#492](https://github.com/risk-sentinel/sparc/issues/492)) and splits the v1.6.4 composite AWS converter into two first-class converters (`aws_config_to_nist`, `aws_security_hub_to_nist`) that operators can **refresh independently** from the converter management page ([#494](https://github.com/risk-sentinel/sparc/issues/494)). [Release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.6.5).

## v1.6.4 -- AWS Labs CDEF Bootstrap + Admin Refresh Button (2026-05-18)

Patch release delivering the operator-facing half of AWS Labs CDEF runtime ingestion ([#466](https://github.com/risk-sentinel/sparc/issues/466)). A new initializer enqueues `AwsLabsCdefRefreshJob` on the first boot where `SPARC_AWS_LABS_CDEF_ENABLED=true` and no AWS-Labs rows exist, so tenants don't wait for the weekly tick ([#487](https://github.com/risk-sentinel/sparc/issues/487)). Bundles a `faraday` security bump and a `thruster` patch. [Release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.6.4).

## v1.6.3 -- Apache-2.0 License Harmonization (2026-05-18)

Legal-terms harmonization. The top-level `LICENSE` is now **Apache License 2.0**, matching what `NOTICE`, `THIRD_PARTY_NOTICES.md`, the component dispositions, and the `LICENSES/` texts had assumed since v1.6.0 — chosen for its express patent grant and NOTICE provision ([#483](https://github.com/risk-sentinel/sparc/issues/483)). Ships alongside the [#481](https://github.com/risk-sentinel/sparc/issues/481) unmapped-component triage. [Release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.6.3).

## v1.6.2 -- Open-Source Readiness: License Inventory + Policy (2026-05-18)

No new app features — the infrastructure of supply-chain transparency. Consolidates three CycloneDX SBOMs into a canonical license inventory (`license-inventory.json` / `.md`), adds declarative `license-policy.yml` + per-component `license-dispositions.yml` (policy-as-code), enables Trivy `--scanners license`, and removes the only GPL-3.0 runtime dependency ([#472](https://github.com/risk-sentinel/sparc/issues/472)). [Release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.6.2).

## v1.6.1 -- SBOM-Driven SCA, AWS Labs CDEFs, SAF CLI Hardening (2026-05-17)

Maintenance + capability release. Adds **Grype** SBOM vulnerability scanning consuming the CycloneDX SBOMs (SARIF + HDF, [#461](https://github.com/risk-sentinel/sparc/issues/461)), hardens HDF normalization (Node 22 pin + cdxgen JSON SBOM, [#463](https://github.com/risk-sentinel/sparc/issues/463)), and clears the dependency-bump backlog with the second migration squash. [Release notes](https://github.com/risk-sentinel/sparc/releases/tag/v1.6.1).

## v1.6.0 -- HDF ↔ OSCAL Translation Bridge, CMS Attestation Export & OSCAL Export Hardening (2026-05-08)

Minor release. Ships the [#449](https://github.com/risk-sentinel/sparc/issues/449) **HDF ↔ OSCAL translation bridge** — three stateless API endpoints that let tenant compliance pipelines move scan data between the HDF and OSCAL ecosystems without managing the `hdf` CLI on their side. Bundled with [#440](https://github.com/risk-sentinel/sparc/issues/440) **CMS attestation export**, [#451](https://github.com/risk-sentinel/sparc/issues/451) **OSCAL export schema-validation hardening + uniform error UX**, and [#453](https://github.com/risk-sentinel/sparc/issues/453) **OSCAL schemas baked into the container** (decouples runtime validation from NIST GitHub availability — multi-version validation now works air-gapped). **No breaking changes**; existing deployments upgrade in place.

Full release notes (with verification evidence) live on the [v1.6.0 GitHub release page](https://github.com/risk-sentinel/sparc/releases/tag/v1.6.0).

### Highlights

- **HDF ↔ OSCAL translation bridge ([#449](https://github.com/risk-sentinel/sparc/issues/449))** — three new authenticated endpoints under `/api/v1/`:
  - `POST oscal/sar_from_hdf` — HDF results → OSCAL Assessment Results
  - `POST oscal/poam_from_hdf` — HDF results → OSCAL Plan of Action and Milestones
  - `POST hdf/amendments_from_oscal_poam` — OSCAL POA&M → HDF Amendments JSON (round-tripped through `hdf amend verify` before serving)
- **Optional Evidence back-matter enrichment** — pass `?authorization_boundary_id=N` to either OSCAL emission endpoint and SPARC merges the boundary's Evidence + Attestation records into the OSCAL output as `back-matter.resources[]` (with control-id, attestation provenance, and rlinks). Requires `evidence.read` on the boundary.
- **`hdf` binary baked into the SPARC container** — `bin/install-hdf.sh` provisions MITRE hdf-libs v3.1.0 from GitHub releases, SHA-256 verified against `checksums.txt`. Same script used by the security_gate CI job; bumping `HDF_LIBS_VERSION` updates both surfaces.
- **CMS attestation JSON export ([#440](https://github.com/risk-sentinel/sparc/issues/440))** — `Api::V1::AttestationsController#export` emits SPARC attestations in the canonical CMS / SAF CLI 6-field schema, denormalized one record per linked control_id. New `frequency` + `status` columns on `attestations` align SPARC with the upstream pattern without forking the internal model.

### Added

- `app/services/hdf_runner.rb` — Ruby subprocess wrapper centralizing all `hdf` CLI invocations (convert / validate / info / stats / amend_verify / amend_apply / version) with structured error class
- `app/services/hdf_oscal_translation_service.rb` — three translation flows + back-matter enrichment helpers
- `app/controllers/api/v1/translations_controller.rb` — public REST surface for the translation bridge
- `app/services/cms_attestation_export_service.rb` — emits CMS attestation JSON (one record per linked control)
- `app/controllers/api/v1/attestations_controller.rb` — fills the existing UI-only API gap; CRUD + `:export`
- `bin/install-hdf.sh` — single source of truth for hdf-cli install (Dockerfile + CI + local dev)
- `docs/compliance/hdf-oscal-bridge-demo.md` — pipeline-only curl demo for the translation surface

### Changed

- `Dockerfile` bakes the verified `hdf` binary into `/usr/local/bin/` via the bootstrap stage (no curl/gnupg in the production image)
- `.github/workflows/security.yml` security_gate now uses `bin/install-hdf.sh` instead of an inline curl-tar block
- `app/models/attestation.rb` gains `frequency` + `status` columns and inclusion validators
- `attestations` UI form gains frequency + status selects
- NIST mapping (CA-2, CA-7, RA-3, SI-2) updated for the new translation surface and CMS export

### Fixed (#451)

- **OSCAL export schema-validation leak** — `OscalMetadata#build_oscal_metadata` was merging the entire `metadata_extra` blob into OSCAL output. ProgressTrackable's `processing_stage` / `processing_message` / `processing_*_at` keys leaked into metadata and tripped schema validation. Switched to `slice(*METADATA_EXTRA_KEYS)` allowlist — covers every document type that includes the concern. Version-agnostic.
- **YAML/XML download 500s** — `download_yaml` / `download_xml` across CDEF, SSP, SAR, POAM, Profile, SAP, and Catalog now rescue `OscalValidationError` and redirect with a flash message that includes the `?skip_validation=1` escape hatch, matching the existing `download_oscal` UX.
- **Inconsistent error UX across views** — six index views (CDEF, SSP, SAR, POAM, Profile, SAP) replaced their inline plain-link export dropdowns with the shared `_oscal_export_dropdown` partial. The Stimulus controller's new `connect()` hook reads `?oscal_validation_failed=1&oscal_format=…` from the redirected show page and auto-opens the validation modal so direct-URL hits land in the same modal as dropdown clicks. Every human-facing path → same modal, same specific errors.

### Schema infrastructure (#453)

- **OSCAL schemas baked into the container** — new `oscal:bundle_schemas` rake task downloads all 5 supported versions (1.1.1 / 1.1.2 / 1.1.3 / 1.2.0 / 1.2.1) × 8 document types from NIST GitHub release assets at Docker build time and writes them to `lib/oscal_schemas_bundle/v<version>/<file>` plus a `manifest.json` with SHA-256 checksums. `oscal:seed_schemas` extended with three-tier fallback: bundle (offline, checksum-verified) → NIST GitHub fetch → legacy disk fallback. Air-gapped deployments validate against all 5 versions without runtime network dependency.
- **Two pre-existing bugs fixed in passing**: `OscalSchema::NIST_SCHEMA_URL_TEMPLATE` was pointing at a `raw.githubusercontent.com/.../json/schema/...` path that NIST never published — every fetch was 404'ing and silently falling back to disk; only v1.1.2 was ever loaded into the DB. URL corrected to the GitHub release-asset path. `DOCUMENT_TYPE_MAP` had `oscal_component-definition_schema.json` for component-definition; NIST publishes it as `oscal_component_schema.json` — corrected to match the validator's `SCHEMA_MAP`.

### Migrations

- `add_frequency_and_status_to_attestations` — adds `frequency` (string, nullable) + `status` (string, default `"passed"`, NOT NULL) + index on `status`. Backwards-compatible; existing rows default to `passed`.

### Verified

- `bundle exec rspec` — 2150+ examples, 0 failures, 2 pending (real-binary integration specs gated on `hdf` being on PATH)
- `bundle exec rubocop` — clean on changed files
- `bundle exec brakeman` — clean (2 ignored, 0 active)
- HDF binary install script verified against MITRE release SHA-256
- OSCAL schema bundle verified end-to-end: 37 schemas downloaded, 37 SHA-256 verified at seed time, 37 loaded into the DB

---

## v1.5.0 -- API Test Suite, Org Migration & Dependency Hardening (2026-05-04)

Minor release. Ships the comprehensive Python pytest API test suite ([#413](https://github.com/risk-sentinel/sparc/issues/413), [PR #432](https://github.com/risk-sentinel/sparc/pull/432) — 247 tests across 18 modules covering every documented endpoint), completes the GitHub org migration to `risk-sentinel` ([#430](https://github.com/risk-sentinel/sparc/issues/430)), and absorbs a wave of dependency security patches and bumps. **No breaking changes** to SPARC user-visible behavior — existing deployments upgrade in place.

Full release notes (with verification evidence and audit context) on the [v1.5.0 GitHub release page](https://github.com/risk-sentinel/sparc/releases/tag/v1.5.0).

### Highlights

- **Python pytest API test suite** — 247 tests, 18 modules, all 95 endpoints covered. Lives at `tests/api/`. ([#413](https://github.com/risk-sentinel/sparc/issues/413), [PR #432](https://github.com/risk-sentinel/sparc/pull/432))
- **GitHub org migration** — `Rebel-Raiders/sparc` → `risk-sentinel/sparc`. Workflows, cosign identity regex, cross-repo dispatch, docs, wiki, compliance CDEFs all retargeted. ([#430](https://github.com/risk-sentinel/sparc/issues/430), [PR #434](https://github.com/risk-sentinel/sparc/pull/434))
- **Security patches** — `net-imap` STARTTLS-stripping (GHSA-vcgp-9326-pqcp) + CRLF injection (GHSA-75xq-5h9v-w6px, GHSA-hm49-wcqc-g2xg) ([PR #438](https://github.com/risk-sentinel/sparc/pull/438)); `erb` defense-in-depth against `Marshal.load` of attacker-controlled ERB instances ([PR #410](https://github.com/risk-sentinel/sparc/pull/410)).
- **`jwt` major bump** — 2.10.2 → 3.1.2. SPARC's JWT consumer surface verified compatible (only one file uses the gem); new regression spec covers happy + rejection paths. ([PR #289](https://github.com/risk-sentinel/sparc/pull/289))

### Added

- Python pytest suite at `tests/api/` — request-level contract coverage for every documented endpoint, parametrized for the three auth modes ([#413](https://github.com/risk-sentinel/sparc/issues/413))
- API documentation review — Phase 1 closed: 100% endpoint doc coverage, Postman collection now covers all 95 endpoints ([#413](https://github.com/risk-sentinel/sparc/issues/413), [PR #427](https://github.com/risk-sentinel/sparc/pull/427), [PR #428](https://github.com/risk-sentinel/sparc/pull/428), [PR #429](https://github.com/risk-sentinel/sparc/pull/429), [PR #431](https://github.com/risk-sentinel/sparc/pull/431))
- API procedure document — review-and-automated-testing workflow at `docs/api/SPARC-API-Review-and-Automated-Testing-Procedure.md`
- OIDC JWT decode regression spec — closes the test-coverage gap for the live JWT happy path ([PR #289](https://github.com/risk-sentinel/sparc/pull/289))
- `.github/CODEOWNERS` — admin review required for non-admin PRs ([#435](https://github.com/risk-sentinel/sparc/issues/435))

### Changed

- Repository now lives at `https://github.com/risk-sentinel/sparc`. All cross-repo references in workflows (cosign identity regex, `repository_dispatch` target), app code, docs, wiki, and OSCAL CDEF `remarks` retargeted ([#430](https://github.com/risk-sentinel/sparc/issues/430))
- Implementation plan reorganized — Phase 12 (post-migration test/CI hardening + federation follow-ups) added with priority-ordered backlog ([PR #439](https://github.com/risk-sentinel/sparc/pull/439))

### Security

- **`net-imap` 0.6.3 → 0.6.4** ([PR #438](https://github.com/risk-sentinel/sparc/pull/438))
  - GHSA-vcgp-9326-pqcp — STARTTLS stripping (MITM could silently prevent TLS upgrade)
  - GHSA-75xq-5h9v-w6px, GHSA-hm49-wcqc-g2xg — CRLF / command / argument injection
- **`erb` 6.0.2 → 6.0.4** ([PR #410](https://github.com/risk-sentinel/sparc/pull/410)) — defense-in-depth: prohibit `def_method` on marshal-loaded ERB instances; release-tooling and packaging fixes
- **`jwt` 2.10.2 → 3.1.2** ([PR #289](https://github.com/risk-sentinel/sparc/pull/289)) — major version bump; the v3 line requires explicit algorithm on JWK verify (SPARC already passes `algorithms: ["RS256"]`), enforces RSA ≥2048 bits (Okta JWKS already meets this), and stricter base64 (RFC 4648). Audit found one consumer (`app/controllers/concerns/api_authentication.rb`); new spec covers a real RS256 token through the full decode path

### Dependencies

- `aws-sdk-s3` 1.219.0 → 1.220.0
- `aws-sdk-rds` 1.310.0 → 1.311.0
- `bootsnap` 1.23.0 → 1.24.1
- `faker` 3.6.1 → 3.8.0
- `rubyzip` 3.2.2 → 3.3.0 (in-major; only behavioral change in 3.3.0 is `Zip::InputStream` IO-compat refactor — SPARC consumers unaffected)
- `aws-sdk-core` 3.244.0 → 3.246.0, `aws-sdk-kms` 1.123.0 → 1.124.0, `aws-partitions` 1.1237.0 → 1.1244.0 (transitive)

([PR #437](https://github.com/risk-sentinel/sparc/pull/437) bundled the application-direct deps in this group.)

### Verification

Full RSpec on the merged dependency state: **2076 examples, 0 failures**. `bundle exec rubocop` clean.

---

# Legacy history (pre-v1.x reset)

> The entries below predate SPARC's adoption of the public **v1.x** release
> line. The `(unreleased)` items (2026-03) and the `v2.x`–`v3.x` versions
> were the project's earlier internal numbering. They are retained verbatim
> for traceability; their functionality is present in the current v1.x
> releases above.

## (unreleased) -- OSCAL XML Catalog Parameters & Baseline Adjustments (2026-03-11)

### Added
- **OSCAL XML catalog import** — full support for OSCAL 1.x XML serialization format alongside existing JSON and legacy SCAP XML imports; correctly parses `<param>`, `<select>`, `<choice>`, `<label>`, and `<guideline>` elements into the same `params_data` structure as JSON imports ([Issue #162](https://github.com/risk-sentinel/sparc/issues/162))
- **Parameter suggestion badges** — profile control edit form now shows clickable catalog-defined choices as quick-pick badges above the text input for selection-type parameters; users can click to fill or type custom values ([Issue #162](https://github.com/risk-sentinel/sparc/issues/162))
- **Selection info in profile show view** — read-only parameter display now shows available catalog options for selection-type parameters
- **CatalogImportService specs** — 29 new tests covering OSCAL XML format detection, parameter extraction (label, select/choice, guideline, props), enhancement recursion, and JSON regression

---

## (unreleased) -- Home Screen OSCAL Layer Alignment (2026-03-11)

### Changed
- **Home screen cards grouped by OSCAL layers** — Controls (blue), Implementation (green), Assessment (orange), and Environments (purple) with section headers and colored accent bars ([Issue #164](https://github.com/risk-sentinel/sparc/issues/164))
- **Control Mapping card added** to home screen under Controls Layer
- **Stat tiles redesigned with horizontal OSCAL layer labels** — replaced vertical truncated text badges with full horizontal labels (CONTROLS, IMPLEMENTATION, ASSESSMENT, ENVIRONMENTS) above each metric group; each group wrapped in a color-coded container with accent border and tinted background ([Issue #164](https://github.com/risk-sentinel/sparc/issues/164))
- **Unique family & control counts** — Families and Controls tiles now show distinct counts across all catalogs instead of total rows
- **Login page OSCAL diagram** updated to include Mapping Model in the Controls Layer
- **Login page branding upsized** — SPARC logo enlarged from 72px/88px to 96px/120px (mobile/desktop), Welcome heading upgraded from h4 to h3, and description text set to standard body size

### Fixed
- **Heatmap card click filtering** — clicking anywhere on a heatmap family card body now filters by that family, not just badges/links ([Issue #159](https://github.com/risk-sentinel/sparc/issues/159))
- **Family group visibility** — empty family groups are hidden when heatmap filter is active
- **Profile show page** — controls grouped by collapsible NIST families with Expand/Collapse All buttons; catalog sub-parts shown as nested implementation statements

### Added
- **NIST catalog fixture files** — Rev 4 (XML, YAML) and Rev 5 (JSON, YAML) catalog fixtures for test coverage

---

## (unreleased) -- Control Family Selection/Deselection (2026-03-10)

### Added
- **Family-level control selection** — "Create Profile from Catalog" page now groups controls by family in collapsible accordions with family-level select/deselect checkboxes, tri-state indicators, and expand/collapse all ([Issue #151](https://github.com/risk-sentinel/sparc/issues/151))
- **Baseline auto-select** — choosing a baseline level (LOW, MODERATE, HIGH) auto-checks all controls matching that impact level via a dedicated server endpoint, keeping baseline logic server-side
- **Manage Controls page** — existing catalog-linked profiles now have a "Manage Controls" button to bulk add/remove controls with parameter inheritance from the source catalog
- **Stimulus controller** — `family_selector_controller.js` replaces inline vanilla JS with proper Hotwire architecture; supports both dynamic (create) and server-rendered (manage) modes
- `profile_controls_bulk_updated` audit event action for tracking bulk control changes

---

## (unreleased) -- OSCAL Document UUID & Back Matter (2026-03-10)

### Added
- **Stable document UUID** — dedicated `uuid` column on all six OSCAL document tables (SSP, SAR, CDEF, SAP, POAM, Profile), auto-generated by Postgres `gen_random_uuid()`. OSCAL imports preserve the source document UUID. Exports use the stable column value instead of generating a random UUID each time. ([Issue #147](https://github.com/risk-sentinel/sparc/issues/147))
- **OSCAL back-matter support** — every exported OSCAL document now includes a `back-matter` section with a SPARC-identifying resource (title, description, rlink to app URL) for auditor traceability
- **Centralized back-matter logic** — `OscalMetadata` concern provides `build_oscal_back_matter` and `sparc_back_matter_resource` methods, eliminating duplicate implementations across export services
- **Round-trip back-matter fidelity** — imported back-matter resources are fully preserved and merged with the SPARC resource on export; Profile parser no longer strips resource fields
- **Parser consistency** — all six JSON parsers now store both `uuid` and `back_matter` in `import_metadata` (SAP and CDEF parsers were previously missing these)
- Missing `cdef_document_imported`, `poam_document_imported`, and `profile_document_imported` audit event actions added to `AuditEvent` whitelist

---

## (unreleased) -- User Lifecycle Enhancements (2026-03-10)

### Added
- **User UUID** — immutable UUID column for audit traceability, auto-generated by Postgres `gen_random_uuid()` ([Issue #146](https://github.com/risk-sentinel/sparc/issues/146))
- **Soft-delete (deactivate)** — admin can deactivate users instead of hard-deleting; records `deleted_at` timestamp and `inactive_reason` for audit trails
- **Reactivate with force password reset** — admin checkbox to require password change on reactivation
- **Password expiration** — local-auth users are forced to change password after configurable `SPARC_PASSWORD_EXPIRY_DAYS` (default 30); OAuth/SSO users are exempt
- **Automatic inactivity deactivation** — `InactivityCheckJob` deactivates users who haven't signed in within `SPARC_INACTIVITY_DAYS` (default 30)
- `SPARC_INACTIVITY_DAYS` and `SPARC_PASSWORD_EXPIRY_DAYS` environment variables for user lifecycle configuration
- Admin user show page displays UUID, password changed date, deactivation details, and 3-way status badge (success/warning/danger)
- Deactivated users see a specific "account has been deactivated" message at login (not generic "invalid")
- Missing `organization_*` audit event actions added to `AuditEvent` whitelist

---

## (unreleased) -- Organization Management (2026-03-10)

### Added
- **Organization entity** with UUID-based audit traceability — organizations own authorization boundaries and serve as the parent grouping unit ([Issue #145](https://github.com/risk-sentinel/sparc/issues/145), [Issue #137](https://github.com/risk-sentinel/sparc/issues/137))
- Admin CRUD interface for organizations with search, status filtering, and pagination
- Organization membership management with senior-official-pattern roles (Org Admin, Head of Agency, CIO, CISO, Risk Executive, etc.)
- Soft-delete via deactivate/reactivate — organizations are never hard-deleted, preserving UUID for audit trails
- Authorization boundaries now link to a parent organization (`organization_id` foreign key)
- `SPARC_ORG_*` environment variables for configuring the default organization name, description, address, and contact info
- Default organization seeded with admin user as org_admin

---

## v3.4.8 -- Home Screen & Navigation UX (2026-03-09)

### Fixed
- Dashboard section cards now have consistent OSCAL-layer-colored borders — Controls (blue), Implementation (green), Assessment (orange), Boundaries (purple) — with uniform hover effect ([Issue #152](https://github.com/risk-sentinel/sparc/issues/152))
- "Auth Boundaries" navbar link upgraded to dropdown showing the user's assigned boundaries with status badges and quick navigation; admins see all boundaries ([Issue #153](https://github.com/risk-sentinel/sparc/issues/153))

---

## v3.4.7 -- Control Parameters & Profile Publish (2026-03-09)

### Added
- Catalog-level OSCAL parameter definitions (`params`) extracted and stored during catalog import as `params_data` JSONB column on `catalog_controls` ([Issue #143](https://github.com/risk-sentinel/sparc/issues/143))
- Control family show view displays parameter badges and expandable parameter details (ID, label, constraint/choices)
- Catalog control edit form with editable parameter labels for organization-specific customization
- OSCAL catalog export now emits `params` array on controls when present
- Profile "Create from Catalog" inherits parameter definitions from the catalog (not empty)
- Per-parameter value editing in profile control form with save-your-work support
- **Publish** action on profiles generates a fully-resolved OSCAL catalog merging catalog data with profile modifications (priority, parameter values)
- Resolved catalog download available after publish via Export dropdown
- `OscalResolvedProfileCatalogService` for building resolved profile catalogs

### Fixed
- Delete buttons across all index views now work with Turbo (changed `link_to method: :delete` to `button_to` with `turbo_confirm`)
- Profiles index table fits viewport without horizontal scrolling (fixed-layout table with truncated names)

### Note
- Re-seed catalogs (`bin/rails db:seed`) to populate `params_data` on existing catalog controls
- Run migration for new `resolved_catalog_json` column on `profile_documents`

---

## v3.4.6 -- Fix Docker Migration Failure (2026-03-09)

### Fixed
- Removed duplicate `error_message` column addition from `AddOscalSspEntities` migration that caused `docker compose up --build` to fail on existing Postgres volumes ([Issue #140](https://github.com/risk-sentinel/sparc/issues/140))

---

## v3.4.5 -- Heatmap Removal & Environment UX Fix (2026-03-09)

### Fixed
- Removed aggregate compliance heatmap from home page -- document-level heatmaps remain on individual SSP, SAR, CDEF, SAP, and Profile pages ([Issue #136](https://github.com/risk-sentinel/sparc/issues/136))
- Renamed "Boundaries & Components" section to "Environments & Components" on authorization boundary show page for clearer terminology ([Issue #136](https://github.com/risk-sentinel/sparc/issues/136))

---

## v3.4.4 -- Authorization Boundary Rebrand (2026-03-09)

### Changed
- Rebranded "Project" to "Authorization Boundary" throughout the application -- models, controllers, views, routes, database schema, and documentation now align with NIST RMF / FedRAMP terminology ([Issue #124](https://github.com/risk-sentinel/sparc/issues/124))
- Renamed database tables `projects` to `authorization_boundaries`, `project_memberships` to `authorization_boundary_memberships`
- Renamed all `project_id` foreign key columns to `authorization_boundary_id`
- Updated role scope from `project` to `authorization_boundary`
- Updated permission keys from `projects.*` to `authorization_boundaries.*`
- Added `docs/groups_users/mindmap.md` capturing Organization to Authorization Boundary to OSCAL Artifacts hierarchy

---

## v3.4.3 -- HTTPS Enforcement & Security Headers (2026-03-09)

- Enforce HTTPS-only traffic with HSTS preload, subdomains, and 1-year max-age ([Issue #106](https://github.com/risk-sentinel/sparc/issues/106))
- Health-check endpoint `/up` excluded from SSL redirect for container probes (ALB, Kubernetes)
- Security headers middleware: `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy`, `Permissions-Policy`, `X-Permitted-Cross-Domain-Policies`
- Content Security Policy enabled in report-only mode (Bootstrap CDN allowlisted)
- Centralized version constant in `SparcConfig::VERSION` — no longer hardcoded in layouts
- HTTPS enforcement and security headers test coverage

## v3.4.2 -- Hide Expected Upload Fields from Upload UI (2026-03-09)

- Removed hardcoded "Expected Format" tables from SSP and SAR upload pages ([Issue #129](https://github.com/risk-sentinel/sparc/issues/129))
- Replaced with concise import notes referencing data mapping definitions (`lib/data_mappings/`)
- OSCAL files (JSON, XML, YAML) noted as auto-detected with no mapping required

## v3.4.1 -- Full Multi-Format Support (2026-03-09)

- Full OSCAL tri-format support: import and export JSON, YAML, and XML for all six document types ([Issue #120](https://github.com/risk-sentinel/sparc/issues/120))
- Six new YAML parser services (SSP, SAR, POAM, Profile, CDEF, SAP) using delegation pattern to avoid logic duplication
- New SAP XML parser service (`SapXmlParserService`) completing XML import coverage for all document types
- OSCAL export format conversion via `OscalExportFormatService` (JSON to YAML/XML)
- OSCAL JSON-to-XML converter (`OscalJsonToXmlConverter`) with Nokogiri XML::Builder and OSCAL namespace
- XSD schema validation for XML exports via `Nokogiri::XML::Schema` with 7 OSCAL XSD schemas
- Format auto-detection service (`OscalFormatDetectionService`) with extension and content sniffing
- Bootstrap 5 split-button dropdown for OSCAL export format selection across all document views
- Upload forms updated to accept `.yaml` and `.yml` extensions
- Fixed pre-existing bug in `CdefJsonParserService#parse_oscal_cdef` (wrong method call for batch insert)

## v3.4.0 -- Robust Audit Logging (2026-03-09)

- Comprehensive audit logging with approximately 80 tracked actions across 16 categories ([PR #121](https://github.com/risk-sentinel/sparc/pull/121), [Issue #101](https://github.com/risk-sentinel/sparc/issues/101))
- Polymorphic subject tracking (`subject_type`/`subject_id`) for resource-level traceability
- Admin audit log UI at `/admin/audit_logs` with filtering, detail views, and CSV export
- `Auditable` controller concern providing a DRY `audit_log` helper method
- Structured JSON logging to `Rails.logger.info` for integration with CloudWatch/Datadog ([PR #122](https://github.com/risk-sentinel/sparc/pull/122))
- Fixed silent audit failures in `ControlMappingsController`
- Authorization failure logging for security monitoring

## v3.3.0 -- Navbar Redesign (2026-03-09)

- Redesigned navbar with OSCAL layer dropdowns organized by function:
  - **Controls** (blue) -- Catalogs, Baselines, Control Mappings
  - **Implementation** (green) -- SSP, CDEF
  - **Assessment** (orange) -- SAP, SAR, POA&M
- User avatar system with upload and remove functionality
- Version badge displayed in the navbar
- [PR #118](https://github.com/risk-sentinel/sparc/pull/118) -- Control Mapping Models

## v3.2.1 -- Bug Fix (2026-03-09)

- Fixed user dropdown menu not opening after Turbo navigation ([PR #117](https://github.com/risk-sentinel/sparc/pull/117), [Issue #116](https://github.com/risk-sentinel/sparc/issues/116))

## v3.2.0 -- RBAC Enforcement & Summary Tiles (2026-03-08)

- Full OSCAL/RMF/FedRAMP role coverage with 29 roles ([PR #115](https://github.com/risk-sentinel/sparc/pull/115))
- Restricted catalog and baseline editing to Policy Manager and Instance Admin ([Issue #99](https://github.com/risk-sentinel/sparc/issues/99))
- Summary tiles across all main sections for at-a-glance status ([Issue #103](https://github.com/risk-sentinel/sparc/issues/103))
- Added SPARC SME and Evidence Integration Engineer roles ([Issue #96](https://github.com/risk-sentinel/sparc/issues/96))

## v3.1.1 -- SSP Rebrand (2026-03-08)

- Rebranded "Controls Implementation" to "System Security Plan" throughout the application ([PR #113](https://github.com/risk-sentinel/sparc/pull/113), [Issue #97](https://github.com/risk-sentinel/sparc/issues/97))

## v3.1.0 -- RBAC Admin Screens (2026-03-08)

- User administration screen with search, suspend, and reactivate capabilities ([Issue #93](https://github.com/risk-sentinel/sparc/issues/93))
- Role administration with permission matrix editing ([Issue #94](https://github.com/risk-sentinel/sparc/issues/94))
- Authorization boundary administration with member and role management ([Issue #92](https://github.com/risk-sentinel/sparc/issues/92))
- [PR #112](https://github.com/risk-sentinel/sparc/pull/112)

## v3.0.0 -- Authentication & RBAC Foundation (2026-03-08)

- Local email/password authentication conforming to NIST SP 800-63B ([Issue #70](https://github.com/risk-sentinel/sparc/issues/70))
- OAuth support for GitHub and GitLab ([Issue #34](https://github.com/risk-sentinel/sparc/issues/34))
- OIDC support for Okta, Keycloak, and generic providers ([Issue #33](https://github.com/risk-sentinel/sparc/issues/33), [Issue #35](https://github.com/risk-sentinel/sparc/issues/35))
- LDAP authentication with bind-and-search pattern
- RBAC system with 29 seeded roles and 20 permission keys
- Login page restructure with OSCAL overview ([Issue #90](https://github.com/risk-sentinel/sparc/issues/90), [Issue #102](https://github.com/risk-sentinel/sparc/issues/102))
- Fixed local login and admin password reset flow ([Issue #91](https://github.com/risk-sentinel/sparc/issues/91))
- [PR #73](https://github.com/risk-sentinel/sparc/pull/73), [PR #104](https://github.com/risk-sentinel/sparc/pull/104), [PR #105](https://github.com/risk-sentinel/sparc/pull/105)

## v2.0.1 (2026-03-06)

- Dark mode fixes for consistent theming ([Issue #47](https://github.com/risk-sentinel/sparc/issues/47))
- Bug fixes for SSP viewing and inline editing ([Issue #41](https://github.com/risk-sentinel/sparc/issues/41), [Issue #42](https://github.com/risk-sentinel/sparc/issues/42))

## v2.0.0 -- OSCAL Full Schema (2026-03-06)

### UI & Framework
- Bootstrap 5.3 adoption for modern responsive layout ([Issue #51](https://github.com/risk-sentinel/sparc/issues/51))
- Interactive heat maps for control status visualization ([Issue #81](https://github.com/risk-sentinel/sparc/issues/81))
- Dashboard aggregate heatmap across all documents ([Issue #83](https://github.com/risk-sentinel/sparc/issues/83))

### OSCAL Compliance
- Full OSCAL schema uplift for all artifact types ([Issue #58](https://github.com/risk-sentinel/sparc/issues/58))
- OSCAL schema validation against official NIST schemas ([Issue #45](https://github.com/risk-sentinel/sparc/issues/45))
- OSCAL metadata management and inheritance ([Issue #52](https://github.com/risk-sentinel/sparc/issues/52))
- Vendor-neutral data mapping schema ([Issue #54](https://github.com/risk-sentinel/sparc/issues/54))

### Document Types
- SSP wizard, enrichment, and enhanced export ([Issue #30](https://github.com/risk-sentinel/sparc/issues/30))
- SAR creation, enrichment, and wizard ([Issue #32](https://github.com/risk-sentinel/sparc/issues/32))
- SAP creation ([Issue #28](https://github.com/risk-sentinel/sparc/issues/28))
- POA&M import and management ([Issue #27](https://github.com/risk-sentinel/sparc/issues/27), [Issue #29](https://github.com/risk-sentinel/sparc/issues/29))
- Component Definition (CDEF) support

### Other
- Evidence and attestation collection ([Issue #31](https://github.com/risk-sentinel/sparc/issues/31))
- Authorization boundary orchestration with RMF roles ([Issue #46](https://github.com/risk-sentinel/sparc/issues/46))
- Document duplication ([Issue #56](https://github.com/risk-sentinel/sparc/issues/56))
- Control catalog and family CRUD ([Issue #48](https://github.com/risk-sentinel/sparc/issues/48), [Issue #49](https://github.com/risk-sentinel/sparc/issues/49))
