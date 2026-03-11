# Builds an OSCAL v1.1.2 resolved-profile Catalog JSON document from a
# ProfileDocument and its linked ControlCatalog.  The output is a full
# Catalog containing only the controls selected in the profile, with
# catalog data (params, props, parts) merged with profile modifications
# (priority overrides, organization-defined parameter values).
#
# Usage:
#   service = OscalResolvedProfileCatalogService.new(profile_document)
#   json_string = service.export
#
class OscalResolvedProfileCatalogService
  OSCAL_VERSION = "1.1.2"

  def initialize(profile_document)
    @profile = profile_document
    @catalog = profile_document.control_catalog
    raise ArgumentError, "ProfileDocument must have a linked control_catalog" unless @catalog
  end

  def export
    JSON.pretty_generate(build_catalog)
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
    {
      "title"         => @profile.name,
      "version"       => @profile.profile_version || "1.0.0",
      "oscal-version" => @profile.oscal_version || OSCAL_VERSION,
      "last-modified" => Time.current.iso8601,
      "published"     => @profile.published,
      "props"         => [ { "name" => "resolution-tool", "value" => "SPARC" } ],
      "links"         => [ { "href" => "#", "rel" => "source-profile" } ],
      "roles"         => [ { "id" => "creator", "title" => "Document Creator" } ],
      "parties"       => [ {
        "uuid" => SecureRandom.uuid,
        "type" => "organization",
        "name" => "SPARC Export"
      } ]
    }.compact
  end

  def build_groups
    profile_controls = @profile.profile_controls
                               .order(:row_order)
                               .includes(:profile_control_fields)

    # Build a lookup of profile control data keyed by control_id
    profile_lookup = profile_controls.index_by(&:control_id)
    selected_ids = profile_lookup.keys.to_set

    # Group catalog controls by family, filtered to selected controls
    families = @catalog.control_families
                       .includes(:catalog_controls)
                       .order(:sort_order)

    groups = families.filter_map do |family|
      selected_controls = family.catalog_controls
                                .select { |cc| selected_ids.include?(cc.control_id) }
                                .sort_by(&:control_id)

      next if selected_controls.empty?

      {
        "id"       => family.code.downcase,
        "class"    => "family",
        "title"    => family.name,
        "controls" => selected_controls.map { |cc| build_control(cc, profile_lookup[cc.control_id]) }
      }
    end

    groups.presence
  end

  def build_control(catalog_control, profile_control)
    result = {
      "id"    => catalog_control.control_id,
      "class" => "SP800-53",
      "title" => catalog_control.title
    }

    # Merge params from catalog with profile parameter values
    params = build_resolved_params(catalog_control, profile_control)
    result["params"] = params if params.present?

    props = build_control_props(catalog_control, profile_control)
    result["props"] = props if props.any?

    parts = build_control_parts(catalog_control)
    result["parts"] = parts if parts.any?

    result
  end

  # Merges catalog param definitions with profile-set parameter values.
  # If the profile has a value for a parameter, it replaces the label.
  def build_resolved_params(catalog_control, profile_control)
    return [] unless catalog_control.params_present?

    # Build lookup of profile parameter values
    param_values = {}
    if profile_control
      profile_control.profile_control_fields.each do |field|
        next unless field.field_name.start_with?("parameter:") && !field.field_name.start_with?("parameter_label:")
        param_id = field.field_name.delete_prefix("parameter:")
        param_values[param_id] = field.field_value if field.field_value.present?
      end
    end

    catalog_control.params_list.map do |param|
      resolved = param.dup
      if param_values[param["id"]].present?
        resolved["label"] = param_values[param["id"]]
      end
      resolved
    end
  end

  def build_control_props(catalog_control, profile_control)
    props = []
    props << { "name" => "label", "value" => catalog_control.display_id }
    if catalog_control.sort_id.present?
      props << { "name" => "sort-id", "value" => catalog_control.sort_id }
    end

    # Use profile priority if set, otherwise fall back to catalog priority
    priority = profile_control&.priority.presence || catalog_control.priority.presence
    props << { "name" => "priority", "value" => priority } if priority.present?

    if catalog_control.baseline_impact.present?
      catalog_control.baseline_impact.split(",").map(&:strip).each do |level|
        props << { "name" => "impact-level", "value" => level }
      end
    end

    props
  end

  def build_control_parts(catalog_control)
    parts = []
    guidance = catalog_control.guidance_data || {}

    if guidance["statement"].present?
      parts << {
        "id"    => "#{catalog_control.control_id}_smt",
        "name"  => "statement",
        "prose" => guidance["statement"]
      }
    end

    if guidance["supplemental_guidance"].present?
      guidance_part = {
        "id"    => "#{catalog_control.control_id}_gdn",
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
end
