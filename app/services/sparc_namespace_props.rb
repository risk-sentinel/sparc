# frozen_string_literal: true

# The nine SPARC-namespace props sparc-horizon reads (#1154).
#
# OSCAL has no native place for a node's position in the federation tree, the
# AO's next decision date, whether a risk blocks the ATO, or what kind of thing
# a piece of evidence is. Every object these land on is `additionalProperties:
# false` in the NIST schema, so `props` is the ONLY legal place for them, and a
# prop outside NIST's namespace is how OSCAL says "this vocabulary is someone
# else's". The vocabulary is defined by the schema vendored at
# lib/data/oscal_ns/sparc-namespace-props.v1.schema.json (Horizon's copy is the
# original; see the provenance sidecar beside it) and enforced on the validated
# export path by SparcNamespacePropsRule.
#
# ── Which namespace, and why it is not SPARC_OSCAL_NS ──────────────────────
#
# These are emitted under the REGISTERED URI, `OscalNamespace.uri(:sparc)`, not
# under `OscalNamespace.instance`. `SPARC_OSCAL_NS` is the deployment's own
# vocabulary ("set it to a URI your organization owns"); these nine names are
# SPARC's product vocabulary, pinned by a `const` in the schema a consumer
# validates with. Emitting them under an operator's override would make every
# one of them invisible to that consumer — the exact failure a namespace exists
# to prevent (see OscalNamespace, "Why this is a constant").
#
# ── Never an invented value ────────────────────────────────────────────────
#
# Every builder here returns only props whose value SPARC actually holds. A
# missing boundary, an uncategorized system, an evidence type with no honest
# mapping: each yields NO prop, never a placeholder that validates.
module SparcNamespaceProps
  NS = OscalNamespace.uri(:sparc)

  NODE_TYPE          = "node-type".freeze
  PARENT_UUID        = "parent-uuid".freeze
  NEXT_DECISION_DATE = "next-decision-date".freeze
  FIPS_199           = "fips-199".freeze
  BLOCKS_ATO         = "blocks-ato".freeze
  EVIDENCE_KIND      = "evidence-kind".freeze
  SIGNED_BY          = "signed-by".freeze
  CONDITION_EXPIRES  = "condition-expires".freeze
  TRIGGER            = "trigger".freeze

  NAMES = [
    NODE_TYPE, PARENT_UUID, NEXT_DECISION_DATE, FIPS_199,
    BLOCKS_ATO, EVIDENCE_KIND, SIGNED_BY, CONDITION_EXPIRES, TRIGGER
  ].freeze

  # The props SPARC DERIVES at each placement. On export these are dropped from
  # any stored/imported props and re-emitted from SPARC's own data, so a stale
  # value carried in from an import (another system's parent, last year's
  # decision date) can never survive beside the current one.
  SSP_METADATA_NAMES = [ NODE_TYPE, PARENT_UUID, FIPS_199, NEXT_DECISION_DATE ].freeze
  PARTY_NAMES        = [ NODE_TYPE ].freeze
  EVIDENCE_NAMES     = [ EVIDENCE_KIND, SIGNED_BY ].freeze
  RISK_COLUMNS = {
    BLOCKS_ATO        => :blocks_ato,
    CONDITION_EXPIRES => :condition_expires,
    TRIGGER           => :reopen_trigger
  }.freeze

  FIPS_199_LEVELS = %w[low moderate high].freeze
  # The schema's own patterns, as Ruby regexes, for the model validations and
  # the import mapping. The exported value is still checked against the schema
  # itself by SparcNamespacePropsRule — these never replace that.
  DATE_PATTERN    = /\A\d{4}-\d{2}-\d{2}\z/
  TRIGGER_PATTERN = /\A(score|blockers)(<|<=|>|>=)[0-9.]+\z/

  # Evidence#evidence_type → the schema's evidence-kind enum. Only the types
  # whose meaning matches an enum value are mapped. `artifact`, `log`,
  # `config_export` and `test_result` have no honest counterpart (a test result
  # is not necessarily HDF, a log is not a report), so they emit no
  # evidence-kind rather than a guess. `hdf-results` has no SPARC evidence type.
  EVIDENCE_KINDS = {
    "signed_statement" => "manual-attestation",
    "screenshot"       => "screenshot",
    "scan_result"      => "scan-report",
    "policy_document"  => "document"
  }.freeze

  extend self

  def prop(name, value) = { "name" => name, "ns" => NS, "value" => value.to_s }

  def ours?(prop, names = NAMES)
    prop.is_a?(Hash) && prop["ns"] == NS && names.include?(prop["name"])
  end

  # `existing` with every contract prop named in `names` removed and `fresh`
  # appended. nil when nothing is left, so a caller can `.compact` the key away
  # rather than emit an empty array (which OSCAL forbids: props is minItems 1).
  def replace(existing, fresh, names:)
    kept = Array(existing).reject { |p| ours?(p, names) }
    (kept + fresh).presence
  end

  # A date as the schema wants it, or nil. Accepts a Date or a YYYY-MM-DD
  # string that is a real calendar date; anything else is not a date SPARC holds.
  def iso_date(value)
    return value.iso8601 if value.is_a?(Date)
    return nil unless value.is_a?(String) && value.match?(DATE_PATTERN)

    Date.iso8601(value).iso8601
  rescue ArgumentError
    nil
  end

  # `fips-199-moderate` (SPARC's stored form), `moderate`, `Moderate` → `moderate`.
  def fips_199_level(value)
    level = value.to_s.strip.downcase.delete_prefix("fips-199-")
    FIPS_199_LEVELS.include?(level) ? level : nil
  end

  # ── SSP metadata ─────────────────────────────────────────────────────────

  # The categorization, highest-authority source first: the boundary's FIPS 199
  # high-water mark (#940), then the SSP's own recorded sensitivity level, then
  # the high-water mark of the SSP's own objectives. The same data the native
  # `security-sensitivity-level` / `security-impact-level` are exported from.
  def fips_199_for(ssp)
    boundary = ssp.authorization_boundary
    candidates = [ boundary&.security_categorization, ssp.security_sensitivity_level ]
    objectives = %i[confidentiality integrity availability].filter_map do |o|
      fips_199_level(ssp.public_send(:"security_objective_#{o}"))
    end
    candidates << objectives.max_by { |l| FIPS_199_LEVELS.index(l) }

    candidates.lazy.filter_map { |c| fips_199_level(c) }.first
  end

  def ssp_metadata_props(ssp)
    boundary = ssp.authorization_boundary
    props = [ prop(NODE_TYPE, "system") ]
    props << prop(PARENT_UUID, boundary.uuid) if boundary&.uuid.present?
    level = fips_199_for(ssp)
    props << prop(FIPS_199, level) if level
    date = iso_date(boundary&.next_decision_date)
    props << prop(NEXT_DECISION_DATE, date) if date
    props
  end

  # What SparcNamespacePropsRule must find on an SSP's metadata. Derived from
  # the facts (is there a boundary, is the system categorized), so an export
  # that dropped or duplicated one is refused rather than published.
  def required_ssp_metadata(ssp)
    boundary = ssp.authorization_boundary
    {
      NODE_TYPE   => "system",
      PARENT_UUID => boundary&.uuid.presence,
      FIPS_199    => fips_199_for(ssp)
    }.compact
  end

  # Adds `metadata.props` to an already-built metadata hash, in place.
  def apply_ssp_metadata!(metadata, ssp)
    props = replace(metadata["props"], ssp_metadata_props(ssp), names: SSP_METADATA_NAMES)
    props ? metadata["props"] = props : metadata.delete("props")
    metadata
  end

  # ── Parties ──────────────────────────────────────────────────────────────

  # `node-type: organization` on the document's organization party — the one
  # `OscalUuidService.org_party_uuid_for` resolves, which is the boundary's
  # Organization when there is one. Only when that party is declared as an
  # organization; an author who re-declared the uuid as something else is not
  # contradicted.
  def tag_organization_party!(metadata, org_party_uuid)
    Array(metadata["parties"]).each do |party|
      next unless party.is_a?(Hash) && party["uuid"] == org_party_uuid && party["type"] == "organization"

      party["props"] = replace(party["props"], [ prop(NODE_TYPE, "organization") ], names: PARTY_NAMES)
    end
    metadata
  end

  # ── Risks ────────────────────────────────────────────────────────────────

  def risk_props(risk)
    props = []
    props << prop(BLOCKS_ATO, risk.blocks_ato.to_s) if risk.respond_to?(:blocks_ato) && !risk.blocks_ato.nil?
    if risk.respond_to?(:condition_expires) && (date = iso_date(risk.condition_expires))
      props << prop(CONDITION_EXPIRES, date)
    end
    props << prop(TRIGGER, risk.reopen_trigger) if risk.respond_to?(:reopen_trigger) && risk.reopen_trigger.present?
    props
  end

  # The risk's stored props with the contract props its COLUMNS own replaced
  # by the column values. Names the model has no column for pass through as
  # issued (a SAR risk carries only blocks-ato).
  def risk_export_props(risk)
    owned = RISK_COLUMNS.select { |_name, column| risk.has_attribute?(column) }.keys
    replace(risk.props_data, risk_props(risk), names: owned)
  end

  # Import: pull the contract props a model has a column for out of `props`
  # into attributes. A value the schema would reject is LEFT in the props as
  # issued rather than dropped or coerced — ingest preserves what the file
  # said (#968), and the validated export then refuses it where a person can
  # see which record is at fault.
  #
  # Returns [attributes, remaining_props].
  def risk_attributes_from(props, model_class)
    attrs = {}
    remaining = Array(props).reject do |p|
      next false unless ours?(p, RISK_COLUMNS.keys)

      column = RISK_COLUMNS.fetch(p["name"])
      next false unless model_class.column_names.include?(column.to_s)

      value = import_value(p["name"], p["value"])
      next false if value.nil?

      attrs[column] = value
      true
    end
    [ attrs, remaining ]
  end

  def import_value(name, raw)
    case name
    when BLOCKS_ATO        then { "true" => true, "false" => false }[raw]
    when CONDITION_EXPIRES then iso_date(raw) && Date.iso8601(raw)
    when TRIGGER           then raw if raw.is_a?(String) && raw.match?(TRIGGER_PATTERN)
    else nil # a name with no column: never imported (risk_attributes_from keeps it in props)
    end
  end

  # ── Evidence (back-matter resources) ─────────────────────────────────────

  def evidence_props(evidence, parties:)
    props = []
    kind = EVIDENCE_KINDS[evidence.evidence_type]
    props << prop(EVIDENCE_KIND, kind) if kind
    signer = signer_party_uuid(evidence, parties)
    props << prop(SIGNED_BY, signer) if signer
    props
  end

  # The party uuid of the evidence's verified attester — but ONLY a party the
  # exporting document actually declares. SPARC users are not OSCAL parties:
  # nothing mints a party per user, so a user's own uuid would be a reference to
  # nothing in the document. A declared party resolves the attester when its
  # uuid IS the user's uuid, or when it is a person whose declared email is the
  # user's (exactly one such party). No match → no signed-by, never an invented
  # uuid.
  def signer_party_uuid(evidence, parties)
    attester = evidence.attestations
                       .select { |a| a.attester_user.present? && a.status == "passed" }
                       .max_by(&:attested_at)&.attester_user
    return nil unless attester

    declared = Array(parties).select { |p| p.is_a?(Hash) && p["uuid"].present? }
    by_uuid = declared.find { |p| p["uuid"] == attester.uuid }
    return by_uuid["uuid"] if by_uuid

    email = attester.email.to_s.downcase
    return nil if email.blank?

    by_email = declared.select do |p|
      p["type"] == "person" && Array(p["email-addresses"]).any? { |e| e.to_s.downcase == email }
    end
    by_email.one? ? by_email.first["uuid"] : nil
  end

  def evidence_resource(resource, evidence, parties:)
    props = replace(resource["props"], evidence_props(evidence, parties: parties), names: EVIDENCE_NAMES)
    props ? resource.merge("props" => props) : resource.except("props")
  end
end
