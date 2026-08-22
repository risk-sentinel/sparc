# #860 — IdP as system of record for entitlements: design memo

**Status: for owner review. No code until the five questions below are answered.**
Bundle R, milestone v1.16.0, with #842 and #822.

The epic (#860) sets the model; this memo answers its open questions against
what the codebase actually is, and adds the Okta console procedure needed to
validate it.

Three of the five questions turned out to be answerable by **measurement rather
than preference** — the schema and the authentication concern already settle
them. Two are genuine owner decisions and are marked **DECISION NEEDED**.

---

## What the code already establishes

Measured on `main` at `fda3413d`, not assumed.

| Fact | Where | Why it matters |
|---|---|---|
| **Boundary slugs are GLOBALLY unique** | `db/schema.rb` — `index ["slug"] … unique: true`, not scoped to `organization_id` | Q2: the org segment in a grant string is redundant *for resolution* |
| **Organization slugs are globally unique** | same, plus a unique index on `name` | Grants can address an org unambiguously |
| **`user_roles` already has a `source` column** | `t.string "source", default: "manual", null: false`, indexed | The sync has its provenance field already. **No migration needed to tell an IdP grant from a hand-made one** |
| **`user_roles` is boundary-scoped and role-FK'd** | `user_id + role_id + authorization_boundary_id` unique | This is the membership model a grant binds to |
| **`current_user` re-reads the user EVERY request, filtered `status: "active"`** | `app/controllers/concerns/authentication.rb:85` | Q4: an in-app deactivation ends a live session **immediately**, not at timeout |
| **Sessions are Rails `cookie_store`** | `config/initializers/session_store.rb` | There is no server-side session table to enumerate or delete |
| **OIDC is generic and already wired** | `config/initializers/omniauth.rb` — `provider :openid_connect, discovery: true` | Okta needs no new adapter, only configuration |
| **`Identity` links user ↔ provider by `uid`** | `app/models/identity.rb`, unique on `(provider, uid)` | The stable `sub` join the epic asks for exists |

### The two role systems, stated precisely (#707)

There are two, and the epic is right that they are not duplicates:

1. **`authorization_boundary_memberships`** — `t.string "role"`, plus
   `user_name`/`user_email` **string** columns and a nullable `user_id`. This is
   a *documentary* record: who is named as holding a role on this boundary, for
   the SSP. It can describe a person who has no account.
2. **`user_roles` → `roles`** — a real FK to a permission-carrying `Role`,
   scoped to a boundary, with `source`. This is the *authorization* record.

**CORRECTION (2026-08-22, while building the resolver): there are THREE, not
two.** This memo originally said a grant binds to `user_roles`. That is right
for a BOUNDARY grant and wrong for an ORG grant, and the error came from
checking `user_roles` for a boundary column and never checking it for an
organization one. **`user_roles` has no `organization_id`** — its only scope is
`authorization_boundary_id`, and a validation requires instance-scoped roles to
carry a NULL boundary. An org grant cannot land there at all.

| Representation | What it is |
|---|---|
| `user_roles → roles` | The **authorization** record. FK to a permission-carrying `Role`, boundary-scoped (or NULL for instance roles). Carries `source`. |
| `organization_memberships.role` | A **string** from a configurable list (`OrganizationMembership.available_roles`), a different vocabulary. `org_admin` here is a real permission gate — `User#org_admin_for?`. |
| `authorization_boundary_memberships` | **Documentary**, for the SSP. `user_name`/`user_email` strings and a nullable `user_id`, so it can name a person with no account. |

**A boundary grant resolves to the first. An org grant resolves to the second.
Nothing resolves to the third, ever** — it is content an assessor reads, and a
sync that overwrote it would replace a deliberate statement about who holds a
role with a directory's current opinion. That is the written answer #842 needs,
and #707's "two role systems" is itself an undercount worth fixing on the issue.

**Instance roles stay unreachable by construction:** the grant format has no
instance scope, so there is no string an IdP can emit that grants an
instance-wide role or the `users.admin` break-glass flag. The epic's
"never destructive to instance roles" constraint needs no guard, and recovery
from a misconfigured IdP is therefore always possible.

---

## How instance-level roles are managed (owner question, 2026-08-22)

**They are `user_roles` rows with `authorization_boundary_id: NULL`**, pointing
at a `Role` whose `scope` is `"instance"`. Ten are seeded: `policy_manager`,
`global_viewer`, `senior_accountable_official`, `senior_agency_official_privacy`,
`head_of_agency`, `risk_executive`, `cio`, `chief_acquisition_officer`,
`fedramp_pmo`, `jab`.

**`users.admin` is NOT one of them.** Instance Admin is a boolean column, the
break-glass authority, and it is deliberately outside the role system entirely.

**Today they are assigned in ONE place: the admin UI**, `Admin::UsersController`
(`role_ids`), which destroys the instance roles not in the submitted list and
creates the rest. `Api::V1::UsersController` **reads** them — it serialises
name, display_name and scope — but there is **no API write path for instance
roles at all.**

That is an API-first gap of the kind the standing rule exists to catch, and it
is worth an issue of its own rather than being folded in here silently. It is
also the reason the admin UI's destroy-then-create is safe TODAY and would stop
being safe the moment anything else could create an instance role: the delete is
**source-blind**, so it would remove an IdP-granted row as readily as a
hand-made one.

### They stay out of IdP reach, and that is a design choice

The grant format has **no instance scope**. There is no string an IdP can emit
that grants an instance-wide role or sets `users.admin`, so the epic's
"never destructive to instance roles" and "the last instance admin is never
removable by any automated path" constraints are satisfied **by construction**
rather than by a guard someone could later relax.

The epic contemplated `instance-level? → SKIP unless allowlisted`. This design
goes further and makes it inexpressible, because instance roles are the recovery
path: if a claim could grant or strip instance-wide authority, a single IdP
misconfiguration could over-privilege or lock out the entire instance, and the
way back would run through the very system that broke it.

**If instance roles are wanted from the IdP later**, the shape should be an
explicit opt-in allowlist (`SPARC_OIDC_INSTANCE_ROLES`, empty by default) that
is **additive only** — never revoking — and that can never name `admin`. That
keeps the recovery path intact whatever the directory says. Not built, and not
recommended until someone asks for it.

## The five questions

### Q1 — Claim name: `groups` or a dedicated `sparc_grants`?

**Recommendation: neither, hardcoded — make the claim name configurable**, new
`SPARC_OIDC_GRANTS_CLAIM`, **defaulting to `groups`**.

`groups` is what every IdP emits by default and what an evaluator will try
first. A dedicated claim is better hygiene on a large tenant, but hardcoding
either one makes SPARC wrong for half its deployments. The prefix filter
(`SPARC_OIDC_GRANTS_PREFIX`, default `sparc:`) is what keeps unrelated groups
out, and it works the same whichever claim carries them.

This dissolves the question rather than answering it, which is why it is not
marked as a decision.

### Q2 — Grant format: keep the org segment?

**Recommendation: keep it. `sparc:boundary:{org_slug}:{boundary_slug}:{role}`.**

Boundary slugs *are* globally unique, so the org segment is not needed to
resolve the grant. Keep it anyway, and **verify it**: if the named org does not
own the named boundary, record an unmatched grant with that reason rather than
applying it. That converts a mis-scoped Okta group from a silent
wrong-tenant grant into a visible, named refusal — for the cost of one
comparison. Grant strings are also read by humans in the Okta console, and
`sparc:boundary:acme:acme-prod:reviewer` is legible where the bare slug is not.

Org-scoped grants stay `sparc:org:{org_slug}:{role}`.

### Q3 — Case and slug matching

**Recommendation: canonicalize once, compare canonically — the #852 rule.**

Downcase and strip the claim value, then compare against the stored slug. Slugs
are already generated lowercase. **One canonical form, applied at the boundary
of the system**, exactly as [`ControlId`](../../app/models/concerns) does for
control identifiers — and per the standing rule, the canonical form is a named,
tested unit, not an inline `.downcase` at three call sites.

Not an owner decision; it is a correctness rule with one right answer.

### Q4 — Session revocation timing · **DECIDED (owner, 2026-08-22)**

> *"Each login should establish user capabilities/rights. We enforce the logout
> based on the login expiration (default I think is set as 60 min)."*

**Ruling: entitlements are established at login, and the exposure window is
bounded by the session timeout.** No re-sync job, no SCIM, no back-channel
logout. Option A.

The model is coherent and the mechanism exists. Verified rather than assumed:

- `SparcConfig.session_timeout` = `SPARC_SESSION_TIMEOUT_MINUTES`, **default 60**
  (`sparc_config.rb:352`) — the owner's recollection is correct.
- `check_session_timeout` is a **global `before_action`** in
  `ApplicationController:13`, mapped to AC-11 / AC-12 / IA-11.
- `current_user` re-reads the user every request on `status: "active"`, so an
  in-app deactivation is immediate.

**One caveat, because it changes the claim SPARC can make in its own SSP: the
60-minute timeout is an IDLE timeout, not an absolute one.** `last_active_at` is
refreshed on every request (`authentication.rb:166`) and there is **no absolute
session cap anywhere in the codebase.** So:

- An **idle** user is bounded at 60 minutes. The ruling holds exactly as stated.
- An **actively working** user is never forced to re-authenticate, so their
  entitlements — and their access after an Okta-side disablement — persist for
  as long as they keep clicking. A full working day is a single session.

"Each login establishes capabilities" bounds entitlement staleness only if there
is a bounded time until the *next* login, and today there is not.

**Recommended, small, and separable:** an absolute cap,
`SPARC_SESSION_MAX_HOURS` (suggest 12 — a working day, so it costs a real user
nothing), checked in the same `before_action` against a `session[:started_at]`
set at sign-in. Roughly a dozen lines and one spec. It makes the owner's model
literally true rather than approximately true, and it is the difference between
"sessions expire after 60 minutes of inactivity" and "a session cannot outlive
its entitlements by more than 12 hours" — the second is what an assessor reading
AC-12 wants.

**Owner's call whether that rides Bundle R or is filed separately; it is not a
blocker for the entitlement work either way.**

### Q5 — Does `bootstrap` mode earn its keep? · **DECIDED (owner, 2026-08-22)**

**Ruling: keep it, and make it the default.** `off` → `bootstrap` → dry-run →
`authoritative` is the adoption ladder.

`bootstrap` is the ADD leg only. It costs almost nothing — the same parse and
resolve, with the revoke branch skipped — and it is the mode a customer can turn
on without any risk of mass de-provisioning. `off → bootstrap → dry-run →
authoritative` is a safe adoption ladder; `off → authoritative` is a cliff.

Three modes to build, test and document rather than two — accepted as the cost
of not handing customers a cliff.

---

## What gets built, in order

**Dry-run first, not last** — the standing rule for this bundle.

1. `GrantString` — parse and canonicalize. Pure, no DB. Tested first.
2. `GrantResolver` — resolve to org/boundary/role. **Never creates.** Returns
   applied and unmatched with a named reason for each.
3. `EntitlementSync#dry_run` — the diff, computed and reported, applying nothing.
4. `EntitlementSync#apply` — modes `off` / `bootstrap` / `authoritative`.
5. Blast-radius guard — refuse a sync revoking more than
   `SPARC_OIDC_SYNC_MAX_REVOKE_PCT` (default 25%) without confirmation.
6. Instance-role protection and the last-admin guard.
7. Unmatched-grant queue for the instance admin.
8. Audit events per grant applied, skipped and revoked, **registered in
   `AuditEvent::ACTIONS`** — an unregistered action records nowhere (#982).
9. `Api::V1` endpoints for the sync status, the dry-run and the unmatched queue,
   with request specs. UI is a thin client over them.

**A missing claim is an ERROR. An empty claim is "no grants."** Distinct paths,
tested in both directions — the failure mode this epic exists to prevent.

---

## Okta console configuration — what to change, and how to validate

The generic OIDC provider already works, so this is configuration only. **Okta
moves its console labels periodically**; the objects are stable even when the
navigation is not.

### 1. Create the application

**Applications → Applications → Create App Integration**

- Sign-in method: **OIDC — OpenID Connect**
- Application type: **Web Application** (Authorization Code, confidential
  client — SPARC holds a client secret)
- **Sign-in redirect URI:** exactly `SPARC_OIDC_REDIRECT_URI`, e.g.
  `https://sparc.example.org/auth/oidc/callback`
- **Sign-out redirect URI:** the SPARC root
- Assignments: assign the users or groups who may reach SPARC at all. **This is
  authentication, not entitlement** — being assigned the app does not grant a
  role.

Copy the **Client ID** and **Client secret** into `SPARC_OIDC_CLIENT_ID` /
`SPARC_OIDC_CLIENT_SECRET`, and the org issuer (e.g.
`https://example.okta.com`, or `https://example.okta.com/oauth2/<id>` for a
custom authorization server) into `SPARC_OIDC_ISSUER_URL`. Discovery is on, so
SPARC reads the endpoints from `/.well-known/openid-configuration`.

### 2. Create the groups that ARE the entitlements

**Directory → Groups → Add Group**, one per grant. The group **name** is the
grant string:

```
sparc:boundary:acme:acme-prod:reviewer
sparc:boundary:acme:acme-prod:assessor
sparc:org:acme:member
```

The org and boundary segments must match existing SPARC slugs exactly. A grant
naming something SPARC does not have is **recorded and surfaced, never created**
— that is the constraint that stops the IdP minting tenants.

### 3. Emit them in the token

Okta does not include groups by default. Either:

**App-level (simplest, org authorization server):**
Applications → *your app* → **Sign On** → **OpenID Connect ID Token** →
- Groups claim type: **Filter**
- Groups claim filter: `groups` **Matches regex** `^sparc:`

**Authorization-server-level (custom auth server):**
Security → API → Authorization Servers → *your server* → **Claims** → Add Claim
- Name: `groups` (or your `SPARC_OIDC_GRANTS_CLAIM`)
- Include in: **ID Token**, *Always*
- Value type: **Groups**, Filter **Matches regex** `^sparc:`

**The regex filter is not cosmetic.** Without it Okta sends every group the user
belongs to, which on a real tenant is hundreds of unrelated names, all of which
SPARC must then reject one at a time into the unmatched queue.

Then add the scope so the claim is actually requested:

```
SPARC_OIDC_SCOPES="openid profile email groups"
```

### 4. Validate, before enabling any sync

1. Set `SPARC_OIDC_SYNC_MODE=off`. Sign in. **Confirm authentication works and
   nothing was granted.**
2. Inspect the received claim — the unmatched-grant queue shows exactly what
   arrived, which is the fastest way to see whether the filter and scope are
   right. A token debugger works too, but the queue is SPARC's own reading.
3. Switch to **dry-run** and read the diff: *"would add 3, would revoke 0,
   2 unmatched."* Any surprise here is a naming mismatch, and it costs nothing.
4. `bootstrap` — additive only. Verify a real user lands with the right
   entitlements and **no more**.
5. `authoritative` only after a dry-run reports a revoke count you expect.

### 5. For #822 — PIV via `acr` / `amr`

Separate from entitlements and configured separately: an Okta **authentication
policy** requiring the PIV/smart-card factor, bound to the app, with SPARC
requesting and then **verifying** the resulting `acr`/`amr` values. Two-ceremony
verification is required — see the standing rule. Detail lands with #822; it is
listed here only so the console work is done in one sitting.

### Environment variables this introduces

| Variable | Default | Purpose |
|---|---|---|
| `SPARC_OIDC_GRANTS_CLAIM` | `groups` | Which claim carries grants |
| `SPARC_OIDC_GRANTS_PREFIX` | `sparc:` | Filter applied before parsing |
| `SPARC_OIDC_SYNC_MODE` | `off` | `off` / `bootstrap` / `authoritative` |
| `SPARC_OIDC_SYNC_MAX_REVOKE_PCT` | `25` | Blast-radius guard |

All four go in `docs/ENVIRONMENT_VARIABLES.md` and the wiki when the code lands.

---

## Backwards compatibility — the guarantees this design makes

**An existing OIDC deployment that upgrades and changes nothing must behave
identically.** That is a hard requirement, not a goal, and it is achievable
because every new behaviour is opt-in. The guarantees:

1. **`SPARC_OIDC_SYNC_MODE` defaults to `off`.** Grants are parsed by nothing
   and applied by nothing. Sign-in, provisioning and roles work exactly as they
   do today.

2. **The `SPARC_OIDC_SCOPES` default does NOT change.** It stays
   `"openid profile email"` (`sparc_config.rb:439`) — deliberately *not*
   `"… groups"`. Adding a scope by default changes the authorization request
   every existing deployment sends, and an IdP with no `groups` scope defined
   can reject it outright at the authorization endpoint. **That would turn an
   upgrade into an outage on the login path**, which is the worst place to have
   one. Operators add the scope when they choose to enable grants.

3. **Only rows the sync created are ever revoked.** `user_roles.source` already
   defaults to `"manual"`; the sync writes `"idp"` and **revocation is scoped to
   `source: "idp"`**. A hand-made grant cannot be removed by an IdP sync even in
   `authoritative` mode, even if the claim set is empty, even if the whole IdP
   configuration is wrong.

   This is the strongest safety property in the design and it is worth stating
   plainly: **the blast radius is bounded by construction, not only by the
   percentage guard.** The guard in deliverable 5 is a second line of defence
   against a bad sync, not the first.

4. **No migration.** `source` exists and is indexed; `Identity` already joins on
   `(provider, uid)`. Nothing in the schema changes for this feature. The
   unmatched-grant queue is a new read model over data the sync records.

5. **Local login, GitHub, GitLab, LDAP, FIDO2 and PIV are untouched.** Grants
   ride the OIDC callback only. A deployment using any other method sees no
   change at all.

6. **`off` remains a supported end state.** A customer who wants SPARC to own
   entitlements entirely is not obliged to adopt any of this, and the
   documentation must not read as though IdP sync is now the expected posture.

**Verification: the backwards-compatibility claim gets a test, not a paragraph.**
A spec that signs a user in through the OIDC callback with `SPARC_OIDC_SYNC_MODE`
unset, asserting that no `user_roles` row is created, changed or removed and that
the request the client builds carries the unchanged scope string. Both
directions, per the standing rule — the same spec with the mode on proves the
sync is actually wired, so the off-leg cannot pass vacuously.

## Documentation this changes

Public-facing, so the **wiki is canonical** and the in-repo copies are the
technical reference. All of it lands with the code, in the same PR, and the wiki
needs its manual `wiki/PUSH_TO_WIKI.sh` run — editing `wiki/` publishes nothing.

| Document | What changes |
|---|---|
| `docs/OKTA_DEV_SETUP.md` | Already a 10-step Okta walkthrough. Gains the groups-as-grants convention, the regex-filtered claim, the scope, and the five-step validation ladder. The Okta section of this memo is the draft |
| `docs/AUTHENTICATION.md` | §"OIDC / SSO" gains the sync modes; §"Roles" gains the statement that a grant binds to `user_roles` and never to the documentary boundary-membership table |
| `docs/ENVIRONMENT_VARIABLES.md` | The four new variables, with their defaults and the note that the scopes default is deliberately unchanged |
| `wiki/Authentication-and-MFA.md` | Operator-facing: what the modes mean and the adoption ladder |
| `wiki/Configuration.md` | The four variables |
| `wiki/RBAC.md` | **The two role systems, stated once, properly** — this is where #707's answer belongs so it stops being folklore |

`docs/PRODUCTION_SECURITY.md` gets the offboarding posture once Q4 is decided —
it is the document that would otherwise imply SPARC ends sessions on IdP
disablement, which it does not.

## Open for the owner

**Both design questions are answered; the memo is settled and implementation can
begin.** One item is left for a decision that does not block it:

- **The absolute session cap** (`SPARC_SESSION_MAX_HOURS`, Q4 above) — in Bundle
  R, or filed for v1.16.1? Recommended either way, because without it the
  offboarding posture is weaker than the ruling assumes for an active user.
