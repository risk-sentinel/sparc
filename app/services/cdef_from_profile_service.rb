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

    catalog = @profile.resolved_catalog_json
    metadata = catalog.dig("catalog", "metadata") || {}

    @document = CdefDocument.create!(
      name:            @name,
      cdef_type:       "custom",
      status:          "completed",
      lifecycle_status: "started",
      oscal_version:   metadata["oscal-version"] || "1.1.2",
      description:     metadata["title"],
      import_metadata: {
        "source_type"         => "profile",
        "source_profile_id"   => @profile.id,
        "source_profile_uuid" => @profile.uuid,
        "source_profile_name" => @profile.name,
        "format"              => "resolved_catalog"
      }
    )

    build_controls_from_catalog(catalog)

    @document
  end

  private

  def validate!
    raise ArgumentError, "Profile must be published" unless @profile.lifecycle_status == "published"
    raise ArgumentError, "Profile must have a resolved catalog" if @profile.resolved_catalog_json.blank?
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

        # Editable placeholder fields
        field_entries << [ idx, "implementation_narrative", "" ]
        field_entries << [ idx, "notes", "" ]
        field_entries << [ idx, "status_override", "" ]

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
