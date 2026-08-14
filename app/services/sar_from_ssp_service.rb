# Creates a SarDocument with controls copied from an existing SspDocument.
# Each SSP control becomes a SarControl with read-only context fields
# (stated_requirement, description, ssp_status) and editable assessment
# placeholder fields (result, working_status, notes_weakness, etc.).
#
# A default SarResult, and a SarFinding and SarRisk per control, are
# scaffolded so the SAR is enrichment-ready.
#
# Usage:
#   service = SarFromSspService.new(ssp_document, name: "My SAR")
#   sar = service.create
#
class SarFromSspService
  # Every scaffolded control is assessed not-satisfied until an assessor says
  # otherwise — that is what makes each one a risk to the authorization.
  FINDING_STATE = "not-satisfied"

  # `deadline` is normally nil: PoamGeneratorService then resolves one from the
  # organisation's RemediationTimeline SLA, which is a policy lookup rather
  # than a date this service made up. A caller pins it only when the generated
  # OSCAL must be byte-reproducible — the #845 reference estate does, because
  # an SLA-derived deadline is Time.current-relative and would put a fresh diff
  # in every regeneration.
  def initialize(ssp_document, name: nil, deadline: nil)
    @ssp      = ssp_document
    @name     = name.presence || "SAR from #{ssp_document.name}"
    @deadline = deadline
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

  # ── Default findings and risks per control ──────────────────────

  # #954 — this used to write findings ONLY, and the result was an empty POA&M
  # that reported success. PoamGeneratorService sources exclusively from
  # SarRisk (`SarRisk.where(sar_result_id: ...)`), never from SarFinding, so a
  # SAR generated from an SSP handed it nothing to convert: items=0 with
  # skipped=0, because there was no input to reject. SarJsonParserService and
  # manual authoring both create risks, which is why only this one path — the
  # path of building an authorization inside SPARC rather than importing one —
  # produced a hollow document.
  #
  # A control assessed not-satisfied IS a risk to the authorization, so the
  # risk is created here beside its finding and linked to it.
  def create_default_findings
    @document.sar_controls.includes(:sar_control_fields).each do |sar_ctrl|
      next if sar_ctrl.control_id.blank?

      finding = @result.sar_findings.create!(
        uuid:        SecureRandom.uuid,
        title:       "Finding for #{sar_ctrl.control_id}",
        description: "Assessment finding for control #{sar_ctrl.control_id}",
        target_data: {
          "type"      => "objective-id",
          "target-id" => normalize_control_id(sar_ctrl.control_id),
          "status"    => { "state" => FINDING_STATE }
        }
      )

      link_risk_to(finding, sar_ctrl)
    end
  end

  # PoamRisk::OSCAL_REQUIRED_FIELDS is title/description/statement/status, and
  # the generator SKIPS a source risk missing any of them rather than filling
  # it in. So all four are set — but `statement`, the one an assessor and an AO
  # actually read, is the control's own requirement carried over from the SSP,
  # not prose composed here. Where the SSP records no requirement, the
  # statement says exactly that instead of implying an assessment nobody made.
  def link_risk_to(finding, sar_ctrl)
    risk = @result.sar_risks.create!(
      uuid:        SecureRandom.uuid,
      title:       "Risk for #{sar_ctrl.control_id}",
      description: "Control #{sar_ctrl.control_id} was assessed #{FINDING_STATE}.",
      statement:   risk_statement_for(sar_ctrl),
      status:      "open",
      deadline:    @deadline
    )

    SarFindingRisk.create!(sar_finding: finding, sar_risk: risk)
  end

  def risk_statement_for(sar_ctrl)
    requirement = sar_ctrl.sar_control_fields
                          .find { |field| field.field_name == "stated_requirement" }
                          &.field_value

    if requirement.present?
      "#{sar_ctrl.control_id} is assessed #{FINDING_STATE}. The control requires: #{requirement}"
    else
      "#{sar_ctrl.control_id} is assessed #{FINDING_STATE}. " \
        "The SSP records no stated requirement for this control."
    end
  end

  # #852 — delegated to the one canonical implementation. This method used to
  # be one of four byte-identical private copies; ControlId.canonical
  # reproduces them exactly and additionally removes zero padding, so "AC-02"
  # and "ac-2" finally name the same control.
  def normalize_control_id(raw_id)
    ControlId.canonical(raw_id)
  end
end
