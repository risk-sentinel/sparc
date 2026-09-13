# #966 — SonarCloud triage: what was fixed, and what needs a console decision

Measured from the SonarCloud API on 2026-09-12, not the UI issue list (UI totals
include resolved findings and read far larger).

**Starting state:** 276 open issues · Security **E** · Reliability **C** ·
Maintainability A · 0 security hotspots.

Sonar sets a rating from the **worst** open finding, which is why the ladder
below is short: two Blockers alone held Security at E.

---

## Fixed in code

| Findings | Rule | What changed |
|---|---|---|
| 2 **Blocker** | `githubactions:S8482` | Grype installed from a pinned release asset with its published checksum verified, instead of piping `install.sh` from `main` into a shell |
| 13 | `*:S6506` | `--proto '=https' --tlsv1.2` on every download, so a redirect cannot downgrade the transport |
| 1 | `shell:S6506` | `scripts/trivy-scan.sh` was the same `curl \| sh` shape — now a pinned, checksum-verified release |
| 4 | `S8544`/`S8543`/`S6505` | semgrep, pyyaml, cdxgen and js-yaml pinned to exact versions; `--ignore-scripts` on the npm install |
| 1 | `docker:S8547` | `bundle config set --local frozen true` stated at the call site |
| 7 | various | **Deleted with `Dockerfile_debian`** — 3 clear-text APT (`docker:S5332`) and 4 pinning findings, in an image nobody shipped |

Every install sequence was run locally before committing. Two were wrong on the
first attempt and would have failed in CI: Trivy publishes Darwin as **macOS**
with `64bit`/`ARM64` architectures, not uname's spelling.

---

## Needs a decision in the SonarCloud console

NOSONAR comments do **not** work for the Web/HTML analyzer — proven in #966: a
comment shipped in #918 is still OPEN, while JS and Ruby NOSONAR are honoured.
These must be resolved in the UI.

### 1. `rubydre:S7875` — disable in the quality profile

203 instances; **192 already Won't Fix**, 3 False Positive, 8 open. The rule is
named for root-route definitions but fires on the documented Rails `member do` /
`collection do` shorthand (`post :analyze`). Marking 8 more repeats work already
done 192 times.

### 2. ui-smoke dependency findings — False Positive

`githubactions:S8541` ×3, `S8544` ×3 on `.github/workflows/ui-smoke.yml`.

`uv sync --locked` already refuses to deviate from `uv.lock`, which pins **29
packages with 260 sha256 hashes**. The rule wants `--no-build`; **it cannot be
used here** — tested, and it fails on `sparc-ui-smoke` itself, the editable local
project, which has no binary distribution by definition:

```
error: Distribution `sparc-ui-smoke==0.1.0 @ editable+.` can't be installed
because it is marked as `--no-build` but has no binary distribution
```

Forcing the flag would break the job to satisfy a rule the lock already satisfies.

### 3. `githubactions:S6505` on `sonarqube-hdf.yml:155` — Won't Fix

`@mitre/saf@${SAF_VER}` is already an **exact** pin (`1.6.0`). The finding is
`npx --yes` running lifecycle scripts at all; suppressing those risks breaking
the CLI's own postinstall. It is also the fallback path — hdf-cli is primary.

### 4. The five `Web:*` "bugs" — False Positive

All five have keyboard equivalents already; the analyzer looks for `onKeyDown` /
`onKeyUp` **attributes**, which the CSP forbids us from using (no inline
handlers), and cannot see Stimulus delegation.

| Finding | Why it is wrong |
|---|---|
| `_heatmap.html.erb:115` | `<a role="button" tabindex="0">`, activated by the delegated `handleKeydown` listener |
| `_heatmap.html.erb:167` | Same delegation — and the file carries a comment warning **not** to add `keydown` here, because both paths would fire and toggle the filter straight back off |
| `ssp_documents/show.html.erb:123` | **Already has** `keydown.enter` and `keydown.space` data-actions, with a comment citing this exact rule |
| `profile_documents/show.html.erb:150,151` | The `<li>` fragments are built in a `capture` block and rendered inside `<ul class="dropdown-menu">` by `shared/_oscal_export_dropdown`. They are within a container at runtime; the analyzer reads one file in isolation |

---

## Handled by exclusion, in version control

`sonar.exclusions` now lives in `.github/workflows/ci.yml` rather than UI
settings nobody can review:

| Path | Why |
|---|---|
| `lib/oscal_xsd_schemas/**` | NIST's vendored XSDs — all 49 `xml:S1135` TODOs and 14 `xml:S125`. Editing them breaks OSCAL validation and detaches us from upstream |
| `db/migrate_archive/**` | Archived Rails-generated migrations, including the **single MAJOR bug holding Reliability at C**: a column named `key` in ActiveStorage's own migration |
| `samples/**` | Committed demo OSCAL output, not source |

---

## Coverage was never reaching Sonar

`coverage: n/a` despite 6,700+ rspec examples. SimpleCov is wired, `COVERAGE=1`
is set, the report is uploaded as an artifact — and analysis ran as **Automatic
Analysis**, which reads the repository and cannot see a build artifact. No
coverage condition could ever gate anything.

`ci.yml` now runs the scanner and passes
`sonar.ruby.coverage.reportPaths=coverage/.resultset.json`.

> **Required owner action.** SonarCloud refuses CI-based analysis while Automatic
> Analysis is enabled:
> **Administration → Analysis Method → disable Automatic Analysis.**
> Until then the job fails with "You are running CI analysis while Automatic
> Analysis is enabled". It is named `SonarCloud Code Analysis`, already in
> `advisoryChecks`, so it cannot block a merge while the toggle is pending.

---

## Expected rating movement

| After | Security | Why |
|---|---|---|
| Blockers fixed | E → **C** | Worst remaining is MAJOR |
| Majors fixed | C → **B** | Worst remaining is MINOR |
| Minors gone with `Dockerfile_debian` | B → **A** | No open vulnerabilities |

Reliability should reach **A** once the archive exclusion lands and the five
`Web:*` false positives are resolved.
