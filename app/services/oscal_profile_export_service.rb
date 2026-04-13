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
  DEFAULT_OSCAL_VERSION = OscalSchema::DEFAULT_VERSION
  OSCAL_VERSION = DEFAULT_OSCAL_VERSION # backward compat

  def initialize(profile_document)
    @document = profile_document
  end

  def export
    data = build_profile
    OscalSchemaValidationService.validate!(:profile, data, version: effective_oscal_version)
    JSON.pretty_generate(data)
  end

  def export_unvalidated
    JSON.pretty_generate(build_profile)
  end

  def validation_result
    data = build_profile
    OscalSchemaValidationService.validate(:profile, data)
  end


  def effective_oscal_version
    @document.oscal_version.presence || DEFAULT_OSCAL_VERSION
  end

  private

  def build_profile
    {
      "profile" => {
        "uuid"         => @document.uuid,
        "metadata"     => build_metadata,
        "imports"      => build_imports,
        "merge"        => build_merge,
        "modify"       => build_modify,
        "back-matter"  => build_back_matter
      }.compact
    }
  end

  def build_metadata
    @document.build_oscal_metadata(
      default_version: @document.profile_version || "1.0.0",
      default_roles: [
        { "id" => "creator", "title" => "Document Creator" }
      ],
      default_parties: [
        { "uuid" => SecureRandom.uuid, "type" => "organization", "name" => "SPARC Export" }
      ]
    )
  end

  def build_imports
    catalog_href = @document.import_metadata&.dig("catalog_href")
    catalog_href ||= @document.control_catalog ? "##{@document.control_catalog.oscal_uuid}" : "#"
    controls = @document.profile_controls.order(:row_order)

    [ {
      "href" => catalog_href,
      "include-controls" => [ {
        "with-ids" => controls.pluck(:control_id)
      } ]
    } ]
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
    props = []
    props << { "name" => "priority", "value" => control.priority } if control.priority.present?

    control.profile_control_fields.each do |field|
      next unless field.field_name.start_with?("prop:")
      prop_name = field.field_name.delete_prefix("prop:")
      props << { "name" => prop_name, "value" => field.field_value }
    end

    return nil if props.empty?

    {
      "control-id" => control.control_id,
      "adds" => [ { "position" => "starting", "props" => props } ]
    }
  end

  def build_set_parameters(controls)
    params = []
    controls.each do |ctrl|
      ctrl.profile_control_fields.each do |field|
        next unless field.field_name.start_with?("parameter:")
        param_id = field.field_name.delete_prefix("parameter:")
        params << {
          "param-id" => param_id,
          "values"   => field.field_value.split(", ")
        }
      end
    end
    params
  end

  def build_back_matter
    base = @document.build_oscal_back_matter
    resources = base["resources"] || []

    # Add source catalog resource entry so the import href resolves
    catalog = @document.control_catalog
    if catalog
      resources.unshift({
        "uuid"        => catalog.oscal_uuid,
        "title"       => catalog.name,
        "description" => "Source catalog for this profile",
        "rlinks"      => [ { "href" => "#{catalog.name.parameterize}.json", "media-type" => "application/json" } ]
      })
    end

    # Add source profile resource entry if this is a tailored profile
    source = @document.source_profile
    if source
      resources.unshift({
        "uuid"        => source.uuid,
        "title"       => source.name,
        "description" => "Source profile this was tailored from",
        "rlinks"      => [ { "href" => "#{source.name.parameterize}.json", "media-type" => "application/json" } ]
      })
    end

    { "resources" => resources }
  end
end
