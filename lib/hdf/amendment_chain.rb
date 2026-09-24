# frozen_string_literal: true

require "json"
require "digest"

module Hdf
  # The hdf-amendments conformance rules SPARC has to satisfy in more than one
  # place: the identity vocabulary, and the tamper-evidence chain.
  #
  # WHY THIS IS SHARED
  #
  # SPARC emits HDF amendments from two independent paths — the release
  # generator (bin/sparc_findings_to_hdf_amendments.rb, from the CVE register)
  # and the API export (HdfAmendmentExportService, from a boundary's finding
  # dispositions). Both had the SAME non-conformant identity mapping, and
  # fixing only the one that happened to be measured first would have left the
  # other emitting documents hdf rejects.
  #
  # The canonicalisation in particular must not be reimplemented per caller: it
  # has to agree byte-for-byte with hdfutil.CanonicalJSON or `hdf amend verify`
  # reports a chain we wrote as BROKEN, which is worse than writing none.
  #
  # NIST SP 800-53 Rev 5: CA-5, RA-5, SI-2, AU-10 (provenance).
  module AmendmentChain
    # The vocabulary hdf-libs enforces for appliedBy.type. Measured against
    # 3.7.0: `username`, `simple` and `other` verify; `name` and `github` — both
    # of which SPARC used to emit — are rejected.
    IDENTITY_TYPES = %w[email username system agent simple other].freeze

    module_function

    # Map a person to a conformant identity.
    #
    #   "@handle"          -> username   (was "github", never in the vocabulary)
    #   "someone@org.gov"  -> email
    #   "Jane Doe"         -> simple     (was "name", also never in it)
    #
    # `simple` rather than `other` for a bare name: `other` is the escape hatch
    # for something the vocabulary cannot express, and a display name is not
    # that. Both verify; this one says more.
    #
    # NOT `system`, even though these documents are machine-written. Upstream
    # stamps `system` on VEX-derived overrides, reasoning that a deterministic
    # mapping is not agent judgment. Ours carry a disposition a PERSON recorded
    # — reviewed_by, decided_by — so `system` would erase real human authority.
    #
    # The identifier keeps its source spelling, @handle and all: it is what the
    # evidence records, and rewriting it would make the amendment disagree with
    # the record it came from.
    def identity_for(who)
      who = who.to_s
      if who.start_with?("@")
        { "type" => "username", "identifier" => who }
      elsif who.include?("@")
        { "type" => "email", "identifier" => who }
      else
        { "type" => "simple", "identifier" => who }
      end
    end

    # A port of hdfutil.CanonicalJSON (hdf-utilities/go/canonicaljson.go).
    #
    # Three details decide whether a chain written here verifies in hdf, and
    # each is a place a reimplementation drifts SILENTLY:
    #
    #   1. object keys sorted by BYTE order
    #   2. null-valued object keys REMOVED — but nulls inside arrays KEPT,
    #      because array position is significant
    #   3. `<`, `>` and `&` escaped as <, >, &. Go's
    #      encoding/json does this by default; Ruby's JSON.generate does not.
    #
    # (3) is the one that bites. Upstream's own chained fixture contains none
    # of those three characters, so a vector test alone cannot catch a missing
    # escape — while SPARC's real amendments contain dozens ("Debian->UBI9",
    # "MEDIUM -> LOW"). Without it every digest would disagree with hdf's.
    #
    # Those characters can only occur inside JSON string values — JSON's own
    # syntax has no use for them — so escaping the generated text is exactly
    # equivalent to escaping each string.
    def canonical_json(value)
      JSON.generate(sort_keys(strip_nulls(value)))
          .gsub("<", "\\u003c")
          .gsub(">", "\\u003e")
          .gsub("&", "\\u0026")
    end

    # Hex-encoded SHA-256 of the canonical form — hdfutil.ChecksumJSON.
    def checksum_json(value)
      Digest::SHA256.hexdigest(canonical_json(value))
    end

    # Mirrors shared.ChainOverrides: stamp previousChecksum in document order,
    # leave the FIRST unlinked, and compute each checksum AFTER its own
    # previousChecksum is set, so each link covers the link before it.
    #
    # Without this, `hdf amend verify` reports "Chain: not established" — which
    # upstream describes as getting "no protection" against an amendment edited
    # in place after the fact.
    #
    # Mutates and returns the array, so a caller can chain the call.
    def chain!(overrides)
      previous = nil
      overrides.each do |override|
        override["previousChecksum"] = previous unless previous.nil?
        previous = { "algorithm" => "sha256", "value" => checksum_json(override) }
      end
      overrides
    end

    def strip_nulls(value)
      case value
      when Hash  then value.reject { |_, v| v.nil? }.transform_values { |v| strip_nulls(v) }
      when Array then value.map { |v| strip_nulls(v) }
      else value
      end
    end

    def sort_keys(value)
      case value
      when Hash  then value.keys.sort_by(&:b).each_with_object({}) { |k, h| h[k] = sort_keys(value[k]) }
      when Array then value.map { |v| sort_keys(v) }
      else value
      end
    end
  end
end
