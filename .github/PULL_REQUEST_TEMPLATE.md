<!--
Thanks for contributing to SPARC. This template enforces a small convention
that keeps the PR Checklist gate happy. Read CONTRIBUTING.md for the full story.

Convention in one line: checkboxes only in `## Test plan`. Use plain bullets
in `## Verified by CI` and `## Post-merge verification`. If you absolutely need
a checkbox elsewhere, wrap it in a `<!-- pr-checklist:skip -->` block.
-->

Closes #<!-- issue number -->.

## Summary

<!-- 1-3 sentences: what changed and why. -->

## Changes

<!-- Concrete bullet list of what's in the diff. -->
-

## Test plan

<!--
ALL `- [ ]` items in this section MUST be checked before merge.
Replace this comment with your real items.

For trivial PRs (typo fixes, doc-only changes) you may leave this empty —
the checklist passes when zero checkboxes are present.

For items verified by CI on this PR or after merge, use the sections below
(plain bullets, no checkboxes) — not this one.
-->

## Verified by CI

<!--
Plain bullets — no checkboxes. CI run status proves these.
Examples:
- security_gate runs HDF amendments + SAF threshold against PR scanners
- rspec / rubocop / brakeman pass
-->
-

## Post-merge verification

<!--
Plain bullets — no checkboxes. Verified after merge or on next release.
Examples:
- release pipeline publishes container on tag push
- staging deploy smoke test
-->
-

## Notes

<!-- Optional: screenshots, follow-up issues, deployment notes, anything else. -->
