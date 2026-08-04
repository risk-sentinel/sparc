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

  # The raw identifiers are what OSCAL and the AWS APIs use, so they stay in
  # the data and remain searchable. These are for display only: a chip reading
  # `aws-cn` makes a reader decode an identifier, where "AWS China" just says it.
  PARTITION_LABELS = {
    PARTITION_STD => "AWS Commercial",
    PARTITION_GOV => "AWS GovCloud",
    PARTITION_CN  => "AWS China"
  }.freeze

  def self.partition_label(partition) = PARTITION_LABELS.fetch(partition.to_s, partition.to_s)

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

  # Free-text search across everything the index knows (#887).
  #
  # The document-level `search_text` scope only sees name and description, so
  # `us-east` matched nothing even though most components are available there —
  # the regions, control ids, capabilities and service ids all live here.
  #
  # Array columns are matched with ILIKE over `unnest` rather than membership,
  # so a partial term finds the full value: `us-east` -> `us-east-1`,
  # `AC-2` -> `AC-2.1`. Exact-only membership would make the obvious search
  # return nothing, which is exactly the failure being fixed.
  ARRAY_SEARCH_COLUMNS = %w[
    region_ids partitions declared_capabilities derived_capabilities
    native_control_ids enriched_control_ids check_ids
  ].freeze

  TEXT_SEARCH_COLUMNS = %w[title description service_id availability lifecycle_stage].freeze

  def self.search(term)
    return none if term.blank?

    # One indexed predicate against the denormalized blob. The previous form —
    # ILIKE over unnest() of seven array columns — could not use any index and
    # sequentially scanned the table for every query.
    where("search_blob ILIKE ?", "%#{sanitize_sql_like(term.to_s.strip)}%")
  end

  # Everything searchable, flattened into the column the trigram index covers.
  # Built here rather than in the indexer so the definition of "searchable"
  # lives next to the columns it names.
  def self.build_search_blob(attrs)
    text = TEXT_SEARCH_COLUMNS.map { |c| attrs[c.to_sym] || attrs[c] }
    arrays = ARRAY_SEARCH_COLUMNS.flat_map { |c| Array(attrs[c.to_sym] || attrs[c]) }
    (text + arrays).compact.reject(&:blank?).join(" ")
  end

  # ── Browser summaries (#887) ──────────────────────────────────────────────
  #
  # A card shows document-level applicability, but the facts live per
  # component. Roll them up for the documents actually being rendered — never
  # for the whole table — so the cost tracks the page, not the corpus.
  #
  # Aggregated in Ruby rather than SQL: the arrays would need unnest + array_agg
  # per column, and the input is one page of documents, not 861 rows.
  def self.summary_for(document_ids)
    ids = Array(document_ids).compact.uniq
    return {} if ids.empty?

    where(cdef_document_id: ids).group_by(&:cdef_document_id).transform_values do |components|
      services = components.select { |c| c.component_type == "service" }
      {
        component_count: components.size,
        service_count: services.size,
        # An upstream file is a service FAMILY, not one service:
        # workspaces.oscal carries four (WorkSpaces, Instances, Thin Client,
        # Web). Naming them is the difference between a card that informs and
        # one that just says "4".
        service_titles: services.filter_map(&:title).uniq.sort,
        # The component's own description is the most useful prose available —
        # it says what the thing actually does, which neither the OSCAL
        # filename nor the document description manages. Prefer a service's;
        # fall back to any component with one.
        primary_description: services.filter_map { |s| s.description.presence }.first ||
                             components.filter_map { |c| c.description.presence }.first,
        partitions: components.flat_map(&:partitions).uniq.sort,
        # Those four services do NOT share a region set (17 / 0 / 7 / 10), so a
        # unioned partition chip can say aws-us-gov when only one of them is
        # actually in GovCloud. Flag when the union is hiding a difference, so
        # the card can say so rather than quietly overstating availability.
        partitions_uniform: services.size <= 1 ||
                            services.map { |s| s.partitions.sort }.uniq.size == 1,
        region_count: components.flat_map(&:region_ids).uniq.size,
        availability: components.filter_map(&:availability).uniq.sort,
        lifecycle_stages: components.filter_map(&:lifecycle_stage).uniq.sort,
        declared_capabilities: components.flat_map(&:declared_capabilities).uniq.sort,
        derived_capabilities: components.flat_map(&:derived_capabilities).uniq.sort,
        # check_ids repeat across a document's components (a service rolls up
        # its siblings'), so count the distinct rules, not the occurrences.
        check_count: components.flat_map(&:check_ids).uniq.size,
        native_control_count: components.flat_map(&:native_control_ids).uniq.size,
        enriched_control_count: components.flat_map(&:enriched_control_ids).uniq.size,
        mapping_sources: components.flat_map(&:mapping_sources).uniq.sort
      }
    end
  end

  # An empty summary, so a view never has to nil-check. A CDEF with no indexed
  # components is a real state — nothing has been indexed for it yet — and
  # should render as "no coverage asserted" rather than blank.
  def self.empty_summary
    {
      component_count: 0, service_count: 0, service_titles: [],
      primary_description: nil, partitions: [],
      partitions_uniform: true, region_count: 0,
      availability: [], lifecycle_stages: [], declared_capabilities: [],
      derived_capabilities: [], check_count: 0, native_control_count: 0,
      enriched_control_count: 0, mapping_sources: []
    }.freeze
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
