# frozen_string_literal: true

# Reads a CdefDocument (already parsed via CdefXccdfParserService) and
# auto-generates ControlMapping + ControlMappingEntry records by looking
# up each control's identifiers against the appropriate framework mapping table.
#
# Supports: disa_stig (via CCI pivot), cis, scap
#
# Usage:
#   doc = CdefDocument.find(123)
#   nist_catalog = ControlCatalog.find_by(name: "NIST SP 800-53 Rev 5")
#   service = FrameworkMappingGeneratorService.new(doc, nist_catalog)
#   mapping = service.generate!           # persists to DB
#   preview = service.preview             # dry-run, returns hash
#   stats   = service.coverage_stats      # { total: 200, mapped: 170, pct: 85.0 }
#
class FrameworkMappingGeneratorService
  class UnsupportedFramework < StandardError; end

  MAPPING_FILES = {
    "disa_stig" => "cci_to_nist",
    "cis"       => "cis_to_nist",
    "scap"      => "scap_oval_to_nist"
  }.freeze

  attr_reader :document, :target_catalog

  def initialize(cdef_document, target_catalog)
    @document       = cdef_document
    @target_catalog = target_catalog
    @lookup         = load_lookup_table
  end

  # Persist a ControlMapping with auto-generated entries. Returns the mapping.
  def generate!
    validate_framework!

    source_catalog = find_or_create_source_catalog

    mapping = ControlMapping.create!(
      name:               "#{@document.name} → #{@target_catalog.name}",
      source_catalog:     source_catalog,
      target_catalog:     @target_catalog,
      status:             "draft",
      method_type:        "automation",
      matching_rationale: "functional",
      metadata_extra:     generation_metadata
    )

    entries = build_entries(mapping)
    ControlMappingEntry.import(entries, validate: false) if entries.any?

    mapping.reload
  end

  # Returns a preview hash without persisting: { "SV-257777" => ["ac-2", "ac-6"], ... }
  def preview
    controls_with_mappings.transform_values { |resolved| resolved.map { |r| r[:nist_id] } }
  end

  # Returns coverage statistics for this document against the mapping table.
  def coverage_stats
    total  = @document.cdef_controls.count
    mapped = controls_with_mappings.count
    pct    = total.zero? ? 0.0 : (mapped.to_f / total * 100).round(1)
    { total: total, mapped: mapped, unmapped: total - mapped, coverage_pct: pct }
  end

  private

  def validate_framework!
    return if MAPPING_FILES.key?(@document.cdef_type)

    raise UnsupportedFramework,
          "cdef_type '#{@document.cdef_type}' is not supported. " \
          "Supported types: #{MAPPING_FILES.keys.join(', ')}"
  end

  def load_lookup_table
    file_key = MAPPING_FILES[@document.cdef_type]
    return {} unless file_key

    path = Rails.root.join("lib", "data_mappings", "#{file_key}.json")
    return {} unless path.exist?

    data = JSON.parse(path.read)
    build_index(data)
  end

  def build_index(data)
    case @document.cdef_type
    when "disa_stig"
      # CCI → NIST: index by CCI ID for O(1) lookup
      (data["mappings"] || []).index_by { |m| m["cci"] }
    when "cis"
      # Merge both data sources into a unified CIS ID → nist mapping index.
      # benchmark_mappings: array of { cis_id, nist_controls, relationship }
      # controls_mappings:  hash of  CIS ID → [{ nist, relationship }]
      index = {}
      (data["benchmark_mappings"] || []).each do |m|
        index[m["cis_id"]] = {
          "nist_controls" => m["nist_controls"],
          "relationship"  => m["relationship"]
        }
      end
      (data["controls_mappings"] || {}).each do |cis_id, nist_arr|
        next if index.key?(cis_id)

        index[cis_id] = {
          "nist_controls" => nist_arr.map { |n| n["nist"] },
          "relationship"  => nist_arr.first&.dig("relationship") || "subset"
        }
      end
      index
    when "scap"
      # Two-tier index: OVAL family + keyword categories
      {
        families:   (data["oval_family_mappings"] || []).index_by { |m| m["oval_family"] },
        categories: data["xccdf_category_mappings"] || [],
        check_systems: (data["check_system_mappings"] || []).index_by { |m| m["check_system"] }
      }
    else
      {}
    end
  end

  # ── Per-framework resolution logic ──────────────────────────────────

  def resolve_nist_controls(cdef_control)
    case @document.cdef_type
    when "disa_stig" then resolve_via_cci(cdef_control)
    when "cis"       then resolve_via_cis(cdef_control)
    when "scap"      then resolve_via_scap(cdef_control)
    else []
    end
  end

  # STIG: SV-XXXXX → CCI-XXXXX (from parsed cci_references) → NIST
  def resolve_via_cci(control)
    return [] if control.cci_references.blank?

    control.cci_references.split(",").flat_map do |cci_raw|
      cci = cci_raw.strip
      entry = @lookup[cci]
      next [] unless entry

      nist_id = entry["nist_rev5"] || entry["nist_rev4"]
      next [] unless nist_id

      [ { nist_id: nist_id, relationship: "subset", via: cci } ]
    end.uniq { |e| e[:nist_id] }
  end

  # CIS: group_id contains numeric section (e.g. "1.1.1") → lookup.
  # Tries exact match first, then progressively shorter IDs (5.2.1 → 5.2 → 5).
  def resolve_via_cis(control)
    cis_id = extract_cis_id(control)
    entry = lookup_cis_with_fallback(cis_id)
    return [] unless entry

    (entry["nist_controls"] || []).map do |nist_id|
      { nist_id: nist_id, relationship: entry["relationship"] || "subset", via: "CIS #{cis_id}" }
    end
  end

  # SCAP: try check_system URI first, then OVAL family, then keyword matching
  def resolve_via_scap(control)
    results = []

    # 1. Check system URI match
    check_field = control.cdef_control_fields.find_by(field_name: "check_system")
    if check_field&.field_value.present? && @lookup[:check_systems]
      cs_entry = @lookup[:check_systems][check_field.field_value]
      if cs_entry
        cs_entry["nist_controls"].each do |nist_id|
          results << { nist_id: nist_id, relationship: cs_entry["relationship"] || "intersects",
                       via: "check_system:#{check_field.field_value}" }
        end
      end
    end

    # 2. OVAL family detection from check_system URI
    if check_field&.field_value.to_s.include?("oval") && @lookup[:families]
      family = detect_oval_family(control)
      fam_entry = @lookup[:families][family]
      if fam_entry
        fam_entry["nist_controls"].each do |nist_id|
          results << { nist_id: nist_id, relationship: fam_entry["relationship"] || "intersects",
                       via: "oval_family:#{family}" }
        end
      end
    end

    # 3. Keyword-based category matching (fallback)
    if results.empty? && @lookup[:categories]
      text = [ control.title, control.control_id,
              control.cdef_control_fields.find_by(field_name: "description")&.field_value ].compact.join(" ").downcase

      @lookup[:categories].each do |cat|
        next unless cat["keywords"]&.any? { |kw| text.include?(kw) }
        cat["nist_controls"].each do |nist_id|
          results << { nist_id: nist_id, relationship: cat["relationship"] || "intersects",
                       via: "keyword:#{cat['category']}" }
        end
        break # use first matching category
      end
    end

    results.uniq { |e| e[:nist_id] }
  end

  # ── Helpers ─────────────────────────────────────────────────────────

  def lookup_cis_with_fallback(cis_id)
    return @lookup[cis_id] if @lookup.key?(cis_id)

    # Try progressively shorter IDs: "5.2.1" → "5.2" → "5"
    parts = cis_id.split(".")
    while parts.length > 1
      parts.pop
      shorter = parts.join(".")
      return @lookup[shorter] if @lookup.key?(shorter)
    end
    nil
  end

  def extract_cis_id(control)
    # CIS XCCDF group IDs: "xccdf_org.cisecurity.benchmarks_group_1.1.1"
    # or rule IDs:          "xccdf_org.cisecurity.benchmarks_rule_1.1.1"
    raw = [ control.group_id, control.rule_id, control.control_id ].compact.join(" ")
    raw.match(/(\d+(?:\.\d+){1,})/)&.[](1) || control.control_id
  end

  def detect_oval_family(control)
    desc = control.cdef_control_fields.find_by(field_name: "description")&.field_value.to_s.downcase
    title = control.title.to_s.downcase

    text = "#{desc} #{title}"
    if text.match?(/patch|update|upgrade/)
      "patch"
    elsif text.match?(/vulnerab|cve-/)
      "vulnerability"
    elsif text.match?(/inventory|installed|software/)
      "inventory"
    else
      "compliance"
    end
  end

  def controls_with_mappings
    @controls_with_mappings ||= @document.cdef_controls
      .includes(:cdef_control_fields)
      .each_with_object({}) do |ctrl, hash|
        resolved = resolve_nist_controls(ctrl)
        hash[ctrl.control_id] = resolved if resolved.any?
      end
  end

  def build_entries(mapping)
    row_order = 0
    entries = []

    @document.cdef_controls.includes(:cdef_control_fields).find_each do |ctrl|
      resolve_nist_controls(ctrl).each do |resolved|
        entries << ControlMappingEntry.new(
          control_mapping_id: mapping.id,
          uuid:               SecureRandom.uuid,
          source_control_id:  ctrl.control_id,
          source_type:        "control",
          target_control_id:  resolved[:nist_id],
          target_type:        "control",
          relationship:       resolved[:relationship],
          remarks:            "Auto-mapped via #{resolved[:via]}",
          row_order:          row_order
        )
        row_order += 1
      end
    end

    entries
  end

  def find_or_create_source_catalog
    name = @document.import_metadata&.dig("title") || @document.name
    ControlCatalog.find_or_create_by!(name: name) do |cat|
      cat.version = @document.cdef_version
      cat.status = "completed"
    end
  end

  def generation_metadata
    {
      "cdef_document_id" => @document.id,
      "cdef_type"        => @document.cdef_type,
      "generator"        => self.class.name,
      "generated_at"     => Time.current.iso8601,
      "mapping_file"     => MAPPING_FILES[@document.cdef_type]
    }
  end
end
