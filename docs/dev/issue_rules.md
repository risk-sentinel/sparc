# SPARC Issue Process Rules

Standard workflow for every issue in the SPARC phased roadmap.
These rules are **mandatory** — no exceptions without explicit owner approval.

---

## Hard Guardrails

- **Never push directly to `main`** — all changes go through feature/bug branches
- **Never merge PRs** — only the repository owner merges
- **Always plan before implementing** — step 5 is not optional
- **Always update compliance artifacts** when touching security-critical code

---

## Workflow Steps

1. **Pull from Main** unless otherwise noted
2. **Assign the issue** to me
3. **Review the issue** and updated notes/comments
4. **Start a fresh branch** — `feature/` or `bug/` prefix with the issue
   number in the branch name (e.g., `feature/217_nist_rev5_mapping_docs`)
5. **Create a plan** — get approval before writing code
6. **Implement the approved plan**
7. **Troubleshoot any issues**
8. **Update project documentation:**
   - `docs/dev/Implemenation_plan.md` — mark issue complete, update phase status
   - `docs/dev/Developer_Collision_Avoidance_Plan.md` — update file lists, status
   - `docs/dev/release_notes.md` — add entry at top of file (stacked)
   - Regression testing — add/update specs as appropriate
9. **Compliance artifact review** — if the issue touches security-critical
   code (authentication, authorization, audit, session management, crypto,
   input validation, or configuration), update the following:
   - `docs/compliance/nist-sp800-53-rev5-mapping.md` — update control
     status, implementation summary, and code locations for affected controls
   - `docs/compliance/oscal/cdefs/*.json` — update or add OSCAL component
     definitions for new/changed control implementations. Document conditional
     coverage where applicable (see [Conditional Coverage](#conditional-coverage) below)
   - Inline NIST control comments in modified source files (see
     `docs/compliance/README.md` for the comment block format)
   - `.github/oscal-metadata.json` — update if system metadata changes
   - **Goal:** maximize documented application-layer control coverage
10. **Commit / push changes**
    - Reference the issue in all commit messages
11. **Wait for user testing**
    - Functional testing
    - Review regression report(s)
12. **Create a PR**
    - Reference the issue so it will auto-close on merge
    - Wait for the PR to be merged by the owner before moving forward

---

## Conditional Coverage

SPARC's control coverage varies based on deployment configuration.
When documenting controls in CDEFs and the mapping document, always
note which configuration is required for full coverage.

### Authentication Mode Deltas

| Control | Local-Only Login | OIDC/SAML Enabled | OIDC + JWT API Auth | LDAP Enabled |
|---------|-----------------|-------------------|---------------------|--------------|
| **IA-2** Identification & Auth | **Partial** — password only, no MFA | **Full** — IdP enforces MFA when `SPARC_OIDC_FORCE_MFA=true` | **Full** — Okta JWT validated via RS256; IdP MFA applies | **Partial** — depends on LDAP server MFA config |
| **IA-2(1)** MFA to Privileged | **Not Met** — no MFA mechanism | **Full** — delegated to OIDC IdP | **Full** — JWT issued by IdP with MFA | **Partial** — depends on LDAP server |
| **IA-2(2)** MFA to Non-Privileged | **Not Met** — no MFA mechanism | **Full** — delegated to OIDC IdP | **Full** — JWT issued by IdP with MFA | **Partial** — depends on LDAP server |
| **IA-5(1)** Password-Based Auth | **Full** — bcrypt, 12-char min, expiry | **Full** — bcrypt for local + IdP for federated | **Full** — SHA-256 token digest + RS256 JWT sig | **Partial** — LDAP manages passwords |
| **IA-8** Non-Org User ID | **Not Met** — local accounts only | **Full** — Okta/Entra/GitHub/GitLab federation | **Full** — JWT federation for API access | **Partial** — directory scope |
| **IA-12** Identity Proofing | **Not Met** — self-registration | **Full** — delegated to OIDC IdP | **Full** — delegated to OIDC IdP | **Partial** — delegated to directory |

### Recommended Production Configuration

For maximum FedRAMP control coverage:

```bash
# Enable OIDC with MFA enforcement (covers IA-2, IA-2(1), IA-2(2), IA-8, IA-12)
SPARC_ENABLE_OIDC=true
SPARC_OIDC_FORCE_MFA=true

# Enable JWT API authentication for SSO-based API access
# Audience defaults to SPARC_OIDC_CLIENT_ID if not set
SPARC_API_OIDC_AUDIENCE=your-api-audience

# Disable local login to eliminate non-MFA authentication path
SPARC_ENABLE_LOCAL_LOGIN=false

# Or keep local login as fallback but document the coverage gap
SPARC_ENABLE_LOCAL_LOGIN=true  # Partial IA-2 coverage when used
```

### How to Document Conditional Coverage in CDEFs

In OSCAL CDEFs, use the `remarks` field to note configuration dependencies:

```json
{
  "control-id": "ia-2",
  "description": "SPARC supports MFA via OIDC IdP delegation...",
  "remarks": "Full IA-2 coverage requires SPARC_ENABLE_OIDC=true and SPARC_OIDC_FORCE_MFA=true. Local-only login (SPARC_ENABLE_LOCAL_LOGIN=true without OIDC) provides password authentication but does not satisfy MFA requirements. See docs/dev/issue_rules.md for the full auth mode coverage matrix."
}
```

---

## References

- `docs/dev/Implemenation_plan.md` — phased roadmap and issue tracking
- `docs/dev/Developer_Collision_Avoidance_Plan.md` — domain ownership and hot files
- `docs/dev/release_notes.md` — stacked release notes
- `docs/compliance/README.md` — compliance documentation guide
- `docs/compliance/nist-sp800-53-rev5-mapping.md` — central NIST control mapping
