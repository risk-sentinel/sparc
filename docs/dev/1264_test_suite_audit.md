<!-- markdownlint-disable MD013 -->
# #1264 — test and workflow audit: what repeats, what it costs, and what could change

An inventory of the test layers and workflows, the work done more than once, and a proposal for each overlap.
Measured 16–18 Nov 2026 against `main` at fab3e26a.

**Status of each part:**

| Part of #1264 | Here |
|---|---|
| Expensive fixtures loaded repeatedly | Measured; a fix is built on the `spec-speed` branch |
| Specs that could share setup | Measured; seven files changed on the branch, the rest listed as proposals |
| Slowest examples and files | Measured locally and on CI's runners |
| The same behaviour asserted at several layers | Inventoried by reading the suites; about a quarter compared example by example |
| Workflows that overlap | Inventoried with durations; a proposal per overlap; **nothing changed** |
| The staged pipeline | Not attempted. The differences between the stage table and `main` are listed |

Nothing in this document changes a workflow's gating or removes a check without the owner's approval. Where the
`spec-speed` branch already changes something, that is stated, with the measurement behind it. Items marked
"inferred" were reasoned from the code or the timings and not confirmed.

## Summary

- **A pull request waits on RSpec, and on nothing else.** The `test` job's median is 51.7 minutes; the next
  longest chain, Security, is 9.7. The API and UI-smoke suites do not run on pull requests at all.
- **RSpec's time was concentrated.** In a full local run of 8,949 examples, 106 examples took 44.2 of the 55.7
  minutes, in 13 files. About a hundred examples each imported the whole NIST Rev 5 catalog.
- **One file made runs vary by ten minutes.** `spec/integration/odp_worksheets_plug_and_play_spec.rb` took 20
  seconds or 13 minutes. The cause was a query in the application, now found and fixed on the branch.
- **The three test layers duplicate very little.** One verbatim duplicate was found in 733 spec files. The
  same-named API and request specs check the same claims at different levels of the stack.
- **The workflows repeat small things, off the critical path.** hdf is built three times per PR, Trivy and Grype
  scan the same inputs in two workflows with two suppression lists, and the app image is built inside a scan job.
  Fixing these improves attribution and saves a minute or two on the Security path; it does not shorten a PR.

## RSpec: where the time went

### Before and after

The same GitHub-hosted runners, 18 Nov 2026. "Before" is `main`; each later row adds to the one above.

| Change | `test` check | Note |
|---|---|---|
| `main`, one process | 62.0 min | One run that day; the 12-run median is 51.7 |
| One descendant selector on the SSP page replaced | 49.2 min | The selector alone cost over two minutes |
| Four shards (separate jobs), coverage merged | 21.5 min | See "The parallel run" below: #1256 proposes a different shape |
| Each NIST catalog imported once per run | 10.6 min | |
| hdf binary and catalog rows cached between runs | 9.3 min | Cold caches |
| The parameter-service query fixed; seven spec files sharing setup | 8.2 min | 9.2 on the next run |

Without sharding, on one machine (not a GitHub runner), the full suite went from 48–56 minutes to 17.6.
Coverage is 86.44% after and 86.77% before; the difference is in two rake files whose measured coverage depends
on which spec loads them first (inferred), and no application file lost coverage. The example count went from
8,949 to 8,938: fifteen examples were merged into others with every assertion kept, and four were added.

### The parallel run and #1256

#1256 proposes four processes inside the one `test` job with `parallel_tests`, and rules out a matrix of separate
jobs because that repeats setup per job and needs a coverage-collation job before Sonar. The branch does the
latter. Both costs are real and were measured: each shard spends about 1.5 minutes on setup, and a joining job
(about 20 seconds) merges coverage and applies the 70% floor. The result was a `test` check of 8–9 minutes against
#1256's estimate of 12–15. The catalog and spec changes below do not depend on which shape is chosen.

### Findings, with what was done about each

| Finding | Evidence | Status |
|---|---|---|
| About 100 examples each import the full Rev 5 catalog (12–15 s, about 21,000 SQL statements) | 13 files held 44 of 55.7 minutes | **Done on the branch.** `spec/support/imported_catalogs.rb`: the importer runs once per fixture per run and its rows are put back inside each example's transaction. `spec/lib/imported_catalogs_spec.rb` compares the rows put back with the rows imported, table by table |
| One Nokogiri selector took 126–166 s | `ssp_wizard_statements_spec.rb:77`, `form[action=…] [data-testid=…]` on a 14 MB page | **Done on the branch.** Find the form, then search inside it |
| A worksheet upload ran a quadratic DELETE per entry when the planner's estimates were low | `BaselineParameterService#upsert_parameter_field`; 249 ms per entry measured; the file took 12 min 54 s in the reproduced state and 35.6 s after | **Done on the branch**, in the application. Also: the catalog walked once per request instead of once per entry, and the payload applied in one transaction |
| Examples that build the same state to make one read-only check each | See the table below | **Done on the branch** for seven files; the rest are proposals |
| `test` printed nothing until it finished | Dots with no newline | **Done on the branch.** `--format documentation` |
| Two specs commit a catalog and remove it with `destroy` | `oscal_e2e_pipeline_spec.rb`, `odp_worksheets_plug_and_play_spec.rb`; a refused destroy is silent and leaves the catalog for every later spec | **Done on the branch.** `destroy!` |
| "Every write lands" checked counters only | `odp_worksheets_plug_and_play_spec.rb` | **Done on the branch.** Every stored value is read back |

Setup shared on the branch, with no assertion removed:

