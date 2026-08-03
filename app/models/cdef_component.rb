# #887 — a single component inside a CDEF, denormalized so the browser can
# filter on dimensions that are otherwise scattered across the OSCAL document
# (and, for regions, across a second document entirely).
#
# Derived data only. Nothing here is authored by a user, so it is always safe
# to rebuild from the source CDEF — see CdefComponentIndexer.
class CdefComponent < ApplicationRecord
  belongs_to :cdef_document

  # AWS partitions. Derived from the region-id prefix rather than declared:
  # the regions CDEF carries only `region-id`, no partition property.
  PARTITION_GOV = "aws-us-gov".freeze
  PARTITION_CN  = "aws-cn".freeze
  PARTITION_STD = "aws".freeze

  # Deployment scope, as AWS spells it in `props[name=availability]`.
  AVAILABILITY_SCOPES = %w[REGIONAL ZONAL SUBZONAL GLOBAL].freeze

  # ── Functional capability (#887) ──────────────────────────────────────────
  #
  # "What does this component do?" — an Okta CDEF should be findable as MFA.
  # This is NOT the OSCAL `capabilities` construct, which is absent from every
  # upstream AWS file and would stay permanently empty.
  #
  # Derivation is deliberately a small, explicit control-id map rather than
  # text matching on titles or descriptions. Guessing "MFA" from prose would
  # manufacture claims about compliance coverage; deriving it from the controls
  # a component actually covers is traceable back to a specific control id.
  #
  # An org CDEF that declares `props[name=capability]` gets that verbatim and
  # does not depend on this map at all — which is how custom content gets the
  # same searchable fields as the AWS corpus.
  CAPABILITY_CONTROL_MAP = {
    "MFA"                      => %w[IA-2(1) IA-2(2) IA-2(6) IA-2(8) IA-2(11) IA-2(12)],
    "Identity and Access"      => %w[AC-2 AC-3 AC-6 IA-2 IA-4 IA-5],
    "Encryption at Rest"       => %w[SC-28 SC-28(1)],
    "Encryption in Transit"    => %w[SC-8 SC-8(1)],
    "Audit Logging"            => %w[AU-2 AU-3 AU-6 AU-9 AU-12],
    "Backup and Recovery"      => %w[CP-9 CP-10],
    "Vulnerability Management" => %w[RA-5 SI-2],
    "Network Protection"       => %w[SC-7 SC-7(3) SC-5],
    "Configuration Management" => %w[CM-2 CM-3 CM-6 CM-7],
    "Continuous Monitoring"    => %w[CA-7 SI-4]
  }.freeze

  validates :component_uuid, presence: true,
            uniqueness: { scope: :cdef_document_id }

  scope :services, -> { where(component_type: "service") }
  scope :with_checks, -> { where(has_checks: true) }
  scope :in_partition, ->(p) { where("partitions && ARRAY[?]::varchar[]", Array(p)) }
  scope :in_region,    ->(r) { where("region_ids && ARRAY[?]::varchar[]", Array(r)) }

  # Control coverage is asked in two different ways and they are NOT the same
  # question. `covering_control` matches only what the upstream author asserted;
  # `covering_control_including_derived` also matches what SPARC inferred.
  # Keeping them separate is what stops a derived mapping being read as an
  # upstream assertion.
  scope :covering_control, ->(id) {
    where("native_control_ids && ARRAY[?]::varchar[]", Array(id).map { |c| c.to_s.upcase })
  }
  scope :covering_control_including_derived, ->(id) {
    ids = Array(id).map { |c| c.to_s.upcase }
    where("native_control_ids && ARRAY[:i]::varchar[] OR enriched_control_ids && ARRAY[:i]::varchar[]", i: ids)
  }

  # A component asserts no control coverage at all. This is the MAJORITY case —
  # 163 of the 230 upstream AWS CDEFs — so the UI must render it as a stated
  # fact rather than an empty region, or 71% of the corpus looks broken.
  def no_coverage_asserted? = native_control_ids.empty? && enriched_control_ids.empty?

  def derived_only? = native_control_ids.empty? && enriched_control_ids.any?

  # `aws_direct` is a one-hop Security Hub -> NIST lookup; `via_config_rule`
  # goes through the Config Rule. Presented as direct vs inferred, never as a
  # numeric confidence — the importer records no such value and inventing one
  # would be fabricating precision.
  def mapping_directness
    return nil if mapping_sources.empty?

    mapping_sources.include?("aws_direct") ? :direct : :inferred
  end

  # Everything this component is known to do, declared first. Used for display;
  # search hits the two columns separately so a caller can ask for asserted-only.
  def capabilities = (declared_capabilities + derived_capabilities).uniq

  scope :with_capability, ->(name) {
    names = Array(name)
    where("declared_capabilities && ARRAY[:c]::varchar[] OR derived_capabilities && ARRAY[:c]::varchar[]", c: names)
  }
  scope :declaring_capability, ->(name) {
    where("declared_capabilities && ARRAY[?]::varchar[]", Array(name))
  }
  scope :checking, ->(check_id) {
    where("check_ids && ARRAY[?]::varchar[]", Array(check_id).map(&:to_s))
  }

  # Map control coverage onto functional capabilities.
  #
  # Both sides go through ControlId.canonical because the map above is written
  # in label form (`IA-2(1)`) while the enriched ids arrive in OSCAL dotted form
  # (`IA-2.1`). Comparing them raw silently matches nothing — MFA derived zero
  # hits across the whole corpus until this was normalised. Normalise the FORM,
  # never the vocabulary.
  #
  # Matching stays exact on the canonical id: `ia-2` must not satisfy `ia-2.1`,
  # because single-factor identification is not multi-factor authentication and
  # a browser that blurred the two would tell an assessor something false.
  def self.derive_capabilities(control_ids)
    ids = Array(control_ids).filter_map { |c| ControlId.canonical(c.to_s) }.to_set
    CAPABILITY_CONTROL_MAP.filter_map do |capability, controls|
      capability if controls.any? { |c| ids.include?(ControlId.canonical(c)) }
    end.sort
  end

  # Derive the partition set from region ids. Kept here rather than in the
  # indexer so the rule has one home and can be unit-tested without an import.
  def self.partitions_for(region_ids)
    Array(region_ids).filter_map { |r|
      case r.to_s
      when /\Aus-gov-/ then PARTITION_GOV
      when /\Acn-/     then PARTITION_CN
      when /\A[a-z]{2}-/ then PARTITION_STD
      end
    }.uniq.sort
  end
end
