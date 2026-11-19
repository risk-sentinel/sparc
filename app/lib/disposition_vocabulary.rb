# frozen_string_literal: true

# #1368 — one definition of how a finding disposition is said in HDF and in
# NIST OSCAL. Read by the model's validations, the triage form, the API, the
# HDF amendments export and the OSCAL POA&M export.
#
# Sources, at the versions SPARC pins:
#   * HDF: hdf-libs v3.8.0, `hdf-amendments.schema.json` — Override_Type
#     (waiver attestation poam inherited falsePositive riskAdjustment
#     operationalRequirement), POAM type (remediation mitigation
#     riskAcceptance vendorDependency).
#   * NIST: OSCAL v1.2.3, `oscal_assessment-common_metaschema.xml` — the
#     allowed values of risk/status, the risk prop names, risk/response
#     `type` and lifecycle, risk-log entry `type`, and facet `state`.
# spec/lib/disposition_vocabulary_spec.rb checks every value here against
# those sources (fixtures with provenance, and the vendored OSCAL schema).
#
# The per-kind NIST response and risk-log types are SPARC's fixed table
# (owner, 2026-11-18); making them configurable is #1376.
module DispositionVocabulary
  # NIST OSCAL v1.2.3 — the values a user picks on every disposition.
  RISK_PROPS = %w[false-positive accepted risk-adjusted].freeze
  RISK_STATUSES = %w[open investigating remediating deviation-requested deviation-approved closed].freeze
  RESPONSE_LIFECYCLES = %w[recommendation planned completed].freeze
  FACET_STATES = %w[initial adjusted].freeze

  # NIST OSCAL v1.2.3 — the full vocabularies the table below draws from.
  RESPONSE_TYPES = %w[avoid mitigate transfer accept share contingency none].freeze
  RISK_LOG_ENTRY_TYPES = %w[
    vendor-check-in status-update milestone-complete mitigation remediated closed
    dr-submission dr-updated dr-approved dr-rejected
  ].freeze

  # HDF v3.8.0.
  HDF_OVERRIDE_TYPES = %w[waiver attestation poam inherited falsePositive riskAdjustment operationalRequirement].freeze

  # NIST SP 800-30 Rev. 1's five-level scale (Tables G-5, H-3, I-3), used for
  # the NIST-namespace likelihood, impact and risk facets. OSCAL v1.2.3 names
  # those facets but leaves their values open; SPARC holds them to this scale
  # (owner, 2026-11-19). The user picks likelihood and impact; risk is derived.
  # The same five tokens POA&M and SAR risk ratings use (RiskRating::LEVELS,
  # #1090): one scale across SPARC.
  LEVELS = RiskRating::LEVELS

  # SP 800-30 Rev. 1, Table I-2 — level of risk from likelihood (the key) and
  # impact (the position in each row, in LEVELS order). Read from NIST's
  # published PDF (nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-30r1.pdf,
  # page I-1) on 2026-11-19.
  RISK_TABLE = {
    "very-high" => %w[very-low low moderate high very-high],
    "high"      => %w[very-low low moderate high very-high],
    "moderate"  => %w[very-low low moderate moderate high],
    "low"       => %w[very-low low low low moderate],
    "very-low"  => %w[very-low very-low very-low low low]
  }.freeze

  # The facet system NIST's own vocabulary lives under.
  NIST_FACET_SYSTEM = RiskRating::DEFAULT_RATING_SYSTEM

  def self.risk_level(likelihood, impact)
    RISK_TABLE.fetch(likelihood).fetch(LEVELS.index(impact) || raise(KeyError, "impact #{impact.inspect}"))
  end

  # NIST does not define a value for the risk props, only their names; this is
  # FedRAMP's convention for the same props (owner, 2026-11-18).
  RISK_PROP_VALUE = "yes"

  # The deviation kinds: their risk-log follows the approval (dr-submission,
  # then dr-approved / dr-rejected).
  DEVIATION_LOG = :deviation

  Mapping = Struct.new(:hdf_override_type, :hdf_status, :response_type, :risk_log, keyword_init: true)

  # kind => how it is said in HDF and NIST. `hdf_status` nil means the override
  # carries no status (hdf-cli 3.8.0: riskAdjustment re-rates `impact`;
  # operationalRequirement carries neither).
  MAPPINGS = {
    "falsePositive"          => Mapping.new(hdf_override_type: "falsePositive", hdf_status: "notApplicable",
                                            response_type: "none", risk_log: DEVIATION_LOG),
    "waiver"                 => Mapping.new(hdf_override_type: "waiver", hdf_status: "notApplicable",
                                            response_type: "accept", risk_log: DEVIATION_LOG),
    "operationalRequirement" => Mapping.new(hdf_override_type: "operationalRequirement", hdf_status: nil,
                                            response_type: "accept", risk_log: DEVIATION_LOG),
    "riskAdjustment"         => Mapping.new(hdf_override_type: "riskAdjustment", hdf_status: nil,
                                            response_type: "mitigate", risk_log: DEVIATION_LOG),
    "poam"                   => Mapping.new(hdf_override_type: "poam", hdf_status: "failed",
                                            response_type: "mitigate", risk_log: "status-update"),
    # A POA&M type in HDF, not an override type: exported as a `poam` override.
    "vendorDependency"       => Mapping.new(hdf_override_type: "poam", hdf_status: "failed",
                                            response_type: "transfer", risk_log: "vendor-check-in"),
    "inherited"              => Mapping.new(hdf_override_type: "inherited", hdf_status: "notApplicable",
                                            response_type: "share", risk_log: "status-update"),
    "attestation"            => Mapping.new(hdf_override_type: "attestation", hdf_status: "passed",
                                            response_type: "none", risk_log: "status-update")
  }.freeze

  KINDS = MAPPINGS.keys.freeze

  def self.for(kind)
    MAPPINGS.fetch(kind)
  end

  # The NIST risk-log entry types a disposition writes, in order.
  def self.risk_log_types(kind, approval_status)
    log = self.for(kind).risk_log
    return [ log ] unless log == DEVIATION_LOG

    case approval_status
    when "approved" then %w[dr-submission dr-approved]
    when "rejected" then %w[dr-submission dr-rejected]
    else %w[dr-submission]
    end
  end
end
