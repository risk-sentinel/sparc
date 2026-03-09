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
    {
      "catalog" => {
        "uuid"     => SecureRandom.uuid,
        "metadata" => build_metadata,
        "groups"   => build_groups
      }.compact
    }
  end

  def build_metadata
    base = {
      "title"         => @catalog.name,
      "version"       => @catalog.oscal_document_version || "1.0.0",
      "oscal-version" => @catalog.oscal_version || OSCAL_VERSION,
      "last-modified" => Time.current.iso8601
    }

    base["published"] = @catalog.published if @catalog.published.present?

    extra = @catalog.metadata_extra || {}
    if extra.any?
      base.merge(extra)
    else
      base.merge(default_metadata_extras)
    end
  end

  def default_metadata_extras
    {
      "roles"   => [ { "id" => "creator", "title" => "Document Creator" } ],
      "parties" => [ {
        "uuid" => SecureRandom.uuid,
        "type" => "organization",
        "name" => "SPARC Export"
      } ]
    }
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

    top_level.map do |control|
      build_control(control, family)
    end
  end

  def build_control(control, family)
    result = {
      "id"    => control.control_id.downcase.tr(" ", "-"),
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
    props << { "name" => "label", "value" => control.control_id }
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
        "id"    => "#{control.control_id.downcase}_smt",
        "name"  => "statement",
        "prose" => guidance["statement"]
      }
    end

    if guidance["supplemental_guidance"].present?
      guidance_part = {
        "id"    => "#{control.control_id.downcase}_gdn",
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
    # Top-level controls match patterns like "AC-01", "AC-01(1)" but not "AC-01a" or "AC-01a.1"
    control_id.match?(/\A[A-Z]+-\d+(\(\d+\))?\z/)
  end
end
