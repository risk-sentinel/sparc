# frozen_string_literal: true

# OSCAL property namespaces (#1106).
#
# An OSCAL `ns` declares WHO DEFINES the meaning of a property name — it is not a
# locator and not a per-deployment address. NIST states the rule plainly:
#
#   "When a `ns` is not provided, its value should be assumed to be
#    http://csrc.nist.gov/ns/oscal and the name should be a name defined by the
#    associated OSCAL model."
#
# So emitting a prop with no `ns` is a CLAIM that NIST defined it. SPARC made
# that claim falsely 13 times (see docs/dev/1106_oscal_conformance_audit.md);
# `deferred` shipped inside NIST's namespace for months while schema validation
# reported PASSED, because prop values are Metaschema constraints and JSON Schema
# cannot see them.
#
# ── Why this is a constant and not a per-tenant setting ─────────────────────
#
# A namespace identifies an authority's vocabulary, so it must be IDENTICAL in
# every deployment. NIST uses csrc.nist.gov/ns/oscal, FedRAMP uses
# fedramp.gov/ns/oscal — neither varies by who runs the software. If SPARC
# derived its namespace from something per-install, two instances would emit
# `sparc-status` under different namespaces, the same name would formally mean
# different things, and nothing could recognise SPARC's vocabulary generically —
# which would break authoritative federation (#372) and the CDEF browser (#887).
#
# The DEPLOYMENT's own vocabulary is a separate thing, and it belongs to the
# operators who manage ODPs, mappings and converters after import. That is
# `SparcConfig.oscal_namespace`, and it defaults to SPARC's own entry here.
class OscalNamespace
  # NIST's namespace is IMPLICIT: a prop in it carries no `ns` at all. Emitting
  # it explicitly is legal but noisy, and it is not what NIST's own catalogs do.
  OSCAL = "http://csrc.nist.gov/ns/oscal"

  # The namespaces SPARC itself emits into. A closed set on purpose — anything
  # an operator defines locally goes under SparcConfig.oscal_namespace, not here.
  REGISTRY = {
    # NIST publishes under TWO namespaces. Its own 800-53 catalog emits `method`,
    # `implementation-level`, `contributes-to-assurance` and `aggregates` under
    # /ns/rmf, NOT /ns/oscal — so "NIST" is not one URI.
    oscal: OSCAL,
    rmf: "http://csrc.nist.gov/ns/rmf",
    fedramp: "http://fedramp.gov/ns/oscal",
    cci: "http://cyber.mil/cci",
    stig: "https://public.cyber.mil/stigs/",
    cis: "https://www.cisecurity.org/cis-benchmarks",
    aws: "http://aws.amazon.com/ns/oscal",
    # SPARC's product vocabulary. NOT `sparc.local` — `.local` is reserved for
    # mDNS (RFC 6762): unresolvable, unownable, and it shipped in every exported
    # artifact as SPARC's identity.
    sparc: "https://sparc.risk-sentinel.org/ns"
  }.freeze

  class UnknownNamespace < StandardError; end

  class << self
    # Raises rather than returning nil: a typo'd key would otherwise emit a prop
    # with `"ns" => nil`, which serialises as NIST's namespace — silently turning
    # a namespaced prop into a false claim on NIST. That is the exact defect this
    # class exists to remove.
    def uri(key)
      REGISTRY.fetch(key.to_sym) do
        raise UnknownNamespace, "unknown OSCAL namespace #{key.inspect} " \
                                "(known: #{REGISTRY.keys.join(', ')})"
      end
    end

    # The vocabulary this deployment defines locally. Props under it are never
    # conformance violations — SPARC validates claims about OTHER authorities'
    # vocabularies, it does not police the operator's own.
    def instance = SparcConfig.oscal_namespace

    def known?(uri) = REGISTRY.value?(uri) || uri == instance

    # True when a prop belongs to NIST — i.e. it carries no `ns`, or carries
    # NIST's explicitly. These are the props whose NAMES and VALUES must come
    # from NIST's vocabulary for the document's OSCAL version.
    def nist?(ns) = ns.blank? || ns == OSCAL
  end
end