| File | Before | Now |
|---|---|---|
| `spec/seeds/nist_rev4_rev5_mapping_seed_spec.rb` | The 921-entry seed loaded 9 times | 3 loads |
| `spec/requests/reference_estate_isolation_spec.rb` | The estate rebuilt for each of 18 read-only requests | 8 builds |
| `spec/integration/oscal_e2e_pipeline_spec.rb` | The full catalog exported 7 times in Stage 1 | Once |
| `spec/services/catalog_import_service_spec.rb` | Four examples ran a full import only to read it or to set up a second | The first import comes from the kept copy; the import under test still runs |
| `spec/services/catalog_import_format_parity_spec.rb` | Three full imports | The JSON side from the kept copy |
| `spec/integration/ssp_item_fields_1312_spec.rb` | One example rendered the same page twice | Once |
| `spec/integration/odp_worksheets_plug_and_play_spec.rb` | The 10 MB catalog re-parsed for every example | Once per file |

### Proposals not acted on

These change what a test covers or how the product behaves, so they are the owner's to decide.

| Where | What it does | Why it proves little | Proposal |
|---|---|---|---|
| `spec/services/catalog_import_service_spec.rb`, "cross-format canonical ID consistency" | Imports Rev 5 as JSON, then as YAML, and compares control ids | Both imports resolve to the same catalog row by name, so the ids compared are the same rows | **Drop**; `catalog_import_format_parity_spec.rb` tests the claim with isolated imports |
| `spec/jobs/catalog_import_lands_draft_spec.rb:63` | Full Rev 5 import through the job, asserts no `missing_priority` or `missing_baseline` warning | `CatalogImportValidationService` no longer has those checks, so it passes for any catalog | **Keep the claim, on `basic-catalog.yaml`** |
| `spec/services/catalog_import_service_spec.rb`, "re-import with existing catalog" | `ControlCatalog.where(id: catalog.id).count == 1` | Always true | **Keep**, asserting `ControlCatalog.count` and `CatalogControl.count` are unchanged |
| `spec/integration/nist_moderate_end_to_end_spec.rb:74` | Validates a fixture against the OSCAL schema | Needs no database, but the group's `let!` loads two catalogs first: 24 s on a CI runner when it is first in its shard | **Keep**, outside the group |
| `spec/requests/api/v1/users_spec.rb` | Four examples repeated verbatim (`:50`=`:208`, `:58`=`:216`, `:68`=`:226`, `:97`=`:254`) | The only verbatim duplicate found in 733 spec files | **Drop** one copy of each |

Setup still repeated:

| File | What repeats | Could be |
|---|---|---|
| `nist_moderate_end_to_end_spec.rb`, `ssp_item_fields_1312_spec.rb`, `ssp_wizard_statements_spec.rb`, `ssp_control_edit_part_responses_spec.rb` | The tailored MODERATE profile (287 controls, 584 values), its SSP, and often the whole SSP page: about 27 SSP builds and 13 renders. Only the first file needs the full baseline by nature; the others assert on ac-1, ac-2 and ac-2.1 | Share one render where examples read the same unchanged page; or give the last three a profile trimmed to those controls. A row-snapshot of the built profile and SSP was tried and saved only about 20 s, so it was not kept |
| `oscal_e2e_pipeline_spec.rb` | Baselines built about 17 times; 19 CDEFs imported 3 times | Once each |
| `spec/services/reference_estate_builder_spec.rb` | About 25 examples each build to read one result | 4 or 5 builds |
| `multi_catalog_profile_1234_spec.rb:139` | The full 287-control profile imported and exported to assert one import and its href | A small single-import profile |

### The slowest examples on CI's runners

From the timestamps of one four-shard run (18 Nov). A line's time includes any group setup that ran before it.
84 examples took 3 seconds or more, 12.8 of about 22 minutes of test time. A CI runner takes about twice as long
as the development machine on these.

| Seconds | Example |
|---|---|
| 42 | `catalog_import_service_spec.rb`: "updates existing catalog without duplicating" |
| 34 | `catalog_import_format_parity_spec.rb`: "imports identical controls, parts, guidance and params from all three" |
| 33 | "exports the baseline with exactly the consumer's values and nothing invented" |
| 25 | HIGH baseline profile "selects its with-ids, in the order listed" |
| 24 | `nist_moderate_end_to_end_spec.rb`: "uses a fixture the OSCAL 1.2.3 profile schema accepts" |
| 21 | `oscal_e2e_pipeline_spec.rb`: Stage 3 setup |
| 21 | `odp_worksheets_plug_and_play_spec.rb`: the catalog worksheet |
| 21 | `catalog_import_service_spec.rb`: "stores oscal_xml for XML imports" |
| 20 | `ssp_wizard_statements_spec.rb`: "gives every control its statement parts to answer" |
| 19 | "requires one response per leaf part of each control the profile selects" |

### The 14 MB SSP page

`SspDocumentsController#show` renders a MODERATE SSP as about 14 MB of HTML. Measured on a saved copy:

| What | Size |
|---|---|
| 287 hidden per-control edit forms (about 11,400 inputs) | 8.7 MB, 62% |
| `shared/baseline_control_detail` and guidance, rendered in the view section and again in each edit form | about 1.8 MB of repetition |
| The whole page gzipped | 1.08 MB |

No `Rack::Deflater` was found in the app; a proxy in front of it may compress (not checked). About 13 examples
request this page and parse all of it to check one or two controls.

In the code: (1) load a control's edit form when it is opened, with a lazy Turbo Frame and a per-control action,
which removes most of the page; (2) render the baseline detail once per control; (3) offer the page by family;
(4) turn on response compression unless the proxy already does it.

