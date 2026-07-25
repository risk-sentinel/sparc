# PIV / CAC identity mapping — operator guide

**Applies from v1.13.1 (#790).** NIST 800-53 IA-2, IA-2(12), IA-5(2), AC-3, AC-6.

How SPARC turns a smart-card certificate into a signed-in user, and how to make it work
for a non-DoD PKI. Pairs with the transport/mTLS setup in `sparc-iac#559`.

## The trust boundary comes first

SPARC does **not** validate certificates. The mTLS handshake, PKI chain validation, and
revocation checking all happen at the proxy/ALB (sparc-iac). SPARC only consumes the
already-validated certificate the proxy forwards, and it **fails closed** unless the proxy
sets the verify header to the configured success value.

Everything below is about *mapping a trusted cert to an account*. It is only as sound as
that proxy trust boundary — in particular, the proxy's PKI **anchor scoping** decides which
certificates are trusted at all. Get that wrong upstream and no app-layer mapping can save
you.

## How mapping works

1. **Primary identifier.** SPARC reads one field from the certificate, chosen by
   `SPARC_PIV_IDENTITY_SOURCE`, and looks for a provisioned identity with that value
   (`provider: "piv"`, `uid:` = the value).
2. **Email fallback.** If no PIV identity matches *and* `SPARC_PIV_ALLOW_EMAIL_MATCH` is
   true (the default), SPARC matches the certificate's `rfc822Name` SAN against
   `User.email` (case-insensitive).
3. **No auto-creation.** A certificate with no matching account is rejected. Accounts are
   provisioned out of band.
4. The user must be **active**.

## `SPARC_PIV_IDENTITY_SOURCE`

| Value | Field used | For |
|---|---|---|
| `edipi_cn` (default) | The **last dotted segment of the Subject CN**, which must be exactly 10 digits (DoD CAC CN is `LAST.FIRST.MI.EDIPI`) | DoD CAC |
| `upn` | The **PIV UPN** carried in the SAN `otherName`, OID `1.3.6.1.4.1.311.20.2.3` | PIV cards keyed on UPN |
| `email` | The **rfc822Name** SAN | PKIs that identify by email |
| `subject_cn` | The **whole Subject CN** string | Everything else |

The default reproduces exactly the behaviour shipped in #779 — existing DoD deployments
need change nothing.

> **Note on the EDIPI extraction.** It takes the final dotted CN *segment* and requires it
> to be exactly 10 digits. It does **not** scan for "any 10-digit run in the CN" — that
> earlier behaviour could capture the wrong ten digits from a CN carrying another number.

## Non-DoD PKI — a worked example

Say your certificates use `CN=employee-8842` and you want to map on the numeric part:

```
SPARC_ENABLE_PIV=true
SPARC_PIV_IDENTITY_SOURCE=subject_cn
SPARC_PIV_UID_PATTERN=employee-(\d+)
```

Then provision each user's identity so the `uid` matches:

```ruby
Identity.create!(user: user, provider: "piv", uid: "8842")
```

`SPARC_PIV_UID_PATTERN` applies to whichever source you chose. Its first capture group is
the identifier; with no capture group, the whole match is used. It is unnecessary for
`edipi_cn` (which has the 10-digit rule built in) and for sources whose value you want
verbatim.

## High-assurance: require an explicit mapping

The email fallback authenticates **any proxy-trusted cert bearing a matching address**.
That is convenient but leans entirely on the proxy trust boundary. To require an explicit
PIV-identity mapping and refuse email matches:

```
SPARC_PIV_ALLOW_EMAIL_MATCH=false
```

With this set, only a provisioned `provider: "piv"` identity authenticates; a cert whose
only link to an account is a shared email address is rejected.

## Optional: restrict which certs are accepted (#804)

Trust of the client cert lives at the **gateway** — it validates the CA chain (against your
org's, likely self-signed, CA). As **defense-in-depth**, SPARC can additionally require the
forwarded cert to come from a known **issuer** and/or carry a known **certificate-policy
OID**, so a cert from an unexpected issuer/policy is rejected even if the gateway trust store
is broader than intended:

```
SPARC_PIV_ACCEPTED_ISSUERS=ACME Corp PIV CA        # CSV; case-insensitive substring of issuer DN
SPARC_PIV_ACCEPTED_POLICY_OIDS=2.16.840.1.101.3.2.1.3.13   # CSV of certificate-policy OIDs
```

Both empty (default) = accept whatever the gateway forwarded (no behaviour change). When set,
a non-matching cert is rejected fail-closed and audited as a `login_failure`. This is **not**
a substitute for gateway CA trust — it's a second, narrower allowlist on top of it.

## What a certificate must carry

| Source | Required in the cert |
|---|---|
| `edipi_cn` | Subject CN ending in `.<10-digit-EDIPI>` |
| `upn` | SAN `otherName` with OID `1.3.6.1.4.1.311.20.2.3` |
| `email` | SAN `rfc822Name` |
| `subject_cn` | Subject CN |
| Email fallback (any source) | SAN `rfc822Name` matching a `User.email` |

If you issue your own certificates, shape the Subject/SAN to match the source you configure
— a certificate that completes the handshake but carries no field the configured source can
read will authenticate nobody, even though the TLS succeeded.

## Verifying

Provision a test identity, present the card through the gateway, and check the audit log —
a successful PIV login records `action: "login_success", provider: "piv"` with the mapped
identifier. A cert that maps to nobody records a `login_failure` with the reason.
