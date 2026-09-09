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
                 selected_control_ids: nil, assessment_methods: nil,
                 authorization_boundary: nil)
    @name = name
    @ssp = ssp_document
    # #952 — an assessment plan plans the assessment of ONE system.
    @boundary = authorization_boundary || ssp_document&.authorization_boundary
    @profile = profile_document
    @assessment_type = assessment_type
    @assessment_start = assessment_start
    @assessment_end = assessment_end
    @description = description
    @selected_ids = selected_control_ids
    # #911 — keyed canonically. Callers pass the form a human writes
    # (`{ "AC-1" => "interview" }`, straight from the UI or an API body) while
    # controls are stored canonically, so a literal lookup silently applied no
    # override at all and the caller got the default method with no indication
    # their choice was ignored.
    @method_overrides = (assessment_methods || {})
                          .transform_keys { |k| ControlId.canonical(k) }
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
        implementation_description: field_map["implementation_statement"]&.field_value ||
                                    field_map["implementation_summary"]&.field_value,
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

  # #852 — matched on `upcase` alone, which is case-insensitive but NOT
  # padding-insensitive, so a selection of "ac-2" silently matched nothing
  # against a control stored as "AC-02". Both shapes genuinely coexist: the
  # demo seed writes SSP controls padded via `pad_ctrl_id` while control lists
  # are written unpadded. The result was an empty SAP reported as success.
  def filter_controls(controls_data)
    id_set = ControlId.canonical_set(@selected_ids)
    controls_data.select { |c| id_set.include?(ControlId.canonical(c[:control_id])) }
  end

  # #1114 — read the control language through the PROFILE, not around it.
  #
  # NIST's layer model is a chain — Catalog -> Profile -> SSP -> SAP — and it
  # says a profile "tailors by modifying statements, parameters and assessment
  # actions". So a plan that reads `CatalogControl` directly is reading
  # UNTAILORED text: the baseline's parameter values are not applied, and the
  # plan can describe a control the profile tailored out.
  #
  # Two concrete defects came from that, and both are fixed by reading the
  # resolved catalog the profile already publishes:
  #
  #   * `guidance_data["assessment_objective"]` is the RAW blob. Measured on the
  #     seeded catalog, ac-1 carries 1,966 characters of it containing
  #     `{{ insert: param, ac-01_odp.01 }}` — so a generated plan told an
  #     assessor to determine something with the organisation-defined value still
  #     written as markup. It is blank on the seeded plan only because that plan
  #     predates this path running.
  #   * the objective arrived as ONE flattened string, which is the other half of
  #     what the per-objective work (#1114) exists to replace.
  #
  # The resolved catalog has parameters already substituted, per part, and
  # recursively (#942) — so correcting the READ PATH is what fixes the
  # parameters. There is no second substitution step here, and there must not
  # be: a copy of that logic would be a copy to drift.
  #
  # The direct-catalog read remains the FALLBACK for a plan generated with no
  # profile in reach, and its text is run through the same resolver rather than
  # emitted raw.
  def enrich_with_catalog_guidance(controls_data)
    control_ids = controls_data.map { |c| c[:control_id] }.compact
    return if control_ids.empty?

    resolved = resolved_catalog_controls
    catalog_controls = CatalogControl.where(control_id: control_ids).index_by(&:control_id)

    controls_data.each do |cd|
      node = resolved[ControlId.canonical(cd[:control_id]).to_s.downcase]
      cat_ctrl = catalog_controls[cd[:control_id]]

      cd[:title] ||= node && node["title"]
      cd[:title] ||= cat_ctrl&.title

      cd[:objective] ||= objective_from_resolved(node)
      next if cd[:objective].present? || cat_ctrl.nil?

      # Fallback: no profile, or a profile whose resolved catalog does not carry
      # this control. Resolve the parameters rather than handing an assessor
      # `{{ insert: param, ... }}`.
      resolver = OscalParameterResolver.new(
        cat_ctrl.effective_params_list.presence || cat_ctrl.params_list, {}
      )
      guidance = cat_ctrl.guidance_data
      raw = (guidance.is_a?(Hash) ? (guidance["assessment_objective"] || guidance["description"]) : nil)
      raw = cat_ctrl.description if raw.blank?
      cd[:objective] = resolver.resolve_text(raw) if raw.present?
    end
  end

  # The profile's published catalog, keyed by canonical control id. Empty when no
  # profile is reachable — `gather_controls` already prefers the SSP, so the
  # profile is found through it when the plan was generated from one.
  def resolved_catalog_controls
    profile = @profile || @ssp&.profile_document
    json = profile&.resolved_catalog_json
    return {} if json.blank?

    catalog = json.is_a?(Hash) ? (json["catalog"] || json) : {}
    nodes = Array(catalog["controls"]) +
            Array(catalog["groups"]).flat_map { |g| Array(g["controls"]) }
    nodes.index_by { |c| ControlId.canonical(c["id"]).to_s.downcase }
  rescue StandardError
    {}
  end

  # The control's assessment objectives, as PROSE for the legacy single-field
  # `objective` column. The per-objective rows are created separately by
  # `ControlObjectiveExtractorService`, which walks the same tree; this keeps the
  # old column populated for callers and exports that still read it, with the
  # parameters already substituted.
  def objective_from_resolved(node)
    return nil if node.blank?

    prose = []
    walk = lambda do |parts|
      Array(parts).each do |part|
        prose << part["prose"].to_s.strip if part["name"] == "assessment-objective" && part["prose"].present?
        walk.call(part["parts"])
      end
    end
    walk.call(node["parts"])
    prose.presence&.join("\n")
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
      authorization_boundary: @boundary,
      profile_document: @profile,
      status: "completed",
      assessment_type: @assessment_type,
      assessment_start: @assessment_start,
      assessment_end: @assessment_end,
      description: @description
    )

    controls_data.each_with_index do |cd, idx|
      method = @method_overrides[ControlId.canonical(cd[:control_id])].presence || cd[:assessment_method]

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
