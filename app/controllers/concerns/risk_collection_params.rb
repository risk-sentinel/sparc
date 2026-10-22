# frozen_string_literal: true

# #1092 — the OSCAL collections a risk carries, as strong-parameter shapes.
#
# `sar_risks` and `poam_risks` both store `threat_ids_data`,
# `mitigating_factors_data`, `origins_data` and `risk_log_data`, both exporters
# EMIT them (oscal_sar_export_service.rb:232-235,
# oscal_poam_export_service.rb:150-155), and the SAR parser POPULATES them on
# import (sar_json_parser_service.rb:190-194). Nothing could author them:
# neither `Api::V1::SarRisks#risk_params` nor `Api::V1::PoamRisks#risk_params`
# permitted one, and `grep -rn "mitigating" app/views app/controllers` returned
# nothing at all. Measured on the demo estate: 0 of 17 SAR risks and 0 of 18
# POA&M risks carried any of them.
#
# For a translation engine that is a one-way street — you can round-trip
# someone else's content but never produce or amend your own.
#
# WHY EXPLICIT KEY LISTS RATHER THAN `permit!`
#
# These are OSCAL objects with defined shapes, not opaque blobs. Permitting the
# real keys keeps anything outside the shape OUT of the jsonb column, where it
# would otherwise sit until it surfaced as a schema-invalid export — the failure
# #1051 is about. It costs a constant per shape and bounds what can be written.
#
# BE PRECISE ABOUT WHAT THAT DOES AND DOES NOT DO. `permit_strictly` raises
# `UnrecognizedFields` for an unknown key at the TOP level of the payload, so
# `sar_risk[threat_ids_dat]` is a 4xx a caller can act on. A key nested INSIDE a
# collection — `threat_ids_data[0][not_an_oscal_key]` — is silently DROPPED by
# strong parameters, not rejected: the request still succeeds and the value
# simply never lands. That is verified rather than assumed (see the
# "does not write a key that is not part of the OSCAL shape" example), and it is
# the reason a caller cannot rely on a 200 meaning every field was stored.
#
# KEYS ARE HYPHENATED because the stored JSON is OSCAL as it arrived: the parser
# writes `risk["threat-ids"]` verbatim, so the hashes hold `implementation-uuid`,
# not `implementation_uuid`. Permitting the snake_case spelling would silently
# drop every value.
module RiskCollectionParams
  extend ActiveSupport::Concern

  # `props` and `links` hang off nearly every OSCAL object.
  PROPS = [ :name, :uuid, :ns, :value, :class, :group, :remarks ].freeze
  LINKS = [ :href, :rel, :"media-type", :"resource-fragment", :text ].freeze

  # threat-id: flat, and `system` + `id` are the required pair.
  THREAT_IDS = [ :system, :href, :id ].freeze

  # mitigating-factor: a described control or circumstance that lowers the risk.
  # This is the one an assessor actually writes by hand.
  MITIGATING_FACTORS = [
    :uuid, :"implementation-uuid", :description,
    { props: PROPS, links: LINKS }
  ].freeze

  # origin: WHO says so. SPARC writes its own for a rating it recorded (see
  # RiskRating#characterizations_for_export); this accepts one that arrived on
  # import, or a correction to it.
  ORIGINS = [
    { actors: [ :type, :"actor-uuid", :"role-id", { props: PROPS, links: LINKS } ] }
  ].freeze

  # risk-log: the history of what was done about the risk. Append-only in
  # spirit, so the UI does not offer it — but an integrator migrating a risk
  # register has to be able to bring one across.
  RISK_LOG = {
    entries: [
      :uuid, :title, :description, :start, :end, :"status-change",
      { "logged-by": [ :"party-uuid", :"role-id" ],
        "related-responses": [ :"response-uuid" ],
        props: PROPS, links: LINKS }
    ]
  }.freeze

  # response/remediation, stored as jsonb on sar_risks only. POA&M models these
  # as real `poam_remediations` rows with their own controller, so this shape is
  # deliberately NOT shared with it.
  REMEDIATIONS = [
    :uuid, :lifecycle, :title, :description,
    { props: PROPS, links: LINKS,
      origins: [ { actors: [ :type, :"actor-uuid", :"role-id" ] } ],
      "required-assets": [ :uuid, :title, :description ] }
  ].freeze

  # OSCAL's allowed values for a response's `lifecycle`. The POA&M remediation
  # form and the SAR risk card both offer exactly these.
  REMEDIATION_LIFECYCLES = %w[recommendation planned completed].freeze

  # What the web forms edit, per collection. A form row carries only these
  # keys; everything else a stored entry holds (props, links, origins,
  # required-assets, an href) is kept, so saving a form never strips content
  # that arrived on import or through the API.
  FORM_FIELDS = {
    threat_ids_data:         %w[system id],
    mitigating_factors_data: %w[description],
    remediations_data:       %w[title description lifecycle]
  }.freeze

  class FormRowInvalid < ArgumentError; end

  # OSCAL's URIDatatype pattern. A threat-id's `id` is a URI, not a bare code:
  # `T1078` exports schema-invalid; `https://attack.mitre.org/techniques/T1078`
  # does not.
  URI_PATTERN = /\A[a-zA-Z][a-zA-Z0-9+\-.]+:.+\z/

  # The nested filters both risk controllers share.
  def risk_collection_filters
    {
      threat_ids_data: THREAT_IDS,
      mitigating_factors_data: MITIGATING_FACTORS,
      origins_data: ORIGINS,
      risk_log_data: RISK_LOG
    }
  end

  private

  # #1092, v1.17.2 — a web form's risk collections, made safe to store. One
  # definition for the SAR risk card and the POA&M risk form.
  #
  # DELETION. An absent key means "unchanged" to `update`, so removing the last
  # row would silently leave the old value in place. The forms emit
  # `collections_present`, so an absent collection alongside it means EMPTY.
  #
  # UUIDs. OSCAL requires one on every mitigating-factor and response, and it is
  # not the operator's business to type it. A row cloned from a <template>
  # carries none, so it is minted here; an existing entry keeps its own.
  #
  # NOTHING STRIPPED. A row the form rendered from a stored entry is matched
  # back to that entry (by uuid, or by system and id for a threat-id), and only
  # the fields the form edits are replaced.
  #
  # REFUSED, not repaired: a remediation with a title but no description (or
  # the reverse), and a threat-id whose `id` is not a URI. OSCAL requires both,
  # and the alternative is storing content that exports schema-invalid, or
  # completing it with invented text. FormRowInvalid carries a message for the
  # operator.
  def normalise_form_risk_collections(attrs, record:, collections:)
    attrs = attrs.to_h.symbolize_keys
    present = attrs.delete(:collections_present).present?

    collections.each do |key|
      attrs[key] ||= [] if present
      next unless attrs.key?(key)

      stored = Array(record&.public_send(key)).map { |entry| entry.to_h.stringify_keys }
      rows = Array(attrs[key]).map { |row| row.to_h.stringify_keys }
      attrs[key] = send(:"normalise_#{key}", rows, stored)
    end

    attrs
  end

  def normalise_threat_ids_data(rows, stored)
    rows.reject { |t| t["system"].blank? && t["id"].blank? }.map do |row|
      unless row["id"].to_s.match?(URI_PATTERN) && row["system"].to_s.match?(URI_PATTERN)
        raise FormRowInvalid, "A threat ID needs its system and its ID as full URIs " \
                              "(for example https://attack.mitre.org/techniques/T1078), " \
                              "not \"#{row["id"].presence || row["system"]}\"."
      end
      match = stored.find { |t| t["system"] == row["system"] && t["id"] == row["id"] }
      (match || {}).merge(row.slice(*FORM_FIELDS[:threat_ids_data]))
    end
  end

  def normalise_mitigating_factors_data(rows, stored)
    rows.reject { |f| f["description"].blank? }.map { |row| merge_by_uuid(row, stored, :mitigating_factors_data) }
  end

  def normalise_remediations_data(rows, stored)
    rows.reject { |r| r["title"].blank? && r["description"].blank? }.map do |row|
      if row["title"].blank? || row["description"].blank?
        raise FormRowInvalid, "A remediation needs both a title and a description " \
                                 "(\"#{row["title"].presence || row["description"]}\")."
      end
      row["lifecycle"] = REMEDIATION_LIFECYCLES.first unless REMEDIATION_LIFECYCLES.include?(row["lifecycle"])
      merge_by_uuid(row, stored, :remediations_data)
    end
  end

  def merge_by_uuid(row, stored, key)
    match = row["uuid"].present? ? stored.find { |entry| entry["uuid"] == row["uuid"] } : nil
    (match || {}).merge(row.slice(*FORM_FIELDS[key]))
                 .merge("uuid" => row["uuid"].presence || SecureRandom.uuid)
  end
end
