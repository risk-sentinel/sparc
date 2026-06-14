# Creates a CdefDocument with controls and fields from a published
# ProfileDocument's resolved_catalog_json.  Each control in the resolved
# catalog becomes a CdefControl with pre-populated read-only fields
# (description, guidance, parameters) and empty editable fields
# (implementation_narrative, notes, status_override).
#
# Usage:
#   service = CdefFromProfileService.new(profile_document, name: "My CDEF")
#   cdef = service.create
#
class CdefFromProfileService
  include BatchInsertable

  PRIORITY_TO_SEVERITY = {
    "P1" => "high",
    "P2" => "medium",
    "P3" => "low"
  }.freeze

  def initialize(profile_document, name: nil)
    @profile = profile_document
    @name    = name.presence || "CDEF from #{profile_document.name}"
  end

  def create
    validate!

    # #498 slice 3 — route construction through CdefMutationService so
    # the assembled CDEF's OSCAL is validated before commit; a profile
    # that resolves to a structurally-bad catalog rolls back instead
    # of leaving an unusable CDEF in the database.
    CdefMutationService.build_and_apply do
      @document = CdefDocument.create!(
        name:                @name,
        cdef_type:           "custom",
        status:              "completed",
        lifecycle_status:    "started",
        oscal_version:       metadata["oscal-version"] || "1.1.2",
        description:         metadata["title"],
        profile_document_id: @profile.id,
        import_metadata:     profile_import_metadata
      )

      build_controls_from_catalog(catalog)
      @document
    end
  end

  # #628 — populate an EXISTING empty CDEF from a published profile, giving a
  # metadata-only shell a control basis instead of a dead end. Preserves any
  # user-entered name/description; only fills blanks and links the profile.
  def populate(document)
    validate!
    raise ArgumentError, "Component definition already has controls" if document.cdef_controls.exists?
    raise ArgumentError, "Component definition is read-only" unless document.editable?

    @document = document
    CdefMutationService.apply(document) do |doc|
      doc.update!(profile_link_attrs(doc))
      build_controls_from_catalog(catalog)
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

  # Attributes applied when linking a profile to an existing CDEF. Fills
  # description/oscal_version only when blank so a user's edits survive.
  def profile_link_attrs(document)
    attrs = {
      profile_document_id: @profile.id,
      import_metadata:     profile_import_metadata
    }
    attrs[:description]   = metadata["title"] if document.description.blank?
    attrs[:oscal_version] = (metadata["oscal-version"] || "1.1.2") if document.oscal_version.blank?
    attrs
  end

  def build_controls_from_catalog(catalog)
    groups = catalog.dig("catalog", "groups") || []
    control_attrs = []
    field_entries = []
    row_order = 0

    groups.each do |group|
      family_code = group["id"].to_s.upcase

      (group["controls"] || []).each do |control|
        idx = control_attrs.size
        severity = extract_severity(control["props"])

        control_attrs << {
          control_id:     control["id"],
          title:          control["title"],
          control_family: family_code,
          severity:       severity,
          row_order:      row_order
        }

        # Pre-populated read-only fields
        statement = extract_part_prose(control, "statement")
        guidance  = extract_part_prose(control, "guidance")
        params    = extract_params(control)

        field_entries << [ idx, "description", statement ] if statement.present?
        field_entries << [ idx, "guidance", guidance ]      if guidance.present?
        field_entries << [ idx, "parameters", params ]      if params.present?

        # Preserve baseline priority as read-only field
        priority = extract_priority(control["props"])
        field_entries << [ idx, "baseline_priority", priority ] if priority.present?

        # Editable placeholder fields
        field_entries << [ idx, "implementation_narrative", "" ]
        field_entries << [ idx, "notes", "" ]
        field_entries << [ idx, "status_override", "" ]
        field_entries << [ idx, "implementation_status", "" ]
        field_entries << [ idx, "control_origin", "" ]
        field_entries << [ idx, "responsible_roles", "" ]
        field_entries << [ idx, "set_parameters", "" ]

        row_order += 1
      end
    end

    batch_insert_records(
      control_class: CdefControl,
      field_class:   CdefControlField,
      document_fk:   :cdef_document_id,
      control_attrs: control_attrs,
      field_entries: field_entries
    )
  end

  def extract_severity(props)
    return nil unless props.is_a?(Array)

    priority = props.find { |p| p["name"] == "priority" }&.dig("value")
    PRIORITY_TO_SEVERITY[priority]
  end

  def extract_priority(props)
    return nil unless props.is_a?(Array)

    props.find { |p| p["name"] == "priority" }&.dig("value")
  end

  def extract_part_prose(control, part_name)
    parts = control["parts"]
    return nil unless parts.is_a?(Array)

    part = parts.find { |p| p["name"] == part_name }
    part&.dig("prose")
  end

  def extract_params(control)
    params = control["params"]
    return nil unless params.is_a?(Array) && params.any?

    params.to_json
  end
end
