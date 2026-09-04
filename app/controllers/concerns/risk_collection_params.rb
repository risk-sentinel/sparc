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

  # The nested filters both risk controllers share.
  def risk_collection_filters
    {
      threat_ids_data: THREAT_IDS,
      mitigating_factors_data: MITIGATING_FACTORS,
      origins_data: ORIGINS,
      risk_log_data: RISK_LOG
    }
  end
end