In the tests: with (1) in place, an example that checks a control's form requests that one frame. Until then,
examples reading the same unchanged page can share a request, and a lookup should find the control's element
first and search inside it. One example asserting the page's size would keep it from growing back unnoticed.

### Left in the parameter service

- Each entry still issues about five statements, so the HIGH worksheet is about 4,000. Batching the writes would
  cut that to a handful; it means rewriting the per-entry alias, validation and counter logic.
- `load_current_values` reads all of the profile's parameter fields once per selection whose choice references a
  parameter.

## The same behaviour asserted at several layers

Read from the code; no tests were run for this section. Counts are regex counts of `it` / `def test_`, so looped
and parametrized examples are undercounted. Items marked "inferred" were not confirmed.

### The layers and when each runs

| Layer | Size | When it runs |
|---|---|---|
| RSpec, `spec/` | 733 spec files | Every PR, push to `main`, manual dispatch (`ci.yml`). Skipped on PRs that touch no app code |
| `tests/api/` (pytest + httpx) | 63 `test_*.py` modules, 866 test functions, plus 7 shared `_*_contract.py` mixins. `test_contract_sweep.py` parametrizes over 369 endpoints | Only on a `v*` tag push, in `build-sign-publish.yml`'s `verify` job, against the built amd64 production image. Never on a PR or on `main` |
| `tests/ui-smoke/` (pytest-playwright) | 96 modules, 317 test functions, 163 skip sites in 71 files | The same `verify` job on a tag push (Chromium), and `ui-smoke.yml` (Chromium and Firefox) on manual dispatch or after a "Deploy" workflow, with `continue-on-error: true` |
| `tests/regression_plan.md` | 239 lines | Not executable: a manual checklist of upload/export round trips |

Worth knowing about the triggers:

- On a PR the two Python suites are only linted (`python_lint`) and inventoried (`api_contract` checks that every
  `/api/v1` route has a doc page, a Postman entry and a pytest module). That is presence, not execution.
- No workflow named "Deploy" exists in this repository, so `ui-smoke.yml`'s `workflow_run` trigger cannot fire from
  here (inferred). Firefox therefore runs only on manual dispatch.
- `tests/api/README.md` says "CI integration: there is none"; the `verify` job does run the suite. `ui-smoke.yml:4`
  cites an `api-tests.yml` that does not exist.
- Three posture-gated ui-smoke modules appear to run in no workflow (inferred): `test_fido2_virtual_authenticator.py`,
  `test_piv_mtls.py`, `test_oidc_idp_redirect.py`. `bin/smoke-prep` exports none of the `SPARC_SMOKE_*` posture
  variables and no workflow sets them, so they report "UNPROVEN" rather than run.
- `spec/system/` (9 files, 23 examples) is the only browser coverage on a PR.

### Coverage by area (files / examples)

Files classified by filename, first match wins: approximate. 101 files matched no area.

| Area | models | services | API requests | web requests | integration | system | other RSpec | tests/api | ui-smoke |
|---|---|---|---|---|---|---|---|---|---|
| SSP | 9/77 | 23/203 | 4/84 | 13/126 | 4/26 | 1/1 | 4/22 | 4/63 | 5/15 |
| SAR | 6/68 | 6/64 | 4/68 | 8/78 | 0 | 0 | 0 | 4/54 | 2/3 |
| SAP | 4/43 | 5/26 | 1/26 | 3/29 | 0 | 0 | 0 | 1/16 | 1/1 |
| POA&M / risks | 6/44 | 3/41 | 5/47 | 12/102 | 1/2 | 0 | 1/5 | 4/52 | 3/5 |
| CDEF | 8/105 | 25/294 | 8/115 | 18/224 | 0 | 0 | 9/82 | 2/63 | 8/17 |
| Profiles / baselines / parameters | 1/11 | 13/141 | 5/61 | 7/84 | 5/39 | 0 | 9/86 | 3/45 | 9/30 |
| Catalogs / controls / mappings / KSI | 17/241 | 20/285 | 11/206 | 14/137 | 2/19 | 0 | 20/178 | 7/107 | 7/19 |
| Boundaries / orgs / memberships | 13/146 | 8/119 | 8/99 | 16/192 | 1/10 | 1/2 | 2/11 | 6/90 | 12/43 |
| Evidence / artifacts / attestations | 7/120 | 7/67 | 6/117 | 7/77 | 0 | 0 | 3/34 | 4/83 | 3/18 |
| HDF / scans / converters | 5/54 | 11/167 | 7/79 | 2/33 | 0 | 0 | 6/36 | 7/84 | 1/4 |
| OSCAL export / validation | 6/86 | 19/235 | 4/42 | 3/42 | 2/68 | 0 | 11/93 | 1/3 + mixins | 3/6 |
| API tokens / service accounts | 2/35 | 0 | 4/56 | 3/40 | 0 | 1/2 | 3/30 | 3/34 | 2/4 |
| Authentication | 10/129 | 6/86 | 5/52 | 19/183 | 0 | 3/12 | 7/53 | 2/10 | 7/20 |
| Authorization / users / roles / IdP | 8/108 | 9/120 | 8/89 | 10/110 | 0 | 2/2 | 12/129 | 8/110 | 6/25 |
| Approval / review | 0 | 1/10 | 1/6 | 3/19 | 0 | 0 | 1/10 | via mixin | 1/5 |
| Import parsers | 1/1 | 2/27 | 2/24 | 0 | 1/2 | 0 | 2/22 | via mixin | 0 |
| UI shell / cross-cutting contract | 1/10 | 3/35 | 7/49 | 17/118 | 0 | 1/4 | 8/81 | 7/52 | 25/99 |

