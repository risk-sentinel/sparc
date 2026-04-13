# Builds an OSCAL v1.1.2 Catalog JSON document from a ControlCatalog
# and its families/controls.  Validates the output against the official
# NIST JSON schema before returning.
#
# Usage:
#   service = OscalCatalogExportService.new(control_catalog)
#   json_string = service.export            # validates, raises on failure
#   json_string = service.export_unvalidated # skips validation
#   result      = service.validation_result  # inspect errors without raising
#
class OscalCatalogExportService
  DEFAULT_OSCAL_VERSION = OscalSchema::DEFAULT_VERSION
  OSCAL_VERSION = DEFAULT_OSCAL_VERSION # backward compat

  def initialize(control_catalog)
    @catalog = control_catalog
  end

  def export
    data = build_catalog
    OscalSchemaValidationService.validate!(:catalog, data, version: effective_oscal_version)
    JSON.pretty_generate(data)
  end

  def export_unvalidated
    JSON.pretty_generate(build_catalog)
  end

  def validation_result
    data = build_catalog
    OscalSchemaValidationService.validate(:catalog, data)
  end


  def effective_oscal_version
    @catalog.oscal_version.presence || DEFAULT_OSCAL_VERSION
  end

  private

  def build_catalog
    {
      "catalog" => {
        "uuid"     => SecureRandom.uuid,
        "metadata" => build_metadata,
        "groups"   => build_groups
      }.compact
    }
  end

  def build_metadata
    @catalog.build_oscal_metadata(
      default_version: @catalog.oscal_document_version || "1.0.0",
      default_roles: [
        { "id" => "creator", "title" => "Document Creator" }
      ],
      default_parties: [
        { "uuid" => SecureRandom.uuid, "type" => "organization", "name" => "SPARC Export" }
      ]
    )
  end

  def build_groups
    @catalog.control_families.includes(:catalog_controls).order(:sort_order).map do |family|
      {
        "id"       => family.code.downcase,
        "class"    => "family",
        "title"    => family.name,
        "controls" => build_controls(family)
      }.compact
    end
  end

  def build_controls(family)
    # Only include top-level controls (those without sub-part suffixes like "a", ".1", ".(a)")
    top_level = family.catalog_controls.order(:control_id).select { |c| top_level_control?(c.control_id) }

    # Separate base controls from enhancements and nest enhancements under parents.
    # OSCAL requires enhancements (e.g., ac-2.1) nested as controls[] children of
    # their parent (e.g., ac-2), not as siblings at the group level.
    base_controls = top_level.select { |c| base_control?(c.control_id) }
    enhancements  = top_level.reject { |c| base_control?(c.control_id) }
    enh_by_parent = enhancements.group_by { |c| c.control_id.sub(/\.\d+\z/, "") }

    base_controls.map do |control|
      ctrl_hash = build_control(control, family)
      children = enh_by_parent[control.control_id]
      if children.present?
        ctrl_hash["controls"] = children.map { |enh| build_control(enh, family) }
      end
      ctrl_hash
    end
  end

  def build_control(control, family)
    result = {
      "id"    => control.control_id,
      "class" => "SP800-53",
      "title" => control.title
    }

    result["params"] = control.params_list if control.params_present?

    props = build_control_props(control)
    result["props"] = props if props.any?

    parts = build_control_parts(control, family)
    result["parts"] = parts if parts.any?

    result
  end

  def build_control_props(control)
    props = []
    props << { "name" => "label", "value" => control.display_id }
    if control.sort_id.present?
      props << { "name" => "sort-id", "value" => control.sort_id }
    end
    props << { "name" => "priority", "value" => control.priority } if control.priority.present?

    if control.baseline_impact.present?
      control.baseline_impact.split(",").map(&:strip).each do |level|
        props << { "name" => "impact-level", "value" => level }
      end
    end

    props
  end

  def build_control_parts(control, family)
    parts = []
    guidance = control.guidance_data || {}

    if guidance["statement"].present?
      parts << {
        "id"    => "#{control.control_id}_smt",
        "name"  => "statement",
        "prose" => guidance["statement"]
      }
    end

    if guidance["supplemental_guidance"].present?
      guidance_part = {
        "id"    => "#{control.control_id}_gdn",
        "name"  => "guidance",
        "prose" => guidance["supplemental_guidance"]
      }

      if guidance["related_controls"].present?
        guidance_part["links"] = guidance["related_controls"].split(",").map(&:strip).map do |ref|
          { "href" => "##{ref.downcase}", "rel" => "related" }
        end
      end

      parts << guidance_part
    end

    parts
  end

  def top_level_control?(control_id)
    # Top-level controls match canonical OSCAL format: "ac-1", "ac-2.1" but not "ac-1a" or "ac-1a.1"
    control_id.match?(/\A[a-z]+-\d+(\.\d+)?\z/i)
  end

  def base_control?(control_id)
    # Base controls have no enhancement suffix: "ac-1", "ac-2" but not "ac-2.1"
    control_id.match?(/\A[a-z]+-\d+\z/i)
  end

end
