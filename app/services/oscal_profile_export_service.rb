# Builds an OSCAL v1.1.2 Profile JSON document from a ProfileDocument
# and its controls.  Validates the output against the official NIST
# JSON schema before returning.
#
# Usage:
#   service = OscalProfileExportService.new(profile_document)
#   json_string = service.export            # validates, raises on failure
#   json_string = service.export_unvalidated # skips validation
#   result      = service.validation_result  # inspect errors without raising
#
class OscalProfileExportService
  OSCAL_VERSION = "1.1.2"

  def initialize(profile_document)
    @document = profile_document
  end

  def export
    data = build_profile
    OscalSchemaValidationService.validate!(:profile, data)
    JSON.pretty_generate(data)
  end

  def export_unvalidated
    JSON.pretty_generate(build_profile)
  end

  def validation_result
    data = build_profile
    OscalSchemaValidationService.validate(:profile, data)
  end

  private

  def build_profile
    result = {
      "profile" => {
        "uuid"     => @document.import_metadata&.dig("uuid") || SecureRandom.uuid,
        "metadata" => build_metadata,
        "imports"  => build_imports,
        "merge"    => build_merge,
        "modify"   => build_modify
      }.compact
    }

    back_matter = build_back_matter
    result["profile"]["back-matter"] = back_matter if back_matter.present?

    result
  end

  def build_metadata
    base = {
      "title"         => @document.name,
      "version"       => @document.profile_version || "1.0.0",
      "oscal-version" => @document.oscal_version || OSCAL_VERSION,
      "last-modified" => Time.current.iso8601
    }

    extra = @document.metadata_extra || {}
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

  def build_imports
    catalog_href = @document.import_metadata&.dig("catalog_href") || "#"
    controls = @document.profile_controls.order(:row_order)

    include_all = @document.import_metadata&.dig("include_all")

    import_entry = { "href" => catalog_href }

    if include_all
      import_entry["include-all"] = {}
    else
      included = controls.where(exclude: false).pluck(:control_id)
      import_entry["include-controls"] = [ { "with-ids" => included } ] if included.any?
    end

    excluded = controls.where(exclude: true).pluck(:control_id)
    import_entry["exclude-controls"] = [ { "with-ids" => excluded } ] if excluded.any?

    [ import_entry ]
  end

  def build_merge
    @document.import_metadata&.dig("merge") || { "as-is" => true }
  end

  def build_modify
    controls = @document.profile_controls
                        .order(:row_order)
                        .includes(:profile_control_fields)

    alters         = controls.filter_map { |ctrl| build_alter(ctrl) }
    set_parameters = build_set_parameters(controls)

    result = {}
    result["set-parameters"] = set_parameters if set_parameters.any?
    result["alters"]         = alters         if alters.any?
    result.presence
  end

  def build_alter(control)
    return nil if control.exclude?

    props = []
    props << { "name" => "priority", "value" => control.priority } if control.priority.present?

    control.profile_control_fields.each do |field|
      next unless field.field_name.start_with?("prop:")
      prop_name = field.field_name.delete_prefix("prop:")
      props << { "name" => prop_name, "value" => field.field_value }
    end

    # Build removes from alters_data
    removes = control.try(:alters_data).presence || []

    return nil if props.empty? && removes.empty?

    alter = { "control-id" => control.control_id }
    alter["removes"] = removes if removes.any?
    alter["adds"] = [ { "position" => "starting", "props" => props } ] if props.any?

    alter
  end

  def build_set_parameters(controls)
    params = []
    controls.each do |ctrl|
      next if ctrl.exclude?

      ctrl.profile_control_fields.each do |field|
        next unless field.field_name.start_with?("parameter:")
        param_id = field.field_name.delete_prefix("parameter:")
        param_entry = {
          "param-id" => param_id,
          "values"   => field.field_value.split(", ")
        }

        # Include full parameter attributes if stored
        %w[class constraints guidelines select].each do |attr|
          attr_field = ctrl.profile_control_fields.find { |f| f.field_name == "parameter_#{attr}:#{param_id}" }
          if attr_field&.field_value.present?
            parsed = JSON.parse(attr_field.field_value) rescue nil
            param_entry[attr] = parsed if parsed
          end
        end

        params << param_entry
      end
    end
    params
  end

  def build_back_matter
    resources = @document.try(:back_matter_data).presence ||
                @document.import_metadata&.dig("back_matter")
    return nil if resources.blank? || resources.empty?

    { "resources" => resources }
  end
end
