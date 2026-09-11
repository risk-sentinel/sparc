# #1044 — admin authority triage

**Status:** complete. Decisions enforced by
`spec/security/admin_identity_sites_spec.rb`, which fails on any raw `admin?`
outside the approved list below.

## The distinction

`admin?` conflated two things. #1044 separates them.

| | Meaning | Who holds it | How it ends |
|---|---|---|---|
| `admin?` | **IDENTITY** — the dedicated break-glass account | A single provisioned account (`SPARC_ADMIN_EMAIL`), required at boot. In practice a **local** login whose credential is checked out of a vault — EPV, AWS Secrets Manager or equivalent | It does not. It is permanent by design, and unreachable from any IdP claim, which is what makes recovery always possible |
| `instance_administrator?` | **AUTHORITY** — may act with instance-wide power right now | The break-glass account, **or** a named person holding an instance-scoped role carrying `admin.administer` | The IdP drops the group; the next sign-in revokes the grant (`EntitlementSync`, authoritative mode); `SPARC_SESSION_MAX_HOURS` (#1043) bounds the session already open |

The rule that decided almost every site:

> **`admin?` used as a GUARD is authority. `admin?` used as a VALUE — displayed,
> serialised, or protecting the account itself — is identity.**

## What was measured

117 `.admin?` call sites in `app/` — not the 77 the issue stated, which counted
only controllers and missed models, services, views and helpers.

| Disposition | Count |
|---|---|
| Swapped to `instance_administrator?` | **105** |
| Kept as `admin?` — deliberate | **12** |

Shapes encountered: 64 early escapes (`return if current_user&.admin?`), 9
`admin? \|\| has_permission?(…)` pairs, 8 hard gates, 17 view/helper visibility
checks, 9 in models and services, plus the rest scattered through controllers.

The 9 `admin? || has_permission?(…)` sites were already redundant before this
issue — `has_permission?` short-circuited on `admin?` — and are now correct
without the prefix, because the short-circuit moved to authority.

## The sites that kept `admin?`

### Separation of duties — owner-decided 2026-08-21

- `app/services/document_approval_service.rb`
- `app/services/finding_disposition_service.rb`

> "admin is global authority and has absolute reign, break-glass type of use."

The exemption belongs to the **account**. A person holding a time-boxed grant
must not be able to approve what they themselves submitted — that is ordinary
separation of duties, and nothing about a temporary grant should suspend it.

### The escalation boundary

- `app/services/user_provisioning_service.rb`

**Found by this triage, and the most important thing in it.**
`apply_privileged_attributes!` sets both `status` and the `admin` **column**. It
was gated on `admin?` as a whole.

Managing users is administrative work, so authority is enough for `status`.
Setting the `admin` column is different in kind: it confers the break-glass
account, which is permanent and which no directory can revoke. Had the whole
method moved to authority, an IdP-granted administrator holding power for one
afternoon could have minted a **permanent** administrator before the grant
expired — and the guarantee that makes granting instance roles from an IdP safe
at all ("`users.admin` is unreachable from any claim, by construction" —
`IdpGrantResolver`) would have held only on paper. The claim could not reach the
column directly, so it would have reached it through a user it created.

The method is now split: authority for `status`, break-glass only for `admin`.

### Reporting the attribute, not gating on it

- `app/views/admin/users/show.html.erb` — renders "Admin: Yes/No"
- `app/views/admin/users/index.html.erb` — the admin badge
- `app/controllers/admin/users_controller.rb` — serialises it into an audit payload
- `app/controllers/api/v1/users_controller.rb` — serialises it into the API response

These answer "what does the column say", which is a real question with a real
answer. They are not gates.

### Telling the two apart

- `app/models/audit_event.rb`

`admin_authority_metadata` exists precisely to distinguish break-glass from a
time-boxed administrator in the audit trail. It has to read the column.

### The account's own lifecycle

- `app/models/user.rb` (3 sites)

`protect_last_active_admin` and `last_active_admin?` stop the break-glass
account being deactivated into an unrecoverable instance — about the account
existing, not about who may act. The third is `instance_administrator?`'s own
base case.

## Audit attribution (slice 4)

Every `AuditEvent` written by an administrator now carries `admin_authority`:

| Value | Meaning |
|---|---|
| `break_glass` | The dedicated account. Attribution runs through the **vault checkout record**, not through SPARC — SPARC only knows the shared account signed in |
| `instance_admin` | A named person holding a time-boxed IdP grant. Attribution is the person, and the directory decides when it ends |
| *(absent)* | Not an administrative actor, or the event predates #1044 |

Metadata rather than a column: it is a property of the act, and backfilling a
column for events logged before the distinction existed would mean inventing an
answer. Caller-supplied metadata wins on key collision — this adds context, it
never overwrites evidence.

NIST 800-53: AU-3, AU-3(1) (content of audit records), AC-6(9) (audit the
execution of privileged functions), AC-2, AC-5, AC-6.

## What is deliberately still impossible

- **An IdP cannot confer or revoke `users.admin`.** `IdpGrantResolver` only ever
  produces `user_roles` and `organization_memberships`. Recovery from a
  misconfigured directory therefore always exists.
- **A boundary-scoped role carrying `admin.administer` confers nothing
  instance-wide.** `instance_administrator?` requires `authorization_boundary_id
  IS NULL`, and there is a spec for it.
- **A time-boxed administrator cannot become a permanent one.** See the
  escalation boundary above.
