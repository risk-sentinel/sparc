# frozen_string_literal: true

# #935 — work out which compliance framework a catalog or baseline belongs to,
# once, at import.
#
# Framework is not a field. In the NIST catalogs SPARC holds it exists only as
# prose and filename:
#
#   title    "Electronic (OSCAL) Version of NIST Special Publication 800-53 ..."
#   version  5.2.0
#   props    ["resolution-tool"]        <- the only prop
#
# So it has to be derived. Deriving it **at request time by regexing titles was
# rejected deliberately** when this was cut from #908: a catalog whose title
# convention differs would be labelled with the wrong framework, and in a
# compliance tool confidently displaying a wrong framework is worse than
# offering no filter at all.
#
# Hence: derive once, persist, and make the rule a named unit with its own
# tests, so adding a framework is a data change rather than an archaeology
# exercise.
#
# ── The rule ───────────────────────────────────────────────────────────────
#
# Signals are consulted strongest-first, and the first confident answer wins:
#
#   1. An explicit `source` on the catalog ("FedRAMP 20x"). Someone stated it.
#   2. The control-id namespace. `ksi-auth-01` is a FedRAMP 20x KSI; `ac-2` is
#      an 800-53 family. This is structural, not prose, so it survives a
#      retitled catalog.
#   3. The title, then the filename — prose, and the weakest evidence, which is
#      why they are last.
#   4. For a baseline, the catalog it descends from, consulted FIRST, because
#      lineage is a statement of fact rather than an inference from a string.
#
# **Nil when nothing says clearly.** A null renders as "Unspecified" and is
# honest; a guess is not. `Demo LOW Baseline` on the dev estate names no
# framework and links to no catalog, and it is meant to come back nil.
class FrameworkDeriver
  NIST_800_53 = "NIST SP 800-53"
  FEDRAMP_20X = "FedRAMP 20x"

  # Explicit vocabulary. Adding a framework means adding a row here and a test,
  # not editing a regex buried in a query.
  SOURCE_RULES = [
    [ /fedramp\s*20x/i, FEDRAMP_20X ]
  ].freeze

  # Structural: the identifier namespace a control uses.
  CONTROL_ID_RULES = [
    [ /\Aksi[-.]/i, FEDRAMP_20X ]
  ].freeze

  # The twenty NIST SP 800-53 Rev 5 families. Matching on the family set rather
  # than one control keeps a lone `ac-1` in some other framework's catalog from
  # claiming the whole catalog.
  NIST_FAMILIES = %w[ac at au ca cm cp ia ir ma mp pe pl pm ps pt ra sa sc si sr].freeze

  TEXT_RULES = [
    [ /fedramp\s*20x/i,          FEDRAMP_20X ],
    [ /\b800[-\s]?53\b/i,        NIST_800_53 ],
    [ /special\s+publication\s+800[-\s]?53/i, NIST_800_53 ]
  ].freeze

  class << self
    # A catalog states its own framework, or its controls do, or its title does.
    def for_catalog(catalog)
      return nil if catalog.nil?

      from_source(catalog.source) ||
        from_control_ids(catalog_control_ids(catalog)) ||
        from_text(catalog.name) ||
        from_text(catalog.original_filename)
    end

    # A baseline inherits from the catalog it resolves against — lineage is a
    # fact, so it outranks every inference from this document's own strings.
    def for_profile(profile)
      return nil if profile.nil?

      from_catalog_lineage(profile) ||
        from_control_ids(profile_control_ids(profile)) ||
        from_text(profile.name) ||
        from_text(profile.original_filename)
    end

    private

    def from_catalog_lineage(profile)
      return nil unless profile.respond_to?(:control_catalog)

      catalog = profile.control_catalog
      catalog && for_catalog(catalog)
    end

    def from_source(value)
      return nil if value.blank?

      SOURCE_RULES.each { |pattern, framework| return framework if value.match?(pattern) }
      nil
    end

    def from_text(value)
      return nil if value.blank?

      TEXT_RULES.each { |pattern, framework| return framework if value.match?(pattern) }
      nil
    end

    # Decided by what the identifiers ARE, so a retitled or re-sourced catalog
    # still resolves. A namespace match wins outright; the NIST families need a
    # majority, because one `ac-1` proves nothing about a catalog of something
    # else.
    def from_control_ids(ids)
      ids = Array(ids).compact.map { |id| id.to_s.downcase }
      return nil if ids.empty?

      CONTROL_ID_RULES.each do |pattern, framework|
        return framework if ids.any? { |id| id.match?(pattern) }
      end

      families = ids.filter_map { |id| id[/\A([a-z]{2})[-.]/, 1] }
      return nil if families.empty?

      nist = families.count { |f| NIST_FAMILIES.include?(f) }
      nist * 2 > families.size ? NIST_800_53 : nil
    end

    # Bounded: enough identifiers to judge a namespace, not a full table scan on
    # a 1,189-control catalog every time a row is saved.
    def catalog_control_ids(catalog)
      return [] unless catalog.respond_to?(:catalog_controls) && catalog.persisted?

      catalog.catalog_controls.limit(50).pluck(:control_id)
    end

    def profile_control_ids(profile)
      return [] unless profile.respond_to?(:profile_controls) && profile.persisted?

      profile.profile_controls.limit(50).pluck(:control_id)
    end
  end
end
