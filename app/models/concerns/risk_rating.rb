# frozen_string_literal: true

# #1090 — a risk rating, expressed the way OSCAL expresses it.
#
# THE DEFECT THIS CLOSES
#
# `impact` and `likelihood` are columns on both risk models, editable on POA&M
# and (since #1090) on SAR. Neither exporter ever wrote them out: both emitted
# `characterizations_data` and nothing else, so a rating chosen by a person was
# invisible in the exported artifact. Measured on the seeded estate before the
# fix: 6 poam_risks carried an impact and a likelihood, and 0 of 16 carried any
# characterizations — so all six ratings vanished at export.
#
# Worse than absent: a risk IMPORTED with a rating and then re-rated in SPARC
# exported with its ORIGINAL characterizations, so the screen and the artifact
# disagreed with nothing to indicate it.
#
# WHY FACETS
#
# OSCAL carries a risk metric in `characterizations[].facets[]`, never in a
# top-level field. The schema requires `name`, `system` and `value` on every
# facet, and describes `system` as the "Naming System" — the taxonomy the metric
# NAME belongs to, so that the same name can mean different things to different
# parties. It is NOT the assessed system or boundary; that is carried by
# `origins`, `related-observations` and the imported SSP.
#
# The import side has always read facets correctly
# (`extract_facet(risk, "likelihood")`); this is the missing other half.
module RiskRating
  extend ActiveSupport::Concern

  # THE NAMING SYSTEM IS NOT OURS TO INVENT.
  #
  # `system` identifies whose vocabulary the facet NAME belongs to, and each
  # system owns its own values. The OSCAL schema constrains only the `system`
  # enum and `risk-status`; it defines NO vocabulary for facet name or value, so
  # it will validate a wrong pairing silently.
  #
  # That makes hardcoding a system actively harmful. SPARC currently offers
  # `high`/`medium`/`low`, while NIST SP 800-30 and FedRAMP both use a five-level
  # scale (Very Low / Low / MODERATE / High / Very High). Stamping
  # `http://fedramp.gov/ns/oscal` on a facet valued `medium` would assert
  # FedRAMP's vocabulary while emitting a value FedRAMP does not define — a
  # schema-valid lie. See #1090 for the open question on aligning the vocabulary.
  #
  # So:
  #
  #   1. If the risk arrived with facets that already name this metric, the
  #      EXISTING system is kept and its value updated in place. A document
  #      imported as NIST re-exports as NIST; imported as FedRAMP, as FedRAMP.
  #      The round trip preserves the customer's framework rather than
  #      converting it to ours.
  #   2. Only when nothing says otherwise is the configured default used —
  #      `SPARC_OSCAL_RISK_SYSTEM`, defaulting to the generic NIST namespace
  #      because it is the neutral one, and OSCAL's own.
  DEFAULT_RATING_SYSTEM = "http://csrc.nist.gov/ns/oscal"

  # The facets SPARC authors, keyed by column and valued by OSCAL facet name.
  # They match today; naming them here keeps that a decision rather than a
  # coincidence, and is the single place to extend when SPARC models more of the
  # risk metrics OSCAL allows.
  AUTHORED_FACETS = { likelihood: "likelihood", impact: "impact" }.freeze

  # The qualitative scale, in one place. Six copies of `High/Medium/Low` were
  # hardcoded across the POA&M forms and the show page's heat map before this.
  #
  # FIVE levels, because three cannot express the scale NIST SP 800-30 and
  # FedRAMP both work in (Very Low / Low / Moderate / High / Very High). The old
  # three-level set was also worded `medium`, which is not the word either
  # framework uses — `moderate` is. LegacyMedium is migrated in
  # db/migrate/*_normalise_risk_levels.rb.
  #
  # STORED TOKENS are lowercase and hyphenated. The exact spelling ends up in an
  # exported artifact as a facet value, and the authoritative FedRAMP/NIST OSCAL
  # spellings were not verifiable offline when this was written — so it lives in
  # ONE constant, and changing it changes every form, the heat map and the
  # export together. See #1090.
  LEVELS = %w[very-low low moderate high very-high].freeze

  # The human spelling of a stored token: "very-low" -> "Very Low".
  #
  # A method rather than a second literal list, because anywhere that renders a
  # level needs this and `capitalize` is subtly wrong for the hyphenated ones —
  # the POA&M heat map's headers read "Very-low" until #1095.
  def self.level_label(value)
    value.to_s.tr("-", " ").split.map(&:capitalize).join(" ")
  end

  # For `options_for_select`: [label, value].
  LEVEL_OPTIONS = LEVELS.map { |v| [ level_label(v), v ] }.freeze

  # What the old three-level vocabulary maps to.
  LEGACY_LEVELS = { "medium" => "moderate" }.freeze

  def rating_system
    ENV.fetch("SPARC_OSCAL_RISK_SYSTEM", DEFAULT_RATING_SYSTEM).presence || DEFAULT_RATING_SYSTEM
  end

  # What the exporter should emit for `characterizations`.
  #
  # Facets that arrived on import are PRESERVED — a CVSS characterization SPARC
  # does not model must survive a round trip untouched. Ours are merged in by
  # name under our own system, so re-exporting never leaves a stale copy of a
  # rating that has since changed.
  # The actor SPARC attributes a characterization to.
  #
  # A characterization REQUIRES an `origin`, and an origin requires `actors`,
  # each with a `type` of tool|assessment-platform|party and an `actor-uuid`.
  # SPARC is the tool that recorded the rating, so `tool` is the honest type —
  # claiming `party` would assert a person or organisation made the assessment.
  #
  # The uuid is DERIVED, not random, so re-exporting the same document produces
  # the same actor rather than a new one on every download.
  def rating_origin
    {
      "actors" => [
        { "type" => "tool", "actor-uuid" => OscalUuidService.derived("sparc-tool", "risk-characterization") }
      ]
    }
  end

  def characterizations_for_export
    authored = AUTHORED_FACETS.filter_map do |column, facet_name|
      value = public_send(column)
      [ facet_name, value ] if value.present?
    end.to_h

    return characterizations_data.presence if authored.empty?

    existing = Array(characterizations_data).map(&:deep_dup)

    authored.each do |name, value|
      # 1. The metric already exists somewhere — keep ITS characterization and
      #    facet system, and update only the value. A document imported as
      #    FedRAMP re-exports as FedRAMP.
      home = existing.find { |c| Array(c["facets"]).any? { |f| f["name"] == name } }
      if home
        Array(home["facets"]).find { |f| f["name"] == name }["value"] = value
        next
      end

      # 2. Nothing said otherwise — add it to OUR characterization, creating one
      #    if this is the first authored facet.
      target = existing.find { |c| ours?(c) }
      unless target
        target = { "origin" => rating_origin, "facets" => [] }
        existing << target
      end
      target["facets"] = Array(target["facets"]) +
                         [ { "name" => name, "system" => rating_system, "value" => value } ]
    end

    existing
  end

  private

  # Our characterization is the one whose facets carry our naming system. The
  # system lives on the FACET, never on the characterization — the schema has no
  # `system` property there, and putting one on it fails validation.
  def ours?(characterization)
    Array(characterization["facets"]).any? { |f| f["system"] == rating_system } ||
      Array(characterization["facets"]).empty?
  end
end
