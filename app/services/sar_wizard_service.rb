# Creates a SAR from wizard inputs: links to an optional SAP document,
# sets assessment dates, and populates controls + default findings from the SAP.
#
# Usage:
#   service = SarWizardService.new(name: "My SAR", sap_document_id: 1, ...)
#   sar_document = service.create
#
class SarWizardService
  def initialize(params)
    @params = params.to_h.with_indifferent_access
  end

  def create
    ActiveRecord::Base.transaction do
      @document = create_document
      link_sap_document
      create_default_result
      populate_controls_from_sap if @sap_document.present?
      create_default_findings if @sap_document.present?
      @document.update!(status: "completed")
      @document
    end
  end

  private

  # ── Document creation ────────────────────────────────────────────

  def create_document
    SarDocument.create!(
      name:             @params[:name],
      description:      @params[:description],
      creation_method:  "wizard",
      file_type:        "json",
      status:           "processing",
      oscal_version:    OscalSarExportService::OSCAL_VERSION,
      assessment_start: parse_datetime(@params[:assessment_start]),
      assessment_end:   parse_datetime(@params[:assessment_end])
    )
  end

  # ── SAP linkage ──────────────────────────────────────────────────

  def link_sap_document
    return if @params[:sap_document_id].blank?

    @sap_document = SapDocument.find(@params[:sap_document_id])
    @document.update!(
      sap_document: @sap_document,
      import_ap_href: "##{@sap_document.id}"
    )
  end

  # ── Default result ──────────────────────────────────────────────

  def create_default_result
    @result = @document.sar_results.create!(
      uuid:       SecureRandom.uuid,
      title:      "Assessment Results for #{@document.name}",
      description: @document.description.presence || "Assessment results.",
      start_time: @document.assessment_start || Time.current,
      end_time:   @document.assessment_end,
      position:   0
    )
  end

  # ── Populate controls from SAP ──────────────────────────────────

  def populate_controls_from_sap
    @sap_document.sap_controls.order(:row_order).each_with_index do |sap_ctrl, idx|
      sar_ctrl = @document.sar_controls.create!(
        control_id:    sap_ctrl.control_id,
        title:         sap_ctrl.title,
        row_order:     idx,
        control_family: sap_ctrl.control_id.to_s.split("-").first.upcase
      )

      # Create default fields from the SAP control's field data
      field_map = sap_ctrl.sap_control_fields.index_by(&:field_name)
      create_default_sar_fields(sar_ctrl, field_map)
    end
  end

  def create_default_sar_fields(sar_ctrl, sap_field_map)
    default_fields = {
      "result"         => "Not Tested",
      "working_status" => ""
    }

    # Copy assessment_method from SAP if present
    assessment_method = sap_field_map["assessment_method"]&.field_value
    default_fields["assessment_method"] = assessment_method if assessment_method.present?

    default_fields.each do |fname, fvalue|
      sar_ctrl.sar_control_fields.create!(
        field_name:  fname,
        field_value: fvalue,
        editable:    %w[result working_status notes_weakness recommended_fix working_comments].include?(fname)
      )
    end
  end

  # ── Default findings from SAP controls ──────────────────────────

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

  def parse_datetime(value)
    return nil if value.blank?
    Time.zone.parse(value.to_s)
  rescue ArgumentError
    nil
  end
end
