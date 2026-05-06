# Contributing to SPARC

Thanks for working on SPARC. This document covers the project conventions for
opening pull requests so the PR Checklist gate doesn't bite you.

For the broader issue/branch/CDEF/auth-mode workflow, see
[`docs/dev/issue_rules.md`](docs/dev/issue_rules.md) — it is the canonical
process and is **mandatory** for non-trivial work.

## Pull request convention

`.github/workflows/pr-checklist.yml` runs on every PR and fails if **any
unchecked checkbox (`- [ ]`) remains in the PR body**. That is intentional for
the human-verified test plan, but it bites two legitimate cases:

1. Items that can only be confirmed by CI runs on the PR itself
2. Items verified after merge (release pipeline, post-deploy smoke tests)

To keep both cases out of the gate, SPARC PRs use a **fixed five-section
shape** — checkboxes belong to exactly one section, the others use plain
bullets.

### Sections

```markdown
## Summary               — 1-3 sentences, what and why
## Changes               — bullet list of concrete diffs
## Test plan             — `- [ ]` checkboxes; ALL must be checked before merge
## Verified by CI        — plain bullets, no checkboxes
## Post-merge verification — plain bullets, no checkboxes
## Notes                 — optional context
```

The PR template at `.github/PULL_REQUEST_TEMPLATE.md` ships this shape — open
a PR and the body pre-populates.

### When to use which section

| Section | Use for | Form |
|---|---|---|
| Test plan | Things the **author** verified locally before opening the PR | `- [x]` after doing it |
| Verified by CI | Things proved by **green CI on this PR** (specs pass, security_gate green, etc.) | plain `-` bullet |
| Post-merge verification | Things confirmed after merge or on next release | plain `-` bullet |

A useful rule of thumb: if the answer to "is this checkable right now, by me,
before I click Open?" is **no**, it does **not** belong in Test plan.

### Escape hatch — `<!-- pr-checklist:skip -->`

If you genuinely need a checkbox outside Test plan (e.g. a release-pipeline
checklist that mixes pre- and post-merge items inline), wrap it in skip
markers and the workflow will ignore the contents:

```markdown
<!-- pr-checklist:skip -->
- [ ] release published to GHCR (verified post-merge)
- [ ] release notes posted to GitHub Releases page
<!-- /pr-checklist:skip -->
```

The opener line, the closer line, and everything in between are stripped from
the checkbox count. Use this sparingly — section-based separation is clearer
to reviewers.

### Trivial PRs

The checklist warns but does **not** fail when zero checkboxes are present.
Typo fixes, comment-only edits, and doc-only changes can leave Test plan
empty if there is genuinely nothing to verify.

## Branching & commits

- Branch off `main`. Never push to `main` directly — always go through a PR.
- Branch name: `feature/<issue>_short_slug` or `fix/<issue>_short_slug`.
- Stack commits on a single branch for multi-slice work on one issue
  (one PR per issue, not one PR per slice).
- Commit messages: imperative subject, body explains the *why*. Reference
  the issue (`Closes #N` in the PR body, not every commit).

## Tests, lint, security

Before pushing, run locally:

```bash
bundle exec rspec
bundle exec rubocop
bundle exec brakeman
```

CI re-runs all of the above and adds `security_gate` (HDF amendments + SAF
threshold), CodeQL, Trivy, Gitleaks, importmap audit, dependency audit, and
SBOM generation. See [`docs/dev/issue_rules.md`](docs/dev/issue_rules.md) for
compliance-artifact requirements (CDEFs, NIST mapping, control comments)
when touching security-critical code.

## Reporting issues

File issues in the repository's issue tracker. Use the templates under
`.github/ISSUE_TEMPLATE/` where they apply.
