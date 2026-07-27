<!-- markdownlint-disable MD013 -->
# Both-directions TLS verification testing (#783)

> **Audience: SPARC maintainers.** This is the **standard** for testing any TLS
> or MITM-relevant surface. Adopted in #783, seeded by the v1.12.3 outbound-TLS
> cluster (#773 / #774 / #775).

## The rule

**Every TLS surface must be proven in BOTH directions, with a real handshake:**

| Direction | Assertion |
|---|---|
| **Negative** (write this **first**) | An **untrusted** certificate is **REJECTED** |
| **Positive** | A **trusted** certificate is **ACCEPTED** |

A test that only proves the positive direction says nothing about security. A
stack that accepts *any* certificate passes every functional test while being
wide open to an on-path attacker — that is exactly the #773 bug, and it shipped.

## Why configuration assertions are not enough

`spec/lib/sparc_http_spec.rb` and `spec/services/ldap_auth_service_spec.rb` assert
that `verify_mode: OpenSSL::SSL::VERIFY_PEER` is passed to `Net::HTTP.start` /
`Net::LDAP.new`. Those are **configuration** assertions. They are worth keeping —
they are fast and they pin the contract — but they can only prove we *said* the
right thing, never that the stack *did* it. Concretely, they cannot catch:

- a library that ignores or overrides the option,
- an `SSLContext` whose `verify_hostname` is off, so any certificate from the
  same CA impersonates any host (the private-PKI failure mode),
- a trust store that was widened rather than extended,
- a code path that never reaches the configured client at all.

Only a handshake against a server holding a certificate we did **not** trust can
distinguish "verifies" from "claims to verify".

## The pattern

`spec/support/tls_test_server.rb` provides the infrastructure. It builds two
independent in-test CAs and serves real TLS on an ephemeral port:

- `TlsTestServer.trusted_ca` — issues the leaf the client is told to trust.
- `TlsTestServer.rogue_ca` — a perfectly well-formed CA that nobody installed;
  the stand-in for an on-path interceptor.
- `TlsTestServer.https(ca:, body:, sans:)` — an HTTPS listener.
- `TlsTestServer.ldaps(ca:, starttls:, sans:)` — an LDAP listener that answers
  bind + search, optionally negotiating StartTLS first.

**WEBrick is not a default gem in Ruby 3.4**, so these are raw
`OpenSSL::SSL::SSLSocket` servers over `TCPServer` rather than a toy HTTPS
server. Nothing extra to add to the Gemfile.

```ruby
# NEGATIVE — write this one first, and watch it fail before the fix exists.
it "REJECTS an untrusted server certificate" do
  TlsTestServer.https(ca: TlsTestServer.rogue_ca) do |server|
    expect { SparcHttp.get(server[:uri]) }
      .to raise_error(OpenSSL::SSL::SSLError, /certificate verify failed/i)
  end
end

# POSITIVE — one variable changes: which CA signed the leaf.
it "ACCEPTS a trusted server certificate" do
  TlsTestServer.https(ca: TlsTestServer.trusted_ca) do |server|
    response = SparcHttp.start(server[:uri], ca_file: server[:ca_file]) { |h| h.request(...) }
    expect(response.code).to eq("200")
  end
end
```

### Change exactly one variable

The negative and positive cases must differ **only** in trust. Same code path,
same listener plumbing, same hostname, same port allocation strategy. Otherwise a
green negative might just mean the server was unreachable — a test that passes
for the wrong reason is worse than no test, because it reads as coverage.

Where practical, add an explicit **control**: show the *same* rogue server is
reachable and answers normally once verification is turned off. That converts
"it failed" into "it failed *because of certificate verification*".

### Give the negative teeth

**Before committing, break the code and confirm the negative goes red.** Flip
`VERIFY_PEER` to `VERIFY_NONE` in the implementation, run the spec, confirm every
negative fails, then revert. A negative test that passes against a deliberately
broken implementation is decoration.

Verified for #783:

| Mutation | Negatives that went red |
|---|---|
| `app/lib/sparc_http.rb` → `VERIFY_NONE` | 3 of 3 |
| `app/services/ldap_auth_service.rb` → `VERIFY_NONE` | 3 of 3 |

### Cover hostname verification, not just the chain

Under a private/enterprise PKI the CA signs certificates for many hosts, so chain
validation alone lets any certificate holder impersonate any host. Assert that a
leaf issued **by the trusted CA for a different hostname** is still rejected. Both
`SparcHttp` and `LdapAuthService` are pinned this way.

### Test the trust mechanism operators actually use

`OpenSSL` reads `SSL_CERT_FILE` once, when it builds `SSLContext::DEFAULT_CERT_STORE`
at load time. Setting that variable inside a running example has **no effect** —
a spec written that way fails and looks like a product bug. The custom-CA
examples (#774) therefore drive the real `bin/lib/ca-trust.sh` to assemble the
bundle and then fetch in a **child process** with `SSL_CERT_FILE` set, which is
exactly what the container entrypoint does before Ruby boots.

## Coverage

| Vector | Spec |
|---|---|
| Outbound HTTP — covers OIDC discovery/JWKS, federation pull, AWS Labs CDEF, MITRE config, AWS Security Hub, since all route through `SparcHttp` (#775) | `spec/lib/sparc_http_tls_spec.rb` |
| LDAP `simple_tls` + `start_tls`, and the `SPARC_LDAP_TLS_VERIFY=false` opt-out (#773) | `spec/services/ldap_auth_service_tls_spec.rb` |
| Custom-CA trust via `bin/lib/ca-trust.sh` (#774) | `spec/lib/sparc_http_tls_spec.rb` |
| Inbound TLS fail-closed (deployed instance) | `tests/ui-smoke/test_tls_verification.py` |

## When you add an outbound client

Route it through `SparcHttp` — it is already covered. If a surface genuinely
cannot use `SparcHttp` (a gem with its own transport, say), it needs its own
both-directions spec before it ships.

NIST: SC-8 (transmission confidentiality & integrity), SC-12, SC-13, SC-23,
IA-2, IA-5.
