# Authentication and MFA

SPARC supports several sign-in methods, and several of them are
phishing-resistant, DoD-ready multi-factor authentication (MFA). This page is
the **operator** reference for enabling and configuring them. For the end-user
walkthrough, see [User Guide: Security Keys & Smart Cards](User-Guide-Security-Keys).

**Methods at a glance**

| Method | Factor(s) | MFA-grade | Notes |
|--------|-----------|-----------|-------|
| Local password | password | No | Break-glass admin path; keep for emergency access |
| OIDC / SSO | delegated to IdP | When the IdP enforces it | GitHub / GitLab / generic OIDC |
| LDAP | directory password | No | Directory-validated password |
| **FIDO2 / WebAuthn** | security key **+** PIN | **Yes** | Passwordless; the key + PIN is MFA in one step |
| **PIV / CAC** | smart-card cert **+** PIN | **Yes** | Certificate over mutual TLS |

All authentication methods default to **disabled** — enable the ones you need.
See also the [Configuration Reference](Configuration) and
[docs/ENVIRONMENT_VARIABLES.md](https://github.com/risk-sentinel/sparc/blob/main/docs/ENVIRONMENT_VARIABLES.md).

---

## FIDO2 / WebAuthn security keys

A FIDO2 security key (YubiKey, Feitian, Token2, a platform authenticator, …)
with a PIN is a complete MFA-grade credential: something you have (the key) plus
something you know (the PIN), phishing- and replay-resistant. SPARC supports it
**passwordless** — the key + PIN is the whole login — and it is authenticator
-agnostic (no vendor lock-in; resident and non-resident keys both work).

### Enable it

| Variable | Default | Description |
|----------|---------|-------------|
| `SPARC_FIDO2_ENABLED` | `false` | Turn on security-key enrollment and sign-in |
| `SPARC_FIDO2_RP_NAME` | `SPARC` | Relying-party name the authenticator displays |
| `SPARC_FIDO2_RP_ID` | host of `SPARC_APP_URL` | Override only to scope credentials to a parent domain |
| `SPARC_APP_URL` | `http://localhost:3000` | **Must be the externally-visible URL** — see below |

> **Critical:** `SPARC_APP_URL` must exactly match the origin users' browsers see
> (scheme + host + port), e.g. `https://sparc.example.com`. WebAuthn binds every
> credential to that origin; a mismatch makes enrollment and sign-in fail *only*
> in that environment. Behind a TLS-terminating proxy (caddy / ALB), set it to
> the public HTTPS URL, not the internal one.

Once enabled, users see a **Security Keys** page (account menu) to enroll keys,
and a **Sign in with a security key** button on the login page.

### Recovery

There are **no self-service recovery codes** by design. If a user loses their
key, an instance admin resets it: *Admin → Users → (user) →* **Reset security
keys**, after which the user re-enrolls. Encourage users to register a **backup
key**.

---

## PIV / CAC smart-card sign-in

SPARC accepts a DoD PIV / CAC certificate (cert + card PIN) — delivering **NIST
IA-2(12)**. The trust work happens at the gateway, not in the app:

```mermaid
flowchart LR
    U[Browser: PIV/CAC + PIN] -->|mTLS| G[Proxy / ALB]
    G -->|validates vs DoD PKI + revocation<br/>forwards verified cert| S[SPARC]
    S -->|EDIPI / email → user| Sess[Session]
```

The mutual-TLS handshake, DoD PKI chain validation, and revocation (CRL/OCSP)
are configured on the proxy / ALB — see the deployment playbook in
[risk-sentinel/sparc-iac#559](https://github.com/risk-sentinel/sparc-iac/issues/559).
SPARC consumes the **already-validated** certificate the gateway forwards.

### Enable it

| Variable | Default | Description |
|----------|---------|-------------|
| `SPARC_ENABLE_PIV` | `false` | Accept forwarded, gateway-validated client certs |
| `SPARC_PIV_CERT_HEADER` | `X-SSL-Client-Cert` | Header carrying the PEM (may be URL-encoded) |
| `SPARC_PIV_VERIFY_HEADER` | `X-SSL-Client-Verify` | Header carrying the gateway's verification result |
| `SPARC_PIV_VERIFY_SUCCESS` | `SUCCESS` | The value SPARC requires in the verify header |

SPARC maps a cert to a user by a pre-provisioned PIV identity (the 10-digit
EDIPI) or by the certificate's email. There is no auto-provisioning — a cert
with no matching account is rejected.

### Forwarded certificate formats

HTTP headers cannot contain newlines, so every gateway mangles the PEM in some
way. SPARC reassembles all of the shapes in use, so no extra gateway
configuration is needed:

| Gateway behaviour | Example source |
|---|---|
| URL-encoded PEM (newlines as `%0A`) | nginx `$ssl_client_escaped_cert`, ALB `X-Amzn-Mtls-Clientcert` |
| Newlines folded to spaces or tabs | nginx `$ssl_client_cert` |
| Literal `\n` written into the value | assorted gateways |
| Bare base64 DER, no `BEGIN`/`END` markers | assorted gateways |

### Troubleshooting a failed smart-card sign-in

The two failure messages mean different things, and the audit event for each
carries shape-only diagnostics (`cert_bytes`, `cert_has_pem_markers`,
`cert_url_encoded`, `cert_normalized`) — never the certificate itself:

| Message | Meaning | Where to look |
|---|---|---|
| *Your smart card could not be verified by the gateway.* | The verify header was missing or not `SUCCESS` | Gateway mTLS config; the app never saw a validated cert |
| *No smart card certificate was presented.* | Verify succeeded but the cert header was empty (`cert_bytes: 0`) | Gateway is attesting verification without forwarding the cert |
| *Your smart card certificate could not be read.* | A cert arrived but could not be decoded | Check `cert_bytes` for truncation — headers have size limits |

> **Security — only enable behind a correctly-configured mTLS gateway.** SPARC
> fails closed unless the gateway sets the verify header, and it trusts the
> forwarded headers **only** because the gateway strips any client-supplied
> copies and the app is reachable only through the gateway. Enabling `PIV`
> without that isolation would let a client forge the identity headers.

---

## PIV enforced at the identity provider (#822)

SPARC's `piv` requirement has always meant a gateway terminated mTLS and
forwarded the client certificate. That path is unchanged. It can now **also** be
satisfied by an OIDC token showing the identity provider itself performed
certificate-based authentication — Okta Smart Card, Entra CBA.

### Why an operator would choose it

Gateway mTLS on a shared `:443` listener prompts **every** user for a client
certificate, because the TLS `CertificateRequest` happens before HTTP exists and
cannot be scoped to a path. It also rests on an issuer-DN filter, which cannot
distinguish a hardware-bound PIV credential from an exportable soft certificate
issued by the same CA. An IdP doing CBA enforces chain validation, revocation
and hardware assurance, and states the result in the token.

Both remain configurable, because CAC-direct and no-IdP deployments still need
the gateway path.

### Enabling it

```bash
SPARC_REQUIRE_AUTH_METHODS="piv"
SPARC_PIV_OIDC_AMR_VALUES="x509,hwk"
# or, if your IdP asserts an assurance level instead:
SPARC_PIV_OIDC_ACR_VALUES="http://idmanagement.gov/ns/assurance/aal/3"
```

In Okta this pairs with an authentication policy on the SPARC application that
requires the smart-card / certificate factor.

> **Empty means accept NOTHING, never accept anything.** With neither variable
> set, `piv` continues to mean the forwarded certificate and nothing else. A
> configuration mistake must not silently downgrade an authentication
> requirement, so there is no wildcard and no default value.

### What is and is not checked

- `amr` is a **list** of methods the IdP used; any one matching an accepted value
  is enough.
- `acr` is compared **exactly**. Prefix matching would accept
  `.../assurance/aal/2` for a deployment that asked for `aal/3`.
- Both are matched case-insensitively and trimmed.
- **`swk` (soft key) is not `x509`.** Accepting it would reintroduce the
  soft-certificate gap this exists to close — list only what you mean.

### What it records

The session still records `oidc` as the provider, so the audit trail says how
the person signed in. A separate `piv_asserted_by_idp` event records the claim
and value that satisfied the requirement, which is what an assessor asks for
when they want to know *why* SPARC accepted a login as PIV.

## Compliance

| Control | How SPARC meets it |
|---------|--------------------|
| IA-2(1) / IA-2(2) | App-native MFA via FIDO2 (key + PIN), or OIDC IdP-enforced MFA |
| IA-2(8) | WebAuthn is replay- and phishing-resistant (challenge, origin binding, signature-counter clone detection) |
| IA-2(12) | Native PIV/CAC acceptance |
| IA-5 / IA-5(2) | Authenticator management (enroll/revoke); PKI validation at the gateway |

See the full [NIST SP 800-53 Rev 5 mapping](https://github.com/risk-sentinel/sparc/blob/main/docs/compliance/nist-sp800-53-rev5-mapping.md).

---

## Related pages

- [User Guide: Security Keys & Smart Cards](User-Guide-Security-Keys) — end-user steps.
- [Configuration Reference](Configuration) — all environment variables.
- [RBAC](RBAC) — roles and permissions.
