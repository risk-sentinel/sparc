# Generates a Security Assessment Plan (SAP) document from existing SSP,
# Profile, and CDEF data.  Pulls control lists from the SSP (or Profile
# if no SSP is provided), auto-populates assessment objectives from
# catalog guidance, and maps InSpec/CDEF test cases where available.
#
# Usage:
#   sap = SapGeneratorService.new(
#     name: "FY26 Annual Assessment",
#     ssp_document: ssp,
#     profile_document: profile,
#     assessment_type: "annual",
#     assessment_start: Date.today,
#     assessment_end: Date.today + 30,
#     selected_control_ids: ["AC-1", "AC-2"],
#     assessment_methods: { "AC-1" => "examine", "AC-2" => "test" }
#   ).generate
#
class SapGeneratorService
  def initialize(name:, ssp_document: nil, profile_document: nil,
                 assessment_type: "initial", assessment_start: nil,
                 assessment_end: nil, description: nil,
                 selected_control_ids: nil, assessment_methods: nil)
    @name = name
    @ssp = ssp_document
    @profile = profile_document
    @assessment_type = assessment_type
    @assessment_start = assessment_start
    @assessment_end = assessment_end
    @description = description
    @selected_ids = selected_control_ids
    @method_overrides = assessment_methods || {}
  end

  def generate
    controls_data = gather_controls
    controls_data = filter_controls(controls_data) if @selected_ids.present?
    enrich_with_catalog_guidance(controls_data)
    enrich_with_cdef_mappings(controls_data)

    create_sap_document(controls_data)
  end

  private

  def gather_controls
    if @ssp.present?
      gather_from_ssp
    elsif @profile.present?
      gather_from_profile
    else
      []
    end
  end

  def gather_from_ssp
    @ssp.ssp_controls.includes(:ssp_control_fields).map do |ctrl|
      field_map = ctrl.ssp_control_fields.index_by(&:field_name)

      {
        control_id: ctrl.control_id,
        title: ctrl.title,
        implementation_status: field_map["status"]&.field_value,
        implementation_description: field_map["private_implementation"]&.field_value ||
                                    field_map["public_implementation"]&.field_value,
        objective: nil,
        test_case: nil,
        assessment_method: default_method_for_control(ctrl.control_id)
      }
    end
  end

  def gather_from_profile
    @profile.profile_controls.includes(:profile_control_fields).map do |ctrl|
      {
        control_id: ctrl.control_id,
        title: ctrl.title,
        implementation_status: nil,
        implementation_description: nil,
        objective: nil,
        test_case: nil,
        assessment_method: default_method_for_control(ctrl.control_id)
      }
    end
  end

  def filter_controls(controls_data)
    id_set = @selected_ids.map(&:upcase).to_set
    controls_data.select { |c| id_set.include?(c[:control_id].to_s.upcase) }
  end

  def enrich_with_catalog_guidance(controls_data)
    control_ids = controls_data.map { |c| c[:control_id] }.compact
    return if control_ids.empty?

    catalog_controls = CatalogControl.where(control_id: control_ids)
                                     .index_by(&:control_id)

    controls_data.each do |cd|
      cat_ctrl = catalog_controls[cd[:control_id]]
      next unless cat_ctrl

      cd[:title] ||= cat_ctrl.title
      guidance = cat_ctrl.guidance_data
      if guidance.is_a?(Hash)
        cd[:objective] ||= guidance["assessment_objective"] || guidance["description"]
      end
      cd[:objective] ||= cat_ctrl.description
    end
  end

  def enrich_with_cdef_mappings(controls_data)
    control_ids = controls_data.map { |c| c[:control_id] }.compact
    return if control_ids.empty?

    cdef_controls = CdefControl.includes(:cdef_control_fields)
                               .where(control_id: control_ids)

    cdef_by_id = {}
    cdef_controls.each do |cc|
      cdef_by_id[cc.control_id] ||= []
      cdef_by_id[cc.control_id] << cc
    end

    controls_data.each do |cd|
      cdefs = cdef_by_id[cd[:control_id]]
      next unless cdefs&.any?

      cdef = cdefs.first
      field_map = cdef.cdef_control_fields.index_by(&:field_name)

      check = field_map["check_content"]&.field_value
      cd[:test_case] ||= check if check.present?

      if cd[:assessment_method] == "examine" && check.present?
        cd[:assessment_method] = "test"
      end
    end
  end

  def create_sap_document(controls_data)
    sap = SapDocument.create!(
      name: @name,
      ssp_document: @ssp,
      profile_document: @profile,
      status: "completed",
      assessment_type: @assessment_type,
      assessment_start: @assessment_start,
      assessment_end: @assessment_end,
      description: @description
    )

    controls_data.each_with_index do |cd, idx|
      method = @method_overrides[cd[:control_id]].presence || cd[:assessment_method]

      sap_control = sap.sap_controls.create!(
        control_id: cd[:control_id],
        title: cd[:title],
        assessment_method: method,
        assessment_status: "planned",
        objective: cd[:objective],
        test_case: cd[:test_case],
        row_order: idx
      )

      fields = []
      if cd[:implementation_description].present?
        fields << { field_name: "implementation_description", field_value: cd[:implementation_description] }
      end
      if cd[:implementation_status].present?
        fields << { field_name: "implementation_status", field_value: cd[:implementation_status] }
      end

      fields.each do |f|
        sap_control.sap_control_fields.create!(
          field_name: f[:field_name],
          field_value: f[:field_value]
        )
      end
    end

    sap
  end

  def default_method_for_control(control_id)
    return "examine" if control_id.blank?

    family = control_id.to_s.split("-").first.upcase
    # Controls that typically need interview-based assessment
    interview_families = %w[AT PS PE]
    # Controls that typically need technical testing
    test_families = %w[AC AU CM IA SC SI]

    if test_families.include?(family)
      "test"
    elsif interview_families.include?(family)
      "interview"
    else
      "examine"
    end
  end
end
