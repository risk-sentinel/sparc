# Creates a SarDocument with controls and fields from a published
# ProfileDocument's resolved_catalog_json.  Each control in the resolved
# catalog becomes a SarControl with pre-populated read-only fields
# (stated_requirement, description) and empty editable placeholder fields
# (result, working_status, notes_weakness, etc.).
#
# A default SarResult and SarFinding per control are scaffolded so the
# SAR is enrichment-ready.
#
# Usage:
#   service = SarFromProfileService.new(profile_document, name: "My SAR")
#   sar = service.create
#
class SarFromProfileService
  include BatchInsertable

  def initialize(profile_document, name: nil)
    @profile = profile_document
    @name    = name.presence || "SAR from #{profile_document.name}"
  end

  def create
    validate!

    catalog  = @profile.resolved_catalog_json
    metadata = catalog.dig("catalog", "metadata") || {}

    @document = SarDocument.create!(
      name:                @name,
      creation_method:     "profile",
      file_type:           "json",
      status:              "completed",
      lifecycle_status:    "started",
      oscal_version:       metadata["oscal-version"] || "1.1.2",
      description:         "Assessment results for #{@profile.name}",
      profile_document_id: @profile.id,
      import_metadata:     {
        "source_type"         => "profile",
        "source_profile_id"   => @profile.id,
        "source_profile_uuid" => @profile.uuid,
        "source_profile_name" => @profile.name,
        "format"              => "resolved_catalog"
      }
    )

    build_controls_from_catalog(catalog)
    create_default_result
    create_default_findings

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

        # Editable placeholder fields for assessment
        field_entries << [ idx, "result", "" ]
        field_entries << [ idx, "working_status", "" ]
        field_entries << [ idx, "notes_weakness", "" ]
        field_entries << [ idx, "recommended_fix", "" ]
        field_entries << [ idx, "working_comments", "" ]
        field_entries << [ idx, "date", "" ]

        row_order += 1
      end
    end

    batch_insert_records(
      control_class: SarControl,
      field_class:   SarControlField,
      document_fk:   :sar_document_id,
      control_attrs: control_attrs,
      field_entries: field_entries
    )
  end

  # ── Default result ──────────────────────────────────────────────

  def create_default_result
    @result = @document.sar_results.create!(
      uuid:        SecureRandom.uuid,
      title:       "Assessment Results for #{@document.name}",
      description: "Assessment results generated from profile #{@profile.name}.",
      start_time:  Time.current,
      position:    0
    )
  end

  # ── Default findings per control ────────────────────────────────

  def create_default_findings
    @document.sar_controls.each do |sar_ctrl|
      next if sar_ctrl.control_id.blank?

      control_id = normalize_control_id(sar_ctrl.control_id)

      @result.sar_findings.create!(
        uuid:        SecureRandom.uuid,
        title:       "Finding for #{sar_ctrl.control_id}",
        description: "Assessment finding for control #{sar_ctrl.control_id}",
        target_data: {
          "type"      => "objective-id",
          "target-id" => control_id,
          "status"    => { "state" => "not-satisfied" }
        }
      )
    end
  end

  # ── Helpers ──────────────────────────────────────────────────────

  def extract_part_prose(control, part_name)
    parts = control["parts"]
    return nil unless parts.is_a?(Array)

    part = parts.find { |p| p["name"] == part_name }
    part&.dig("prose")
  end

  def normalize_control_id(raw_id)
    return "unknown" if raw_id.blank?
    raw_id.strip
          .downcase
          .gsub(/\s+/, "-")
          .gsub("(", ".")
          .gsub(")", "")
          .gsub(/\.{2,}/, ".")
          .gsub(/-\./, ".")
  end
end
