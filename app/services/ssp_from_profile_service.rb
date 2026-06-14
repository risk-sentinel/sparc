# Creates an SspDocument with controls and fields from a published
# ProfileDocument's resolved_catalog_json.  Each control in the resolved
# catalog becomes an SspControl with pre-populated read-only fields
# (stated_requirement, description) and empty editable placeholder fields
# (status, control_type, responsible_entities, etc.).
#
# A "this-system" SspComponent, a default SspInformationType, and a
# default SspUser are scaffolded so the SSP is enrichment-ready.
#
# Usage:
#   service = SspFromProfileService.new(profile_document, name: "My SSP")
#   ssp = service.create
#
class SspFromProfileService
  include BatchInsertable

  PRIORITY_TO_SEVERITY = {
    "P1" => "high",
    "P2" => "medium",
    "P3" => "low"
  }.freeze

  def initialize(profile_document, name: nil)
    @profile = profile_document
    @name    = name.presence || "SSP from #{profile_document.name}"
  end

  def create
    validate!

    @document = SspDocument.create!(
      name:                @name,
      creation_method:     "profile",
      file_type:           "json",
      status:              "completed",
      lifecycle_status:    "started",
      oscal_version:       metadata["oscal-version"] || "1.1.2",
      description:         metadata["title"],
      profile_document_id: @profile.id,
      import_metadata:     profile_import_metadata
    )

    @this_system = create_this_system_component
    create_default_information_type
    create_default_user

    imported_ids = build_controls_from_catalog(catalog)
    create_by_component_records(imported_ids)

    @document
  end

  # #628 — populate an EXISTING empty SSP from a published profile, giving a
  # metadata-only shell a control basis instead of a dead end. Preserves the
  # user's name/description; only fills blanks, scaffolds missing OSCAL
  # entities, links the profile, and imports controls.
  def populate(document)
    validate!
    raise ArgumentError, "SSP already has controls" if document.ssp_controls.exists?

    @document = document
    ActiveRecord::Base.transaction do
      document.update!(profile_link_attrs(document))
      @this_system = document.ssp_components.find_by(component_type: "this-system") ||
                     create_this_system_component
      create_default_information_type unless document.ssp_information_types.exists?
      create_default_user unless document.ssp_users.exists?

      imported_ids = build_controls_from_catalog(catalog)
      create_by_component_records(imported_ids)
    end

    @document
  end

  private

  def validate!
    raise ArgumentError, "Profile must be published" unless @profile.lifecycle_status == "published"
    raise ArgumentError, "Profile must have a resolved catalog" if @profile.resolved_catalog_json.blank?
  end

  def catalog
    @catalog ||= @profile.resolved_catalog_json
  end

  def metadata
    @metadata ||= catalog.dig("catalog", "metadata") || {}
  end

  def profile_import_metadata
    {
      "source_type"         => "profile",
      "source_profile_id"   => @profile.id,
      "source_profile_uuid" => @profile.uuid,
      "source_profile_name" => @profile.name,
      "format"              => "resolved_catalog"
    }
  end

  # Attributes applied when linking a profile to an existing SSP. Fills
  # description/oscal_version/creation_method only when blank so a user's
  # edits survive.
  def profile_link_attrs(document)
    attrs = {
      profile_document_id: @profile.id,
      import_metadata:     profile_import_metadata
    }
    attrs[:creation_method] = "profile" if document.creation_method.blank?
    attrs[:description]      = metadata["title"] if document.description.blank?
    attrs[:oscal_version]    = (metadata["oscal-version"] || "1.1.2") if document.oscal_version.blank?
    attrs
  end

  def create_this_system_component
    @document.ssp_components.create!(
      uuid:           SecureRandom.uuid,
      component_type: "this-system",
      title:          @document.name,
      description:    "This system — #{@document.name}",
      status_state:   "under-development"
    )
  end

  def create_default_information_type
    @document.ssp_information_types.create!(
      uuid:        SecureRandom.uuid,
      title:       "General Information",
      description: "Default information type — update via enrichment."
    )
  end

  def create_default_user
    @document.ssp_users.create!(
      uuid:        SecureRandom.uuid,
      title:       "System Administrator",
      description: "Default administrative user — update via enrichment."
    )
  end

  def build_controls_from_catalog(catalog)
    groups = catalog.dig("catalog", "groups") || []
    control_attrs = []
    field_entries = []
    row_order = 0

    groups.each do |group|
      (group["controls"] || []).each do |control|
        idx = control_attrs.size

        control_attrs << {
          control_id: control["id"],
          title:      control["title"],
          row_order:  row_order
        }

        # Pre-populated read-only fields
        statement = extract_part_prose(control, "statement")
        guidance  = extract_part_prose(control, "guidance")

        field_entries << [ idx, "stated_requirement", statement ] if statement.present?
        field_entries << [ idx, "description", guidance ]         if guidance.present?

        # Editable placeholder fields
        field_entries << [ idx, "status", "Deferred" ]
        field_entries << [ idx, "control_type", "" ]
        field_entries << [ idx, "responsible_entities", "" ]
        field_entries << [ idx, "implementation_statement", "" ]
        field_entries << [ idx, "implementation_summary", "" ]
        field_entries << [ idx, "notes", "" ]

        row_order += 1
      end
    end

    batch_insert_records(
      control_class: SspControl,
      field_class:   SspControlField,
      document_fk:   :ssp_document_id,
      control_attrs: control_attrs,
      field_entries: field_entries
    )
  end

  def create_by_component_records(imported_control_ids)
    records = imported_control_ids.map do |control_id|
      SspByComponent.new(
        ssp_control_id:        control_id,
        ssp_component_id:      @this_system.id,
        uuid:                  SecureRandom.uuid,
        implementation_status: "planned"
      )
    end

    SspByComponent.import(records, validate: false) if records.any?
  end

  def extract_part_prose(control, part_name)
    parts = control["parts"]
    return nil unless parts.is_a?(Array)

    part = parts.find { |p| p["name"] == part_name }
    part&.dig("prose")
  end
end
