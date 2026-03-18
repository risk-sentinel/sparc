# Creates a SarDocument with controls copied from an existing SspDocument.
# Each SSP control becomes a SarControl with read-only context fields
# (stated_requirement, description, ssp_status) and editable assessment
# placeholder fields (result, working_status, notes_weakness, etc.).
#
# A default SarResult and SarFinding per control are scaffolded so the
# SAR is enrichment-ready.
#
# Usage:
#   service = SarFromSspService.new(ssp_document, name: "My SAR")
#   sar = service.create
#
class SarFromSspService
  def initialize(ssp_document, name: nil)
    @ssp  = ssp_document
    @name = name.presence || "SAR from #{ssp_document.name}"
  end

  def create
    validate!

    ActiveRecord::Base.transaction do
      @document = create_document
      build_controls_from_ssp
      create_default_result
      create_default_findings
    end

    @document
  end

  private

  def validate!
    raise ArgumentError, "SSP must be completed" unless @ssp.status == "completed"
  end

  def create_document
    SarDocument.create!(
      name:                @name,
      creation_method:     "ssp",
      file_type:           "json",
      status:              "completed",
      lifecycle_status:    "started",
      oscal_version:       @ssp.oscal_version || "1.1.2",
      description:         "Assessment results for #{@ssp.name}",
      ssp_document_id:     @ssp.id,
      profile_document_id: @ssp.profile_document_id,
      import_metadata:     {
        "source_type"     => "ssp",
        "source_ssp_id"   => @ssp.id,
        "source_ssp_uuid" => @ssp.uuid,
        "source_ssp_name" => @ssp.name,
        "format"          => "ssp_controls"
      }
    )
  end

  def build_controls_from_ssp
    @ssp.ssp_controls.order(:row_order).includes(:ssp_control_fields).each_with_index do |ssp_ctrl, idx|
      sar_ctrl = @document.sar_controls.create!(
        control_id:     ssp_ctrl.control_id,
        title:          ssp_ctrl.title,
        row_order:      idx,
        control_family: ssp_ctrl.control_id.to_s.split("-").first&.upcase
      )

      # Copy SSP read-only context fields
      ssp_fields = ssp_ctrl.ssp_control_fields.index_by(&:field_name)

      create_context_field(sar_ctrl, "stated_requirement", ssp_fields["stated_requirement"]&.field_value)
      create_context_field(sar_ctrl, "description", ssp_fields["description"]&.field_value)
      create_context_field(sar_ctrl, "ssp_status", ssp_fields["status"]&.field_value)

      # Editable SAR assessment fields
      create_editable_field(sar_ctrl, "result", "")
      create_editable_field(sar_ctrl, "working_status", "")
      create_editable_field(sar_ctrl, "notes_weakness", "")
      create_editable_field(sar_ctrl, "recommended_fix", "")
      create_editable_field(sar_ctrl, "working_comments", "")
      create_editable_field(sar_ctrl, "date", "")
    end
  end

  def create_context_field(control, field_name, value)
    return if value.blank?

    control.sar_control_fields.create!(
      field_name:  field_name,
      field_value: value,
      editable:    false
    )
  end

  def create_editable_field(control, field_name, value)
    control.sar_control_fields.create!(
      field_name:  field_name,
      field_value: value,
      editable:    SarControlField::EDITABLE_FIELDS.include?(field_name)
    )
  end

  # ── Default result ──────────────────────────────────────────────

  def create_default_result
    @result = @document.sar_results.create!(
      uuid:        SecureRandom.uuid,
      title:       "Assessment Results for #{@document.name}",
      description: "Assessment results generated from SSP #{@ssp.name}.",
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
