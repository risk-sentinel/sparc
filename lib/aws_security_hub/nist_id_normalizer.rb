# frozen_string_literal: true

# Issue #491 — normalize NIST control identifiers between MITRE-style
# uppercase paren notation (`AC-2(1)`, `AC-2(j)`, `IA-5(1)(a)(d)(e)`) and
# OSCAL/SPARC lowercase notation (`ac-2.1`, `ac-2_smt.j`).
#
# MITRE's AwsConfigMappingData encodes three patterns:
#
#   AC-3                bare control
#   AC-2(1)             enhancement (numeric in parens)
#   AC-2(j)             statement subpart (lowercase letter in parens)
#   IA-5(1)(a)(d)(e)    enhancement + multiple expanded subparts
#
# OSCAL/SPARC canonical:
#
#   ac-3                bare control
#   ac-2.1              enhancement -> `.<n>`
#   ac-2_smt.j          subpart -> `_smt.<letter>`
#
# Composite forms expand into multiple OSCAL IDs (one per subpart letter).
#
# This is rev-agnostic notation: the same bare/enhancement/subpart IDs are
# valid in both NIST SP 800-53 rev4 and rev5. The semantic remapping of
# subpart letters between revisions (which is what actually differs) is
# handled separately via a curated transform table -- see #491.
module AwsSecurityHub
  module NistIdNormalizer
    module_function

    # Convert a MITRE-style id like "AC-2(1)" or "IA-5(1)(a)(d)" to one or
    # more OSCAL ids. Returns an Array<String> (multiple when subparts
    # are expanded).
    #
    # Returns [] on unparseable input rather than raising -- the upstream
    # mapping is third-party data we periodically re-vendor; one bad row
    # should not blow up the entire seed.
    def normalize(mitre_id)
      return [] if mitre_id.nil? || mitre_id.strip.empty?

      # Capture the family/number stem (e.g., "AC-2") and any paren tokens.
      match = mitre_id.strip.match(/\A([A-Z]{2})-(\d+)((?:\([^)]+\))*)\z/)
      return [] unless match

      family    = match[1].downcase
      number    = match[2]
      paren_str = match[3] || ""

      stem = "#{family}-#{number}"

      tokens = paren_str.scan(/\(([^)]+)\)/).flatten
      return [ stem ] if tokens.empty?

      # Split tokens into enhancement (digits) vs subpart (single lowercase letter).
      # Anything else is logged-and-skipped.
      enhancement_token = nil
      subpart_letters   = []

      tokens.each do |token|
        case token
        when /\A\d+\z/
          # First enhancement token wins; trailing digit tokens are unusual
          # in MITRE data and treated as malformed.
          enhancement_token ||= token
        when /\A[a-z]\z/
          subpart_letters << token
        else
          # Skip unrecognized tokens (e.g., multi-letter or mixed).
        end
      end

      base = enhancement_token ? "#{stem}.#{enhancement_token}" : stem

      if subpart_letters.empty?
        [ base ]
      else
        subpart_letters.map { |letter| "#{base}_smt.#{letter}" }
      end
    end

    # Convenience: flatten an array of MITRE ids into a deduplicated,
    # ordered array of OSCAL ids.
    def normalize_all(mitre_ids)
      Array(mitre_ids).flat_map { |id| normalize(id) }.uniq
    end

    # Inverse-direction helper for reading rev5 transforms or constructing
    # display strings. Not used by the seed pipeline directly.
    def to_oscal_lowercase(id)
      id.to_s.downcase
    end
  end
end
