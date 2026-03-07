# Builds an OSCAL v1.1.2 Catalog JSON document from a ControlCatalog
# and its families/controls. Validates the output against the official
# NIST JSON schema before returning.
#
# Usage:
#   service = OscalCatalogExportService.new(control_catalog)
#   json_string = service.export            # validates, raises on failure
#   json_string = service.export_unvalidated # skips validation
#   result      = service.validation_result  # inspect errors without raising
#
class OscalCatalogExportService
  OSCAL_VERSION = "1.1.2"

  def initialize(control_catalog)
    @catalog = control_catalog
  end

  def export
    data = build_catalog
    OscalSchemaValidationService.validate!(:catalog, data)
    JSON.pretty_generate(data)
  end

  def export_unvalidated
    JSON.pretty_generate(build_catalog)
  end

  def validation_result
    data = build_catalog
    OscalSchemaValidationService.validate(:catalog, data)
  end

  private

  def build_catalog
    result = {
      "catalog" => {
        "uuid"     => @catalog.uuid || SecureRandom.uuid,
        "metadata" => build_metadata,
        "groups"   => build_groups
      }
    }

    back_matter = build_back_matter
    result["catalog"]["back-matter"] = back_matter if back_matter.present?

    result
  end

  def build_metadata
    if @catalog.respond_to?(:build_oscal_metadata)
      @catalog.build_oscal_metadata
    else
      {
        "title"         => @catalog.name,
        "version"       => @catalog.version || "1.0.0",
        "oscal-version" => @catalog.oscal_version || OSCAL_VERSION,
        "last-modified" => Time.current.iso8601,
        "roles"         => [{ "id" => "creator", "title" => "Document Creator" }],
        "parties"       => [{
          "uuid" => SecureRandom.uuid,
          "type" => "organization",
          "name" => "SPARC Export"
        }]
      }
    end
  end

  def build_groups
    families = @catalog.control_families.includes(catalog_controls: [])

    families.map do |family|
      group = {
        "id"       => family.code.downcase,
        "title"    => family.name
      }

      group["class"] = "family" if family.code.present?

      props = family.try(:props_data).presence
      group["props"] = props if props.present?

      links = family.try(:links_data).presence
      group["links"] = links if links.present?

      controls = build_controls(family)
      group["controls"] = controls if controls.any?

      group
    end
  end

  def build_controls(family)
    # Only export root controls (no sub-parts like AC-01a, AC-01a.1)
    root_controls = family.catalog_controls.select { |c| root_control?(c.control_id) }

    root_controls.map do |control|
      build_control(control, family)
    end
  end

  def build_control(control, family)
    ctrl = {
      "id"    => oscal_control_id(control.control_id),
      "title" => control.title || control.control_id
    }

    ctrl["class"] = control.control_class if control.try(:control_class).present?

    # Parameters
    params = control.try(:oscal_params) || []
    ctrl["params"] = params if params.any?

    # Properties
    props = build_control_props(control)
    ctrl["props"] = props if props.any?

    # Links
    links = control.try(:oscal_links) || []
    ctrl["links"] = links if links.any?

    # Parts — use structured OSCAL parts if available, else build from guidance_data
    parts = control.try(:oscal_parts) || []
    if parts.any?
      ctrl["parts"] = parts
    else
      built_parts = build_parts_from_guidance(control, family)
      ctrl["parts"] = built_parts if built_parts.any?
    end

    # Sub-controls (enhancements) — controls with IDs like AC-01(01)
    enhancements = find_enhancements(control, family)
    if enhancements.any?
      ctrl["controls"] = enhancements.map { |e| build_control(e, family) }
    end

    ctrl
  end

  def build_control_props(control)
    # Use stored OSCAL props if available
    stored_props = control.try(:oscal_props) || []
    return stored_props if stored_props.any?

    # Build from existing columns
    props = []
    props << { "name" => "label", "value" => control.control_id } if control.control_id.present?
    props << { "name" => "priority", "value" => control.priority } if control.priority.present?

    if control.baseline_impact.present?
      control.baseline_impact.split(",").map(&:strip).each do |level|
        props << { "name" => "impact-level", "value" => level.downcase }
      end
    end

    props
  end

  def build_parts_from_guidance(control, _family)
    parts = []
    guidance = control.guidance_fields

    if guidance["statement"].present?
      parts << {
        "id"    => "#{oscal_control_id(control.control_id)}_smt",
        "name"  => "statement",
        "prose" => guidance["statement"]
      }
    end

    if guidance["supplemental_guidance"].present?
      guidance_part = {
        "id"    => "#{oscal_control_id(control.control_id)}_gdn",
        "name"  => "guidance",
        "prose" => guidance["supplemental_guidance"]
      }

      # Add related control links
      if guidance["related_controls"].present?
        related_links = guidance["related_controls"].split(",").map(&:strip).map do |ref|
          { "href" => "##{ref.downcase.tr(' ', '-')}", "rel" => "related" }
        end
        guidance_part["links"] = related_links
      end

      parts << guidance_part
    end

    parts
  end

  def find_enhancements(control, family)
    base_id = control.control_id
    family.catalog_controls.select do |c|
      c.control_id != base_id &&
        c.control_id.start_with?("#{base_id}(") &&
        !c.control_id.match?(/[a-z]\z/)
    end
  end

  # Determine if a control_id is a root control (not a sub-part like AC-01a or AC-01a.1)
  def root_control?(control_id)
    # Root controls: AC-01, AC-01(01), SI-02(02)
    # Not root: AC-01a, AC-01a.1, AC-01a.1.(a)
    control_id.match?(/\A[A-Z]+-\d+(\(\d+\))?\z/)
  end

  # Convert stored control_id to OSCAL format: AC-01 → ac-1
  def oscal_control_id(control_id)
    control_id.downcase
      .sub(/\A([a-z]+-)0+(\d+)/, '\1\2')  # Remove zero-padding: ac-01 → ac-1
  end

  def build_back_matter
    resources = @catalog.try(:back_matter_data)
    return nil if resources.blank? || resources.empty?

    { "resources" => resources }
  end
end
