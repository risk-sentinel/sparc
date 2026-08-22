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

**A grant binds to `user_roles`, never to `authorization_boundary_memberships`.**
That is the written answer #842 needs. The documentary table may not be driven
from claims: it can name a person with no account, and overwriting it from an
IdP would destroy SSP content that an assessor reads.

---

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

### Q4 — Session revocation timing · **DECISION NEEDED**

**The epic's premise is half wrong, and the correction narrows the work.**

The epic says *"existing SPARC session remains valid until timeout."* For an
**in-app deactivation that is not true**: `current_user` re-reads the user on
every request with `status: "active"`, so the very next request after
deactivation is unauthenticated. Offboarding path **C is already solved**.

What is genuinely missing is different: **SPARC never finds out that the IdP
disabled someone.** Okta disables the account, the user cannot start a *new*
session, and their existing SPARC cookie keeps working until idle timeout
because nothing told SPARC anything changed.

Three options, in ascending cost:

| Option | What it is | Cost | Residual gap |
|---|---|---|---|
| **A. Document it** | Operator procedure: disabling in Okta is not offboarding; deactivate in SPARC too | ~0 | Depends on a human doing both |
| **B. Re-sync job** | Periodic job re-reads entitlements and deactivates users the IdP no longer returns | Moderate — needs a service account with directory read | Window = the interval |
| **C. Back-channel logout / SCIM** | Okta pushes logout or deprovisioning to SPARC | High — new endpoint, new trust relationship | Smallest |

**Recommendation: A now, B in v1.16.1, C only if a customer requires it.**
The idle timeout already bounds the exposure, and option C is a second
authenticated inbound channel — meaningful new attack surface for a gap that A
plus the timeout largely covers. **Owner call, because it sets the offboarding
claim SPARC can make in its own SSP.**

### Q5 — Does `bootstrap` mode earn its keep? · **DECISION NEEDED**

**Recommendation: keep it**, and make it the default.

`bootstrap` is the ADD leg only. It costs almost nothing — the same parse and
resolve, with the revoke branch skipped — and it is the mode a customer can turn
on without any risk of mass de-provisioning. `off → bootstrap → dry-run →
authoritative` is a safe adoption ladder; `off → authoritative` is a cliff.

Marked as a decision because it is three modes to test and document rather than
two, and that is a real cost the owner may not want.

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

1. **Q4** — offboarding: option A, B or C?
2. **Q5** — keep `bootstrap`, or ship `off` + `authoritative` only?

Everything else above is a recommendation grounded in the schema or the
authentication concern, and proceeds unless overruled.
