# #887 — build the denormalized CdefComponent rows for one CDEF.
#
# The browser needs to filter on partition, region, availability, lifecycle
# stage, automated-check presence and control coverage. None of those live in
# one place:
#
#   * availability / lifecycle-stage / service-id  -> component `props`
#   * automated checks                             -> sibling components of
#                                                     type `software` carrying
#                                                     a ConfigRuleId prop
#   * region + partition                           -> `links[rel=provided-by]`,
#                                                     and specifically the
#                                                     `resource-fragment`, which
#                                                     resolves against a
#                                                     SEPARATE document
#                                                     (aws_regions.oscal.json)
#   * derived NIST ids                             -> cdef_control_fields, EAV
#
# The `href` on every provided-by link is the same generic pointer at the
# regions CDEF resource; reading only `href` makes it look like there is no
# per-service region data. The per-region detail is in `resource-fragment`.
#
# Region components are indexed too, each carrying its own region-id in
# `region_ids`. That is what lets a service's `resource-fragment` resolve to a
# region id without holding both documents in memory at once — and it means the
# regions CDEF must be indexed before the services that reference it. A service
# indexed first simply resolves nothing; re-running fixes it, which is why
# reindexing is always safe.
class CdefComponentIndexer
  AWS_NS = "http://aws.amazon.com/ns/oscal".freeze
  CONFIG_RULE_PROP = "ConfigRuleId".freeze

  def initialize(document, oscal, logger: Rails.logger)
    @document = document
    @oscal    = oscal.is_a?(String) ? JSON.parse(oscal) : oscal
    @logger   = logger
  end

  # Replaces this document's component rows. Idempotent: same input, same rows.
  def index!
    body = @oscal["component-definition"] || @oscal
    components = Array(body["components"])

    rows = components.filter_map { |component| build_row(component) }
    # The trigram index covers `search_blob`, and this is the only writer of
    # these rows, so filling it here keeps it in step by construction.
    rows.each { |row| row[:search_blob] = CdefComponent.build_search_blob(row) }

    CdefComponent.transaction do
      CdefComponent.where(cdef_document: @document).delete_all
      CdefComponent.insert_all!(rows) if rows.any?
    end

    rows.size
  end

  private

  def build_row(component)
    uuid = component["uuid"]
    return nil if uuid.blank?

    props  = index_props(component["props"])
    type   = component["type"].to_s
    regions = resolve_regions(component, type, props)

    native   = native_control_ids(component)
    enriched = enriched_control_ids(component)
    declared = declared_capabilities(component["props"])

    now = Time.current
    {
      cdef_document_id: @document.id,
      component_uuid: uuid,
      title: component["title"],
      component_type: type.presence,
      description: component["description"],
      purpose: component["purpose"],
      service_id: props["service-id"],
      availability: props["availability"],
      lifecycle_stage: props["lifecycle-stage"],
      region_ids: regions,
      partitions: CdefComponent.partitions_for(regions),
      has_checks: check_count(component, props).positive?,
      check_count: check_count(component, props),
      native_control_ids: native,
      enriched_control_ids: enriched,
      mapping_sources: mapping_sources(component),
      declared_capabilities: declared,
      # Derived from BOTH layers: an Okta CDEF may assert IA-2(1) directly,
      # while an AWS service only reaches MFA through its enriched NIST ids.
      derived_capabilities: CdefComponent.derive_capabilities(native + enriched) - declared,
      check_ids: check_ids(component, props),
      content_hash: Digest::SHA256.hexdigest(component.to_json),
      created_at: now,
      updated_at: now
    }
  end

  # Props are a list, and AWS repeats some names (two `label` entries on the S3
  # service component). Last one wins — we only read single-valued names.
  def index_props(props)
    Array(props).each_with_object({}) do |prop, map|
      name = prop["name"].to_s
      next if name.blank?

      map[name] = prop["value"]
    end
  end

  # A `region` component describes itself; anything else resolves its
  # provided-by fragments against previously indexed region components.
  def resolve_regions(component, type, props)
    return Array(props["region-id"]).compact if type == "region"

    fragments = Array(component["links"])
                  .select { |link| link["rel"] == "provided-by" }
                  .filter_map { |link| link["resource-fragment"].presence }
                  .uniq
    return [] if fragments.empty?

    region_map.values_at(*fragments).flatten.compact.uniq.sort
  end

  # component_uuid -> [region-id]. Scoped to region components across all
  # documents, because the regions live in their own CDEF, not this one.
  def region_map
    @region_map ||= CdefComponent.where(component_type: "region")
                                 .pluck(:component_uuid, :region_ids)
                                 .to_h
  end

  # Config Rule components are the automated checks. A `service` component does
  # not carry them itself — they are siblings — so a service reports the count
  # for its whole document, which is the question a user is actually asking
  # ("does this CDEF contribute to continuous assessment?").
  def check_count(component, props)
    return 1 if props.key?(CONFIG_RULE_PROP)

    if component["type"].to_s == "service"
      @document_check_count ||= Array(@oscal.dig("component-definition", "components"))
        .count { |c| index_props(c["props"]).key?(CONFIG_RULE_PROP) }
      return @document_check_count
    end

    0
  end

  # An org or custom CDEF states its own capability with a repeatable
  # `capability` prop. This is the path that gives hand-built content the same
  # searchable fields as the AWS corpus without relying on any inference.
  def declared_capabilities(props)
    Array(props)
      .select { |p| p["name"].to_s.casecmp?("capability") }
      .filter_map { |p| p["value"].presence&.to_s&.strip }
      .uniq
      .sort
  end

  # The automated checks themselves, so "what can automatically check X" is
  # answerable rather than just "does this have checks". AWS spells them as
  # Config Rule ids; an org CDEF using a different check system lands here too
  # as long as it carries the prop.
  def check_ids(component, props)
    own = props[CONFIG_RULE_PROP].presence
    return [ own.to_s ] if own

    return [] unless component["type"].to_s == "service"

    @document_check_ids ||= Array(@oscal.dig("component-definition", "components"))
      .filter_map { |c| index_props(c["props"])[CONFIG_RULE_PROP].presence&.to_s }
      .uniq
      .sort
  end

  # What the upstream author actually asserted. For AWS service CDEFs these are
  # Security Hub control ids, NOT NIST ids — see #491.
  def native_control_ids(component)
    Array(component["control-implementations"])
      .flat_map { |impl| Array(impl["implemented-requirements"]) }
      .filter_map { |req| req["control-id"].presence }
      .map(&:upcase)
      .uniq
      .sort
  end

  # What SPARC derived. Read from the EAV rows the AWS import writes so the two
  # layers stay distinguishable; a component with no matching CdefControl simply
  # has none.
  def enriched_control_ids(component)
    enrichment_for(component).fetch(:ids, []).sort
  end

  def mapping_sources(component)
    enrichment_for(component).fetch(:sources, []).sort
  end

  # cdef_control_fields stores the component title under field_name
  # "component", which is the only link back from a control row to the
  # component that owns it.
  def enrichment_for(component)
    @enrichment ||= build_enrichment_map
    @enrichment.fetch(component["title"].to_s, { ids: [], sources: [] })
  end

  def build_enrichment_map
    control_ids = CdefControl.where(cdef_document_id: @document.id).select(:id)
    fields = CdefControlField
               .where(cdef_control_id: control_ids,
                      field_name: %w[component nist_oscal_ids nist_mapping_source])
               .pluck(:cdef_control_id, :field_name, :field_value)

    by_control = fields.group_by(&:first)
    by_control.each_with_object({}) do |(_control_id, rows), map|
      values = rows.to_h { |(_id, name, value)| [ name, value ] }
      component_title = values["component"].to_s
      next if component_title.blank?

      entry = map[component_title] ||= { ids: [], sources: [] }
      entry[:ids].concat(values["nist_oscal_ids"].to_s.split(",").map { |i| i.strip.upcase }.reject(&:blank?))
      entry[:sources] << values["nist_mapping_source"] if values["nist_mapping_source"].present?
      entry[:ids].uniq!
      entry[:sources].uniq!
    end
  end
end
