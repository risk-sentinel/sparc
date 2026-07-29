# IdP as system of record for entitlements

Design record for epic [#860](https://github.com/risk-sentinel/sparc/issues/860), consolidating #842 (map OIDC claims to org/boundary/role) and #707 (two role systems).

**Status: plan. Nothing implemented.** Review this before work begins.

> Slated for the wiki once the feature is live; this in-repo copy is the working draft and should be removed when it is published there.

---

## The decision this rests on

**Roles stay exactly as they are.** That is deliberate, and it dissolves #707 without a migration. The two role systems were never divergent representations of one thing — they are two concerns that share a word.

| | Defined in SPARC | Sourced from the IdP |
|---|---|---|
| **Answers** | What a role may **do** | **Who** holds it, and **where** |
| **Owner** | The customer; an instance admin configures it | The identity provider |
| **Truth for** | Authorization inside a boundary | Entitlement — membership of `{org}:{boundary}:{role}` |

SPARC never learns what a role *means* from a claim. The IdP never learns what a role can *do*. A claim answers exactly one question: *is this person in this role, in this scope?*

---

## Hard constraints

1. **The organization and boundary must already exist.** A grant naming an unknown scope is recorded and surfaced, never created. Auto-creating would let the identity provider mint tenants.
2. **Instance roles are non-destructive from claims.** A claim may not remove or demote an instance admin. Instance-level authority is established in-app.
3. **The last instance admin is never removable** by any automated path.

Constraint 2 is load-bearing rather than incidental: it is what keeps a recovery route open when a claim mapping goes wrong. If it is ever softened for convenience, the recovery path goes with it.

---

## Resolved design questions

### Claim source — native `groups`

Grants are read from the IdP's native `groups` claim, filtered by prefix. No custom claim, no Expression Language, no per-IdP transformation. This works unchanged on Okta, Entra ID, Keycloak and PingFederate because it uses what they already emit from group membership.

### Grant format — fully qualified

```
sparc:instance:{role}
sparc:org:{org_slug}:{role}
sparc:boundary:{org_slug}:{boundary_slug}:{role}
```

The org segment is retained on boundary grants even though boundary slugs may be unique in practice. Fully qualifying the scope makes a mis-scoped grant impossible to express, rather than merely unlikely — the cost is a longer string, the benefit is that an ambiguous grant cannot be written down.

### Slug matching — canonical comparison, casing irrelevant

Claim values are compared to org and boundary slugs **canonically**: case-insensitive, whitespace-trimmed, separator-normalised. An IdP administrator typing `Acme-Prod` must match a boundary slugged `acme-prod`.

This carries the lesson from [#852](https://github.com/risk-sentinel/sparc/issues/852) directly. That issue existed because a dozen ad-hoc control-id transformers disagreed about case and zero-padding, so `AC-02` and `ac-2` were different strings despite naming one control. Decide the canonical form **once**, compare through it everywhere, and never let two representations drift.

Same discipline as `ControlId`: normalise **form**, never **vocabulary**. Canonicalisation makes `Acme-Prod` match `acme-prod`; it must never attempt to guess that `acme_production` means the same boundary.

### Sync modes — `off` and `authoritative` only

`bootstrap` has been **dropped**. It only made sense if grants were persisted and then reconciled, which is not the model below — with session-derived entitlement there is no "first login only" state to preserve.

| Mode | Behaviour |
|---|---|
| `off` (default) | Claims ignored entirely. Today's behaviour, unchanged. |
| `authoritative` | The claims presented at login determine the session's entitlements. |

---

## Entitlement is derived per session, not persisted then reconciled

This is the central mechanic, and it is what makes the whole design safe.

A session's boundary authority comes from **the grants presented at that login**. Grants are not written into SPARC and later diffed against a fresh claim set, because that framing requires a destructive revoke step — and a destructive step is what turns an IdP misconfiguration into a customer-wide outage.

Consequences, all of them good:

- **Nothing is ever revoked destructively.** A grant that stops appearing simply stops being present in subsequent sessions.
- **An IdP failure degrades rather than destroys.** See below.
- **Recovery is automatic.** When the IdP returns to health, the next login carries full entitlements again with no operator action.
- **No blast-radius guard or dry-run is needed**, because there is no bulk mutation to guard.

An unmatched grant — one naming an org, boundary or role that does not exist — is recorded and surfaced to an instance admin so the mapping can be corrected. It is never silently dropped.

---

## Absent claims: degrade to instance-level read-only

If a login carries **no** grants — an IdP outage, a filter typo, a renamed claim — the user still authenticates, but holds **no organization or boundary entitlements** for that session.

What remains reachable is the instance-level material, **view and export only**:

- Control catalogs
- Profiles
- Component definitions (CDEFs)
- Control mappings
- Converters

What is unreachable: every organization and every authorization boundary, and therefore every SSP, SAP, SAR, POA&M and item of evidence.

This is the correct failure posture. The user is not locked out, no data is destroyed, no memberships are stripped, and the blast radius of a claims misconfiguration is *"I can see the catalogs but none of my systems"* — legible, self-describing, and reversible by fixing the IdP rather than by restoring state in SPARC.

It should still be **loud**: a login that resolves zero grants where grants were previously present is worth an audit event and an operator-visible signal, so the condition is diagnosed rather than endured.

---

## Session revocation and idle timeout

Membership revocation already exists in the codebase. The residual exposure is a timing one: a user who is signed in when their access changes retains it for up to the remaining session duration.

Bounded by session duration already, so this is a hardening item rather than a hole. The proposed guard — **worth having on its own merits, independent of this epic** — is an operator-configurable **inactivity timeout**: an idle session is terminated after a defined period rather than surviving for the full session lifetime.

That shortens the window in which a stale entitlement can be used, and is standard practice for compliance-facing systems (NIST 800-53 **AC-11**, Device Lock; **AC-12**, Session Termination).

---

## Onboarding flow

### Phase 0 — prerequisites, in-app, once

Nothing downstream can grant anything that does not exist after this step.

```
1  Create Organization(s)
2  Create AuthorizationBoundary(s) beneath them
3  Define enumerated Roles and their permissions
4  Configure the IdP mapping convention
5  Set the sync mode:  off | authoritative
```

### Phase 1 — every authentication

```
User authenticates at the IdP
        │
        ▼
OIDC callback → SPARC receives claims
        │
        ▼
Parse grants from `groups`, filtered by the sparc: prefix
        │
        ├── no grants present ──► authenticate, but grant NO org/boundary
        │                        entitlements. Instance-level read-only.
        │                        Audit it; signal to the operator.
        ▼
Find or create the User by stable subject (sub); email as fallback
        │
        ▼
For each grant  { scope_type, org, boundary, role }
        │
        │   compare slugs CANONICALLY (case/whitespace/separator-insensitive)
        │
        ├── org unknown?      ──► record unmatched grant, surface to admin
        ├── boundary unknown? ──► record unmatched grant, surface to admin
        ├── role unknown?     ──► record unmatched grant, surface to admin
        ├── instance-level?   ──► apply only if allowlisted; never destructive
        │
        └── all resolve       ──► entitlement active for this session
        │
        ▼
Audit each grant applied and each grant unmatched, with the reason
```

---

## Two axes, not one spectrum

Offboarding and scope reduction are different mechanisms answering different questions. Conflating them is what makes access changes hard to reason about.

| Axis | Mechanism | Answers |
|---|---|---|
| **Authentication** | The IdP / MFA stops authenticating the user | Can they get in **at all**? |
| **Authorization** | Grants absent from the claims presented at login | What can they **reach** once in? |

### Offboarding a person — authentication

**The offboard is complete when the IdP no longer authenticates them.** There is no separate de-provisioning step in SPARC, because SPARC never held the entitlement independently: it derives authority per session from claims, and a user who cannot authenticate presents no claims.

That is the whole mechanism. It is not a gap requiring compensating in-app action.

Two deployment preconditions make it airtight, and both should be stated in operator documentation rather than discovered:

- **Local login must be disabled, or break-glass only.** A local credential is a second authentication path and therefore a second way in. In an IdP-as-source-of-record deployment it should not exist for ordinary users.
- **An active session survives until it ends.** Bounded by session duration, and shortened by the configurable inactivity timeout. This is a known, bounded window rather than an open one.

In-app deactivation by an instance admin remains available as a **fallback** — for a deployment that has not disabled local login, or when a session must be ended immediately rather than at expiry. It is not the primary route. It retains the user record for audit integrity (NIST **AU-9**) rather than hard-deleting it.

### Reducing what someone can reach — authorization

A grant removed at the IdP is simply absent from the next login, so the entitlement does not materialise. Other scopes are unaffected. Nothing is revoked destructively, and recovery is automatic if the grant returns.

At the limit, **all** grants absent leaves an authenticated user with no organization or boundary access at all — the degrade posture described above. That is scope reduction taken to zero, which is deliberately **not** the same as an offboard: the person can still sign in.

## Deliverables

- [ ] Parse grants from the `groups` claim using the documented convention
- [ ] Canonical slug comparison for org, boundary and role matching
- [ ] Session-derived entitlement resolution against existing scopes
- [ ] Absent-claims path: authenticate, instance-level read-only, audited and signalled
- [ ] Unmatched-grant queue visible to an instance admin
- [ ] Instance-role allowlist; non-destructive; last-admin guard
- [ ] Configurable inactivity timeout (AC-11 / AC-12) — independently valuable
- [ ] Audit events for grants applied, unmatched, and logins resolving zero grants
- [ ] Operator documentation: convention, modes, failure posture, offboarding procedure for trigger B

## Still open

- **Trigger B**: the procedure for a leaver who also holds a local-login credential.
- Whether the instance-level read-only surface listed above is exactly right, or whether any of those five should also be gated.
