# Contributing

SPARC follows a strict, auditable issue process. The canonical references are
[`CONTRIBUTING.md`](https://github.com/risk-sentinel/sparc/blob/main/CONTRIBUTING.md)
and [`docs/dev/issue_rules.md`](https://github.com/risk-sentinel/sparc/blob/main/docs/dev/issue_rules.md)
in the main repo — this page summarizes them.

## Hard guardrails

- **Never push directly to `main`** — all changes go through `feature/` or `bug/` branches and a PR.
- **Never merge PRs** — only the repository owner merges.
- **Always plan before implementing** — get the plan approved before writing code.
- **Always update compliance artifacts** when touching security-critical code.

## Workflow

1. Pull from `main`; assign the issue to yourself.
2. Review the issue and its notes/comments.
3. Start a fresh branch — `feature/<n>_short_name` or `bug/<n>_short_name`.
4. Create a plan and get approval.
5. Implement, troubleshoot, and add/update specs.
6. Update project docs (`docs/dev/Implemenation_plan.md`, the
   [Developer Collision Avoidance Plan](https://github.com/risk-sentinel/sparc/blob/main/docs/dev/Developer_Collision_Avoidance_Plan.md), etc.).
7. **Compliance artifact review** — for security-critical code (auth, authz,
   audit, session, crypto, input validation, config), update
   `docs/compliance/nist-sp800-53-rev5-mapping.md`, the OSCAL CDEFs under
   `docs/compliance/oscal/cdefs/`, and inline NIST control comments.
8. Run the **full** test suite (`bundle exec rspec`) and `bundle exec rubocop`
   before pushing.
9. Open a PR referencing the issue; the owner merges.

## Migration safety

All database migrations must be **deployment-safe and idempotent** —
`if_not_exists:`/`column_exists?`/`index_exists?` guards, no `NOT NULL` column
without a default on a populated table, and column-level checks in squashes. See
[`docs/dev/issue_rules.md`](https://github.com/risk-sentinel/sparc/blob/main/docs/dev/issue_rules.md#migration-safety-rules).

For long-running data migrations, prefer the deferred pattern
(`include DeferredDataMigration`, v1.8.3) so the container stays up.

## Documentation & this wiki

This wiki is mirrored from the [`wiki/`](https://github.com/risk-sentinel/sparc/tree/main/wiki)
directory in the main repo and published via `wiki/PUSH_TO_WIKI.sh`. **Edit the
source under `wiki/` through the normal PR process** — direct edits to the wiki
git repository are overwritten on the next sync. When you add or move a file
under `docs/`, update [`docs/MAP.md`](https://github.com/risk-sentinel/sparc/blob/main/docs/MAP.md)
in the same PR.