The structural fact behind most of the overlap: nearly every `tests/api/test_X.py` has a same-named
`spec/requests/api/v1/X_spec.rb` with a similar example count (cdef_documents 46 and 48, ssp_documents 29 and 24,
users 25 and 20, api_tokens 14 and 12, translations 20 and 20, organizations 16 and 16).

### Specific overlaps

Three kinds: **(a)** the same claim at the same level of the stack; **(b)** the same claim, where the second layer
proves something the first cannot; **(c)** looks alike, different claim.

For every (b) against `tests/api`: the request spec runs in-process (test environment, factories, `SparcConfig`
often stubbed). `tests/api` runs over real HTTP against the production image (built without dev and test gems, real
Puma, seeded data, real token authentication, rack-attack live).

**(a) True duplicates.** One found: `spec/requests/api/v1/users_spec.rb` repeats four of its own examples verbatim:
`:50` = `:208`, `:58` = `:216`, `:68` = `:226` (15 identical lines), `:97` = `:254` (its comment at `:251` calls it
"the sibling copy"). A body-hash scan of all 733 spec files found no other verbatim duplicate of four or more lines
with the same subject.

**(b) Same claim, different stack.** Compared example by example:

| Behaviour | Request spec | tests/api | Only RSpec also checks |
|---|---|---|---|
| API tokens: issue, expiry, unaccepted field, anonymous, non-admin, revoke | `api/v1/api_tokens_spec.rb:25, 53, 63, 88, 81, 71, 117, 131` | `test_api_tokens.py:54, 84, 98, 115, 126, 135, 152, 180` | RSpec proves "authenticates" with a model call; tests/api with a real request. tests/api accepts 401 or 403 where RSpec pins 403 |
| SSP documents: 401, list, show, 404, create, 403, update, delete, export, update_fields, convert, populate | `api/v1/ssp_documents_spec.rb:18-315` (14 examples) | `test_ssp_documents.py:271-500`, `_populate_from_profile.py:65` | Audit events `:122, :168, :199`; status filter `:44`; soft-delete then 404 `:210` |
| SSP change baseline (#1330), API half | `ssp_change_baseline_1330_spec.rb:156, 166, 184, 192` | `test_ssp_documents.py:181, 196, 224, 232` | |
| Pagination on `/api/v1/cdef_documents` (`items`, `per_page`, clamp, fallback to 25) | `api/v1/cdef_documents_spec.rb:40, 47, 54, 60` | `test_edge_cases.py:50, 62, 68, 75` | The closest to (a): identical endpoint, parameters and expected numbers |
| OSCAL export contract for ssp/sap/sar/poam (8 claims) | `api/v1/oscal_document_export_1181_spec.rb:94-237` | `_oscal_export_contract.py:57-144` | ETag changes with a child record `:199`; per-format ETags `:214`; boundary-scoped read `:245-259` |
| CDEF export formats | `api/v1/cdef_export_formats_spec.rb:31, 119, 126, 135, 143` | `test_cdef_documents.py:901, 920, 933, 945` | |
| Baseline parameters (8 claims) | `api/v1/baseline_parameters_spec.rb:32-313` | `test_baseline_parameters.py:72-394` | |
| Sessions bridge | `api/v1/sessions_spec.rb:20, 49, 61, 82` | `test_sessions.py:29, 61, 67, 37` | The whole ui-smoke suite also depends on it (`authed_page`) |
| Authorization boundaries: CRUD, org link, bulk delete | `api/v1/authorization_boundaries_spec.rb:15-236` | `test_authorization_boundaries.py:80-370`, `_bulk_destroy.py:43, 62, 69` | |
| Evidence (11 claims, including ELF upload refused and server-stamped provenance) | `api/v1/evidences_spec.rb:40-527` | `test_evidences.py:106-361` | |
| Review workflow | `api/v1/document_approval_spec.rb:17, 23, 30, 44` | `_review_workflow.py:66, 92`, `test_cdef_documents.py:424` | ui-smoke `test_review_queue.py:55, 108` adds the browser half |
| List envelope | `api/v1/list_envelope_contract_spec.rb:40-98` (5 endpoints) | `test_contract_sweep.py:160` (every collection GET) | `meta.count == data.size` |
| Public Controls posture (#974) | `public_controls_access_974_spec.rb:66-221` | ui-smoke `test_public_controls_974.py:123-174` | ui-smoke proves it on the shipped image in both postures |
| CSP report collector | `security/csp_reports_spec.rb:24, 52` | ui-smoke `test_csp_reporting.py:47, 59` | Neither uses a browser |
| Nav inventory | `nav_inventory_spec.rb:62, 88` | ui-smoke `test_nav_inventory.py:180, 193` | Both read the same `nav_inventory.json` |
| Login-page accessibility | `system/accessibility_spec.rb:13` | ui-smoke `test_accessibility.py:29` | Both run axe in Chrome; ui-smoke adds authenticated and show pages |

Two rules are asserted at four or five levels:

| Rule | Service / model | API request | Web request | tests/api | ui-smoke |
|---|---|---|---|---|---|
| Profile bulk edit (#1270) | `services/profile_control_bulk_edit_service_spec.rb:17-103` | `api/v1/profile_controls_bulk_1270_spec.rb:30-74` | `profile_control_bulk_edit_1270_spec.rb:111-156` | `test_profile_controls_bulk_1270.py:91-154` | `test_profile_priority_bulk_1270.py:91, 117, 135` |
| Token lifetime (#1176) | `models/api_token_lifetime_spec.rb:17-162` | `api/v1/token_lifetime_1176_spec.rb:40-218` | `admin/api_token_lifetime_1176_spec.rb:50-152` | `test_api_token_lifetime_1176.py:81-176` | `test_api_token_edit_limits_1233.py:36` |

**(c) Looks alike, different claims** (keep both):

- Boundary isolation on the SSP index: `ssp_documents_spec.rb:61` proves a scoped user sees their own and not
  another's; `test_edge_cases.py:179, 214` proves only the negative and accepts 200-filtered, 401 or 403.
- Endpoint list: `endpoint_coverage_spec.rb` pins the route list; `test_contract_sweep.py` uses the same file as
  input and asserts behaviour; `bin/api_inventory_check.rb` asserts docs exist. Three claims about one surface.
- Unknown-field refusal: `security/api_strict_params_coverage_spec.rb` is a static scan; `_crud_contract.py:315` and
  `test_contract_sweep.py:120` send a bad field and check nothing was written.
- Authorization: `security/controller_authorization_coverage_spec.rb` is structural (a guard is declared); the
  request specs and tests/api are behavioural.
- CSP `form-action`, session expiry, CDN integrity, HDF triage: the spec asserts the server's output, the ui-smoke
  module asserts what Chrome does with it.

### Within RSpec: one rule at several levels

| Rule | Model / service | API request | Web request | System |
|---|---|---|---|---|
| Service-account token must expire | `models/api_token_lifetime_spec.rb:17, 22` | `api/v1/token_lifetime_1176_spec.rb:40, 47` | `admin/api_token_lifetime_1176_spec.rb:50, 142` | |
| Renew keeps limits; reissue ends the old token | same `:81, 94, 146` | same `:90, 108` | same `:103, 112` | |
| Regenerate does not widen | same `:162` | same `:218` | same `:82` | |
| Empty CDEF cannot be submitted (#634) | `services/document_approval_service_spec.rb:31` | `api/v1/document_approval_spec.rb:44` | `document_approval_spec.rb:83` | |
| Submit, approve, reject | same `:14, 44, 87` | same `:17, 23` | same `:28, 34, 41` | |
| Profile bulk edit refusals | `services/profile_control_bulk_edit_service_spec.rb:87, 103` | `api/v1/profile_controls_bulk_1270_spec.rb:56, 64` | `profile_control_bulk_edit_1270_spec.rb:81, 144` | |
| SSP change-baseline refusals and delta | `services/ssp_baseline_change_spec.rb:45, 105, 122` | `ssp_change_baseline_1330_spec.rb:156, 175, 184` | same file `:79, 136` | |
| ATO decision-field formats | `models/ato_decision_fields_spec.rb:32, 38, 90` | `api/v1/ato_decision_fields_1154_spec.rb:44, 89` | `ato_decision_fields_web_1154_spec.rb:38` | `system/ato_decision_fields_1154_spec.rb:21, 39` |
| POA&M risk required fields | `models/poam_risk_validation_spec.rb:38, 83, 93` | `api/v1/poam_risks_spec.rb:47, 72, 82` | | |
| Executable upload refused | `controllers/concerns/file_uploadable_spec.rb:239, 277` | `api/v1/evidences_spec.rb:457` | `evidence_upload_policy_spec.rb:89, 96` | |

### Covered only off the PR path: must not be dropped

**Only in `tests/api` (release tags only):**

- Whole-surface sweeps over all 369 endpoints in `test_contract_sweep.py`: anonymous gets 401 (`:62`), unknown
  token gets 401 (`:81`), no 5xx to an authenticated caller (`:100`), no 2xx to an unrecognised body (`:120`), every
  refusal is a JSON `error` envelope (`:287`), no 2xx for an unresolvable id (`:324`). RSpec has per-resource 401
  examples and static scans, and nothing that walks the surface behaviourally.
- `?items=1` narrows every list endpoint (`:226`). RSpec proves narrowing for two endpoints.
- `?items=-5` and a page beyond the last (`test_edge_cases.py:56, 81`).
- Emoji, right-to-left and long-description round trips on document names (`test_edge_cases.py:121, 132, 143`).
- Everything that depends on the production image: boot without test gems, token authentication over HTTP, live
  throttling, `/up` not redirected to login, STIG ingest to OSCAL export end to end.
- Create and update confirmed by an independent read (`_crud_contract.py:149, 212`), for 23 resources.

**Only in ui-smoke:**

- CSP violations in a real browser: load and click, Turbo Drive navigation, and the sweep for inline handlers on
  every page. No spec listens for `securitypolicyviolation`.
- Chrome loading the SRI-hashed module; bfcache restore; keyboard activation; the hide class winning the cascade.
- Comboboxes and pickers, clipboard copy, the heat-map family filter.
- Every nav link opening by click; authenticated and show-page axe audits.
- Transport: `test_tls_verification.py`, `test_transport_posture_858.py`, `test_config_inference.py`.
- Firefox as a whole.

**Only in RSpec in these areas** (so the Python suites are no substitute): audit-event emission, positive
boundary-scoped visibility, ETag invalidation on a child change, and every model and service rule above.

### What was not examined

- Example-by-example comparison covers about 14 of the 63 `tests/api` and request-spec pairs. The other 49 or so
  (sar, sap, poam, catalogs, families, mappings, converters, HDF, KSI, roles, organizations, federation and others)
  are established by matching names and counts only.
- About 30 of the 96 ui-smoke modules were compared against specs.
- `spec/integration` against `tests/regression_plan.md` was not mapped.
- Which ui-smoke skips actually fire in the `verify` job is unknown.

## Workflow and job inventory

Workflows read from `main` at fab3e26a. Durations are medians of successful jobs from upstream runs, in minutes:

| Sample | Workflow | Runs | Dates (2026) |
|---|---|---|---|
| A | CI | 12 successful (10 PR, 2 push to `main`) | 16–18 Nov |
| B | Security Scanning | 12 successful; the scan jobs ran in 10 | 6–18 Nov |
| C | Build, Sign & Publish | 12 successful tag runs | 2 Oct–6 Nov |
| D | every other workflow | 10 successful each unless stated | given per row |

"Required" means a rule in `.github/required-checks.json`; "advisory" means listed in its `advisoryChecks`. A job
that is neither still blocks a merge when it fails, because the aggregator fails on any failed non-advisory check
(`required-passed.yml:174-187`). The branch ruleset itself could not be read. "Stage" is where the job would sit
in the staged design this issue describes.

### `ci.yml` (pull request, push to `main`, dispatch)

| Job | Path filter | What it proves | Status | Median (n) | Stage |
|---|---|---|---|---|---|
| `changes` | PR only | Computes the `app_code`, `yaml`, `python`, `api_contract` filters | neither | 0.16 (10) | 1 |
| `lint` | `app_code` | rubocop | required | 0.49 (12) | 1 |
| `yaml_lint` | `yaml` | yamllint | neither | 0.18 (11) | 1 |
| `python_lint` | `python` | ruff over `tests/api` and `tests/ui-smoke` | neither | 0.18 (10) | 1 |
| `api_contract` | `api_contract` | Every `/api/v1` route has a doc page, a Postman entry and a pytest module. Static: no database, does not run pytest | required | 0.35 (3) | 1 |
| `test` | `app_code` | The whole RSpec suite including Chrome system specs, on a fresh database; builds hdf; asserts the HDF pipeline specs did not skip; emits coverage | required | 51.68 (12), range 39.1–65.6 | 3 |
| `upgrade_path` | `app_code` | The last release's image builds a database on postgres:15, this code migrates it, no drift from `schema.rb` | advisory | 2.18 (12) | 3 |
| `sonar_scan` | none; `needs: test` | SonarCloud analysis with coverage | advisory | 1.26 (12) | 3, gate in 5 |

### `security.yml` (pull request, push to `main`, Mondays 06:00, dispatch)

| Job | What it proves (tool → input) | Status | Median (n) | Stage |
|---|---|---|---|---|
| `changes` | Path filter | neither | 0.15 (10) | 1 |
| `secrets_scan` | gitleaks → the whole git history | required | 0.27 (10) | 3 |
| `brakeman_scan` | brakeman → app | neither | 0.58 (10) | 3 |
| `codeql_scan` | CodeQL ruby → `app`, `lib`, `config`; SARIF kept as an artifact, not uploaded | neither | 1.12 (10) | 3 |
| `semgrep_scan` | semgrep; dispatch only | neither | no data (skipped 12 of 12) | 3 |
| `dependency_audit` | bundler-audit → `Gemfile.lock` | required | 0.30 (10) | 3 |
| `findings_freshness` | Review dates in `sparc-findings.yml` and `.trivyignore` have not lapsed | neither | 0.20 (12) | 5 |
| `importmap_audit` | `bin/importmap audit` → JS pins; never gates | neither | 0.24 (10) | 3 |
| `trivy_fs_scan` | trivy fs → repo, two passes | required | 0.47 (10) | 3 |
| `trivy_container_scan` | Builds the image; trivy image in four formats; Syft SBOM of the image | required | 3.46 (10), range 1.7–12.1 | 2 and 3 |
| `sbom_generation` | cdxgen → Ruby CycloneDX SBOM | neither | 0.90 (10) | 3 |
| `grype_sbom_scan` | grype → three SBOMs; then gates at critical | required | 2.13 (10) | 3, its gate in 5 |
| `license_inventory` | Licence policy over three SBOMs (warns only) | neither | 0.22 (10) | 3 or 4 |
| `normalize_hdf` | Converts all scan output to HDF; builds hdf; asserts the hdf pins | neither | 1.69 (10) | 4 |
| `bundle_results` | Summary and combined archive | neither | 0.52 (10) | 4 |
| `security_gate` | Applies amendments, `saf validate threshold` per scanner, CodeQL disposition pin; builds hdf | required | 1.39 (10) | 5 |
| `publish_for_sparc_iac` | `main` only: S3 sync and dispatch to sparc-iac | neither | 0.38 (2) | 4 |
| `pipeline_metrics` | Durations CSV and chart | neither | 0.37 (10) | 4 |

### `build-sign-publish.yml` (tags `v*`): all stage 6, none required

| Job | What it proves | Median (n=12) |
|---|---|---|
| `prepare` | Version format; whether the tag moves `latest` | 0.05 |
| `build-image` amd64 / arm64 | Native build per architecture | 3.60 / 3.34 |
| `verify` | The amd64 image serves; the API pytest suite and Chromium UI smoke run against it | 20.99, range 14.8–28.8 |
| `verify-arm64` | The arm64 image boots; native gems, jemalloc, hdf | 2.28 |
| `build-and-push` | Promotes the verified archives, behind `environment: production` | 2.66 |
| `sign-verify-attest` | cosign sign and verify; SBOM attest; Grype → VEX attest; builds hdf | 3.45 |
| `notify-consumers` | Files the pin-bump issue in sparc-iac | 0.08 |

### Smaller workflows

| Workflow / job | Trigger | What it proves | Status | Median (n) | Stage |
|---|---|---|---|---|---|
| `sbom-and-sca.yml` / `sbom` | every PR, push to `main`, daily 08:00; no path filter | Syft → source-tree SBOM | neither | 0.20 (10) | 3 |
| `sbom-and-sca.yml` / `sca` | same | grype → that SBOM; trivy fs → repo; fails at CRITICAL | neither | 1.72 (10) | 3, its gate in 5 |
| `sbom-and-sca.yml` / `emit` | not on PRs | SBOM to S3 | neither | 0.18 (3) | 4 |
| `sonarqube-hdf-emit.yml` / `emit` | push to `main`, Mondays 12:30 | Fetches SonarCloud issues → OHDF, validates, S3 | neither | 0.49 (10) | 4 |
| `compliance.yml` | PR, top-level paths | OSCAL metadata and CDEF validity | required | 0.18 (10) | 1 |
| `pr-checklist.yml` | PR opened, edited, synchronized | Every PR-body checkbox is ticked | required, always | 0.05 (10) | 1 |
| `validate-required-checks-sync.yml` | PR touching workflows or the JSON | JSON rules are a subset of the workflow filters | neither | 0.19 (10) | 1 |
| `required-passed.yml` | PR to `main` | Polls the Checks API every 15 s, cap 90 min | the branch gate | 42.65 (10), max 53.9 | reads 5 |
| `deviation-approval.yml` | PR paths, review events | No deviation is unapproved or self-approved | required | 0.24 (10) | 5 |
| `deviation-approve-command.yml` | issue comment | Records an admin's approval | neither | 0.33 (10) | separate |
| `publish-wiki.yml` | push to `main` on `wiki/**` | Wiki mirror moved | neither | 0.24 (10) | separate |
| `ubi9-prototype-validation.yml` | push to `experiment/742_ubi9_prototype`, dispatch | Builds the image, smoke, grype | neither | 3.71 (2, 17 Jul) | dormant |
| `ui-smoke.yml` | dispatch; `workflow_run` on "Deploy" | Playwright, Chromium and Firefox, against a deployed URL | neither | 1.31 (2, 31 May) | separate |

Also reporting on every PR, though not in `.github/workflows`: GitHub's CodeQL default setup (four Analyze jobs:
ruby, javascript-typescript, actions, python; 1.5 min wall-clock, 10 runs) and Dependabot.

### The critical path today

| Workflow | Chain | Sum of medians | Measured wall-clock |
|---|---|---|---|
| CI (PR) | `changes` 0.16 → `test` 51.68 → `sonar_scan` 1.26 | 53.1 | median 53.2 (10 PR runs), range 40.6–66.8 |
| Security (PR) | `changes` → `trivy_container_scan` 3.46 → `grype_sbom_scan` 2.13 → `normalize_hdf` 1.69 → `security_gate` 1.39 | 8.8 | median 9.7 (8 runs) |
| Build, Sign & Publish | `build-image` 3.6 → `verify` 21.0 → approval → `build-and-push` 2.66 → `sign-verify-attest` 3.45 | 30.8 of work | median 53.4 with the approval wait |
| SBOM + SCA | `sbom` → `sca` | 1.9 | median 2.0 |

A pull request's readiness is set by `test`. Nothing in Security or SBOM + SCA is within 40 minutes of it. Inside
`test`, the "Run tests" step is 48.7 minutes (max 62.4) and the HDF re-assert 1.3. In release `verify`, UI smoke is
16.6 minutes (79% of the job) and the API suite 1.8.

### Repeated work, and a proposal for each

Nothing below has been changed. The owner approves before any workflow or required check changes.

| # | Repeated work | Evidence | Cost per PR | Proposal | What must not be lost |
|---|---|---|---|---|---|
| 1 | The app image is built inside a scan job | `security.yml:497-505`, step median 2.0 min, range 19–622 s | On Security's critical path; cold-cache runs set that workflow's time | **Merge** into a stage-2 build job; scans consume the artifact | The Dockerfile floors as build checks, the #1080 and #873 assertions, all four Trivy formats, the Syft SBOM. Wall-clock will not improve (upload and reload costs about as much); the gain is that a build failure stops reading as six scan failures |
| 2 | Release builds do not share the PR build's cache | `build-sign-publish.yml:242-254` uses `scope=<slug>`; the PR build uses the default scope (inferred from the keys) | Tags only | **Merge** the scopes | The native arm64 build and `verify-arm64` |
| 3 | hdf CLI built from source three times per PR | `ci.yml:282-306` (42 s), `security.yml:1217-1250` (41 s), `security.yml:1838-1859` (42 s); a fourth in the Dockerfile; a fifth on tags | About 2.1 min of runner time, 1.4 of it serial on the Security path | **Merge**: build once, share by cache keyed on the Dockerfile pins, or copy it out of the stage-2 image | The x/text floor, the Go fix line, the version check, and the pin assertion (today `security_gate` does not assert) |
| 4 | SAF CLI installed twice | `security.yml:1168-1172`, `1990-1994`, about 20 s each, serial | 20 s on the Security path | **Merge** with 3 | The `@mitre/saf@1.7.0` pin and the soaked install |
| 5 | Trivy fs run in two workflows on the same input | `security.yml:454, 468` and `sca-scan.yml:87-97` (14 s) | Parallel, off the critical path | **Drop** the pass in `sca-scan.yml`, or feed it the other's output | `sca-scan.yml` is vendored for cross-repo parity, so dropping diverges from its source; its daily 08:00 run is the only daily dependency scan |
| 6 | Grype over the source dependency set in two workflows, with two suppression lists and two CRITICAL gates | `security.yml:974-1000`, `sca-scan.yml:281-285`; database load paid twice (95 s and 77 s) | About 1.9 min for `sbom-and-sca`, parallel; it runs on docs-only PRs too (no path filter) | **Keep both scans, merge the gates** into stage 5 with one register | The Syft source SBOM goes to S3 for Dependency-Track; the other SBOMs feed HDF and the licence inventory. Keep the daily schedule |
| 7 | Grype re-scans inside its own enforce step | `security.yml:974-1000`, 6 s | Seconds | **Drop**; read the JSON already written | Same result |
| 8 | CodeQL analyses Ruby twice | `security.yml:242-262` (1.12 min) and the default setup's "Analyze (ruby)" | Parallel | **Keep** `codeql_scan`; the owner decides on the default setup | Dropping `codeql_scan` loses the HDF threshold and the #1186 pin. Dropping the default setup loses JS, Actions and Python analysis and Code Scanning alerts |
| 9 | Sonar analysis and Sonar fetch are ordered wrongly on `main` | Both fire on the same push; the fetch finishes in 0.5 min, the analysis lands after `test` (inferred from triggers and durations) | None, but the fetch exports the previous commit's analysis | **Keep both**; trigger the fetch after the analysis | The weekly schedule (#1027) and fork safety. The headers at `sonarqube-hdf-emit.yml:8-10` still describe Automatic Analysis |
| 10 | The HDF pipeline spec runs twice in `test` | `ci.yml:320-333`, median 78 s | 1.3 min on the CI critical path | **Merge**: assert from the main run's output | The assertion that the specs did not skip and that `hdf` is on PATH |
| 11 | Path filters computed three times | `ci.yml:22-70`, `security.yml:104-136`, and the aggregator's own globs | 0.15 min each; every job waits on one | **Merge** into one preflight job | Identical glob sets; move `required-checks.json`, `required-passed.yml` and the sync validator in the same PR |
| 12 | Checkout, setup-ruby, bundle in eight jobs | 4–8 s cache hits | About 2.5 min of runner time, all parallel | **Keep** | Merging jobs to save it would serialise parallel work |
| 13 | Two Postgres services | `ci.yml:196-204` (unpinned) and `397-408` (`postgres:15`) | Parallel | **Keep** | They differ on purpose |
| 14 | `test`, `api_contract`, `upgrade_path` | They do not build or boot the same thing | — | **Keep all three** | Each proves a different thing |
| 15 | bundler-audit and Grype; gitleaks and Trivy secrets; Trivy SBOM and Syft SBOM | Different databases, scopes or consumers | — | **Keep** | |
| 16 | `ui-smoke.yml` beside release `verify` | Its "Deploy" trigger names a workflow that does not exist here; last ran 31 May | None | The owner decides | It is the only Firefox run and the only axe-baseline capture |
| 17 | `ubi9-prototype-validation.yml` | The Dockerfile on `main` is already UBI; no `experiment/*` branch found; last ran 17 Jul | None | **Drop**, with approval | Its grype-on-image scan is covered by `grype_sbom_scan` |
| 18 | `pipeline_metrics` runs before CI finishes | `security.yml:2468` queries completed runs about 10 minutes into a PR (inferred) | None | **Keep, move** to after CI | Otherwise the recorded totals omit `test`, which matters for before-and-after numbers |
| 19 | `Required Checks Passed` holds a runner while it polls | Median 42.65 min per PR event | Runner minutes, not wall-clock | **Keep** | The staged design could replace polling with a final job that `needs` the threshold stage |

### Where this issue's stage table does not match `main`

1. **"hdf pin checks" in stage 1.** There is no such job. The assertion is one line inside `normalize_hdf`
   (`security.yml:1231`).
2. **"again in `ubi9-prototype-validation.yml`".** That workflow is dormant. The real second and third builds are
   `build-image` (amd64, arm64) in `build-sign-publish.yml`.
3. **Stage 6 omits** `prepare`, `build-image` and `verify-arm64`. The release builds its own image and `verify`
   tests that build, so "build once" still means a tag-time build unless images are promoted from `main`.
4. **`sbom-and-sca` is a workflow of three jobs**, and its `sca` job carries its own pass/fail gate. So does
   `grype_sbom_scan`, which is a required check. Both break "only threshold jobs decide" and neither is listed as a
   threshold to move.
5. **`api_contract` in stage 3.** It is a static inventory check with no database and no image; it fits Preflight.
6. **The Sonar scan in stage 3** `needs: test` for coverage, so it is serial after `test`, not a peer.
7. **The Sonar fetch in stage 4** never runs on PRs.
8. **Jobs missing from the table:** `pipeline_metrics`, all of `ui-smoke.yml`, and GitHub's CodeQL default setup.
9. **"`Required Checks Passed` reads this stage."** Today it reads every check on the commit.
10. **`TIMEOUT_MIN`.** `test` (75) plus `sonar_scan` (15) is 90 as stated, but `changes` (timeout 10) precedes
    `test`, so the worst-case chain is already 100 against a cap of 90.
11. **`compliance.yml`, `validate-required-checks-sync.yml` and `deviation-approval.yml` use top-level `paths:`,**
    so they report no check when unmatched. Under one `pipeline.yml` they need job-level filters.

Not verified: the branch ruleset, the CodeQL default-setup configuration, and which Trivy scanners the vendored
`sca` job runs by default.
