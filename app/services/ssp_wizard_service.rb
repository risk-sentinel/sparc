# Creates a complete SSP from wizard inputs: a Profile baseline, optional CDEFs,
# and system characteristics.  Runs in a single transaction.
#
# Usage:
#   service = SspWizardService.new(name: "My SSP", profile_document_id: 1, ...)
#   ssp_document = service.create
#
class SspWizardService
  def initialize(params)
    @params = params.to_h.with_indifferent_access
  end

  def create
    ActiveRecord::Base.transaction do
      @document = create_document
      @this_system = create_this_system_component
      create_default_information_type
      create_default_user
      import_cdef_components if selected_cdef_ids.any?
      populate_controls_from_profile
      auto_fill_from_cdefs if selected_cdef_ids.any?
      @document.update!(status: "completed")
      @document
    end
  end

  private

  # ── Document creation ────────────────────────────────────────────

  def create_document
    SspDocument.create!(
      name:                              @params[:name],
      description:                       @params[:description],
      creation_method:                   "wizard",
      file_type:                         "json",
      status:                            "processing",
      profile_document_id:               @params[:profile_document_id],
      system_status:                     @params[:system_status].presence || "operational",
      security_sensitivity_level:        @params[:security_sensitivity_level],
      security_objective_confidentiality: @params[:security_objective_confidentiality], # lgtm[rb/clear-text-storage-sensitive-data] FIPS 199 impact levels, not secrets
      security_objective_integrity:      @params[:security_objective_integrity],
      security_objective_availability:   @params[:security_objective_availability],
      authorization_boundary_description: @params[:authorization_boundary_description],
      oscal_version:                     OscalSspExportService::OSCAL_VERSION
    )
  end

  # ── OSCAL-required defaults ──────────────────────────────────────

  def create_this_system_component
    @document.ssp_components.create!(
      uuid:           SecureRandom.uuid,
      component_type: "this-system",
      title:          @document.name,
      description:    @document.description.presence || "The system described by this SSP.",
      status_state:   @document.system_status
    )
  end

  def create_default_information_type
    @document.ssp_information_types.create!(
      uuid:        SecureRandom.uuid,
      title:       "System Information",
      description: "Information processed, stored, or transmitted by #{@document.name}."
    )
  end

  def create_default_user
    @document.ssp_users.create!(
      uuid:         SecureRandom.uuid,
      title:        "General User",
      role_ids_data: [ "system-owner" ]
    )
  end

  # ── CDEF component import ────────────────────────────────────────

  def selected_cdef_ids
    @selected_cdef_ids ||= Array(@params[:cdef_document_ids]).reject(&:blank?)
  end

  def import_cdef_components
    @cdef_components = {}
    selected_cdef_ids.each do |cdef_id|
      cdef = CdefDocument.find(cdef_id)
      SspDocumentCdefDocument.create!(ssp_document: @document, cdef_document: cdef)

      component = @document.ssp_components.create!(
        uuid:            SecureRandom.uuid,
        component_type:  "software",
        title:           cdef.name,
        description:     cdef.description.presence || "Component from #{cdef.name}",
        cdef_document_id: cdef.id,
        status_state:    "operational"
      )
      @cdef_components[cdef.id] = component
    end
  end

  # ── Control population from profile ──────────────────────────────

  def populate_controls_from_profile
    profile = ProfileDocument.find(@params[:profile_document_id])
    controls = profile.profile_controls.order(:row_order)

    controls.each_with_index do |pc, idx|
      ssp_ctrl = @document.ssp_controls.create!(
        control_id: pc.control_id,
        title:      pc.title,
        row_order:  idx
      )

      create_default_ssp_fields(ssp_ctrl)

      ssp_ctrl.ssp_by_components.create!(
        ssp_component: @this_system,
        uuid:          SecureRandom.uuid,
        implementation_status: "planned"
      )
    end
  end

  def create_default_ssp_fields(ssp_ctrl)
    default_fields = {
      "status"                 => "Deferred",
      "type_use_as"            => "",
      "provided_as"            => "",
      "control_origination"    => "",
      "responsible_entities"   => "",
      "private_implementation" => "",
      "public_implementation"  => "",
      "expected_completion"    => "",
      "notes"                  => ""
    }
    default_fields.each do |fname, fvalue|
      ssp_ctrl.ssp_control_fields.create!(field_name: fname, field_value: fvalue)
    end
  end

  # ── Auto-fill from CDEFs ─────────────────────────────────────────

  def auto_fill_from_cdefs
    ssp_controls_by_id = @document.ssp_controls
                                   .includes(:ssp_control_fields)
                                   .index_by { |c| normalize_id(c.control_id) }

    selected_cdef_ids.each do |cdef_id|
      cdef = CdefDocument.find(cdef_id)
      component = @cdef_components[cdef.id.to_i] || @cdef_components[cdef.id]

      cdef.cdef_controls.includes(:cdef_control_fields).find_each do |cc|
        nist_ids = extract_nist_ids(cc)
        nist_ids.each do |nist_id|
          ssp_ctrl = ssp_controls_by_id[normalize_id(nist_id)]
          next unless ssp_ctrl

          apply_cdef_to_control(ssp_ctrl, cc, component)
        end
      end
    end
  end

  def extract_nist_ids(cdef_control)
    field_map = cdef_control.cdef_control_fields.index_by(&:field_name)
    nist_field = field_map["nist_controls"]&.field_value
    if nist_field.present?
      nist_field.split(",").map(&:strip)
    elsif cdef_control.control_id.to_s.match?(/\A[A-Z]{2}-/i)
      [ cdef_control.control_id ]
    else
      []
    end
  end

  def apply_cdef_to_control(ssp_ctrl, cdef_ctrl, component)
    field_map = cdef_ctrl.cdef_control_fields.index_by(&:field_name)
    ssp_field_map = ssp_ctrl.ssp_control_fields.index_by(&:field_name)

    narrative = field_map["implementation_narrative"]&.field_value

    if narrative.present? && ssp_field_map["private_implementation"]&.field_value.blank?
      ssp_field_map["private_implementation"]&.update!(field_value: narrative)
    end

    if narrative.present? && ssp_field_map["status"]&.field_value == "Deferred"
      ssp_field_map["status"]&.update!(field_value: "Implemented")
    end

    return unless component
    return if ssp_ctrl.ssp_by_components.exists?(ssp_component: component)

    ssp_ctrl.ssp_by_components.create!(
      ssp_component:         component,
      uuid:                  SecureRandom.uuid,
      description:           narrative,
      implementation_status: narrative.present? ? "implemented" : "planned"
    )
  end

  def normalize_id(raw)
    return "" if raw.blank?
    raw.to_s.strip.downcase
       .gsub(/\s+/, "-")
       .gsub("(", ".")
       .gsub(")", "")
       .gsub(/\.{2,}/, ".")
       .gsub(/-\./, ".")
  end
end
