# Exports FedRAMP 20x KSI compliance status for an authorization boundary.
#
# Produces a machine-readable schema containing:
#   - System identification (boundary name, UUID)
#   - KSI catalog version and theme definitions
#   - Per-KSI validation status with evidence references
#   - KSI-to-NIST control mappings
#   - Summary statistics (counts by status, by theme, compliance percentage)
#
# Supports JSON, YAML, and XML output formats.
#
# Usage:
#   service = KsiExportService.new(authorization_boundary)
#   hash    = service.export_hash
#   json    = service.export(format: :json)
#   yaml    = service.export(format: :yaml)
#   xml     = service.export(format: :xml)
#
# NIST: CA-7 (Continuous Monitoring), PM-6 (Measures of Performance)
class KsiExportService
  attr_reader :boundary

  def initialize(authorization_boundary)
    @boundary = authorization_boundary
  end

  # Returns the full export as a formatted string in the requested format.
  def export(format: :json)
    hash = export_hash
    case format.to_sym
    when :json
      JSON.pretty_generate(hash)
    when :yaml
      require "yaml"
      JSON.parse(hash.to_json).to_yaml
    when :xml
      build_xml(hash)
    else
      raise ArgumentError, "Unsupported format: #{format}. Use :json, :yaml, or :xml"
    end
  end

  # Returns the export data as a Ruby hash.
  def export_hash
    validations = boundary.ksi_validations
                          .includes(catalog_control: :control_family, evidence: [])
                          .order("control_families.sort_order", "catalog_controls.sort_id")

    ksi_catalog = find_ksi_catalog
    mapping_entries = load_mapping_entries(ksi_catalog)

    {
      system: system_info,
      ksi_catalog: catalog_info(ksi_catalog),
      export_timestamp: Time.current.iso8601,
      validations: validations.map { |v| serialize_validation(v, mapping_entries) },
      summary: build_summary(validations)
    }
  end

  # Returns summary statistics only (used by the summary API endpoint).
  def summary
    validations = boundary.ksi_validations
                          .includes(catalog_control: :control_family)

    ksi_catalog = find_ksi_catalog
    total_ksis = ksi_catalog&.catalog_controls&.count || 0

    stats = build_summary(validations)
    stats[:total_ksis_in_catalog] = total_ksis
    stats[:assessed_percentage] = total_ksis.positive? ?
      ((stats[:total] - stats.dig(:by_status, :not_assessed).to_i).to_f / total_ksis * 100).round(1) : 0.0
    stats
  end

  private

  def system_info
    {
      boundary_id: boundary.id,
      boundary_name: boundary.name,
      boundary_slug: boundary.slug,
      boundary_status: boundary.status,
      organization: boundary.organization&.name
    }
  end

  def find_ksi_catalog
    ControlCatalog.find_by(source: "FedRAMP 20x")
  end

  def catalog_info(catalog)
    return {} unless catalog

    {
      name: catalog.name,
      version: catalog.version,
      source: catalog.source,
      themes_count: catalog.control_families.count,
      indicators_count: catalog.catalog_controls.count
    }
  end

  def load_mapping_entries(ksi_catalog)
    return {} unless ksi_catalog

    mapping = ControlMapping.find_by(source_catalog: ksi_catalog)
    return {} unless mapping

    mapping.control_mapping_entries
           .group_by(&:source_control_id)
           .transform_values { |entries| entries.map { |e| { target: e.target_control_id, relationship: e.relationship } } }
  end

  def serialize_validation(validation, mapping_entries)
    {
      ksi_id: validation.ksi_id,
      ksi_title: validation.ksi_title,
      theme_code: validation.theme_code,
      theme_name: validation.theme_name,
      status: validation.status,
      validation_method: validation.validation_method,
      evidence_format: validation.evidence_format,
      last_validated_at: validation.last_validated_at&.iso8601,
      next_validation_due: validation.next_validation_due&.iso8601,
      overdue: validation.expired?,
      notes: validation.notes,
      evidence: serialize_evidence(validation.evidence),
      mapped_nist_controls: mapping_entries[validation.ksi_id] || [],
      validation_metadata: validation.validation_metadata
    }
  end

  def serialize_evidence(evidence)
    return nil unless evidence

    {
      id: evidence.id,
      title: evidence.title,
      evidence_type: evidence.evidence_type,
      status: evidence.status,
      file_hash: evidence.file_hash,
      collected_at: evidence.created_at&.iso8601
    }
  end

  def build_summary(validations)
    by_status = KsiValidation::STATUSES.index_with { |s| validations.count { |v| v.status == s } }
    by_theme = validations.group_by(&:theme_code).transform_values do |vs|
      {
        total: vs.size,
        passed: vs.count { |v| v.status == "passed" },
        failed: vs.count { |v| v.status == "failed" },
        partial: vs.count { |v| v.status == "partial" },
        expired: vs.count { |v| v.status == "expired" },
        not_assessed: vs.count { |v| v.status == "not_assessed" }
      }
    end

    total = validations.size
    passed = by_status["passed"]

    {
      total: total,
      by_status: by_status,
      by_theme: by_theme,
      overdue_count: validations.count(&:expired?),
      compliance_percentage: total.positive? ? (passed.to_f / total * 100).round(1) : 0.0
    }
  end

  def build_xml(hash)
    require "builder"
    xml = Builder::XmlMarkup.new(indent: 2)
    xml.instruct! :xml, version: "1.0", encoding: "UTF-8"
    xml.tag!("ksi-compliance-report", xmlns: "urn:fedramp:20x:ksi:1.0") do
      hash_to_xml(xml, hash)
    end
    xml.target!
  end

  def hash_to_xml(xml, data, parent_key = nil)
    case data
    when Hash
      data.each do |key, value|
        xml_key = key.to_s.tr("_", "-")
        if value.is_a?(Array)
          xml.tag!(xml_key) { hash_to_xml(xml, value, key) }
        elsif value.is_a?(Hash)
          xml.tag!(xml_key) { hash_to_xml(xml, value) }
        else
          xml.tag!(xml_key, value.to_s)
        end
      end
    when Array
      singular = parent_key.to_s.chomp("s").tr("_", "-")
      data.each do |item|
        xml.tag!(singular) { hash_to_xml(xml, item) }
      end
    end
  end
end
