# Builds an OSCAL v1.1.2 System Security Plan (SSP) JSON document from an
# SspDocument and its relational records.  Validates the output against the
# official NIST JSON schema before returning.
#
# Unified approach: uses enriched relational data when available (regardless of
# creation_method), falling back to placeholder values only for fields with no
# data.  This means Excel-imported SSPs that have been enriched via the UI also
# get proper exports, while legacy un-enriched SSPs continue to export valid
# OSCAL with sensible defaults.
#
# Usage:
#   service = OscalSspExportService.new(ssp_document)
#   json_string = service.export            # validates, raises on failure
#   json_string = service.export_unvalidated # skips validation
#   result      = service.validation_result  # inspect errors without raising
#
class OscalSspExportService
  DEFAULT_OSCAL_VERSION = OscalSchema::DEFAULT_VERSION
  OSCAL_VERSION = DEFAULT_OSCAL_VERSION # backward compat

  def initialize(ssp_document)
    @document = ssp_document
    eager_load_associations
  end

  # Build, validate, and return pretty-printed OSCAL SSP JSON.
  def export
    data = build_ssp
    OscalSchemaValidationService.validate!(:ssp, data, version: effective_oscal_version)
    JSON.pretty_generate(data)
  end

  # Build and return OSCAL JSON without schema validation.
  def export_unvalidated
    JSON.pretty_generate(build_ssp)
  end

  # Build the document and return the validation result (does not raise).
  def validation_result
    data = build_ssp
    OscalSchemaValidationService.validate(:ssp, data)
  end


  def effective_oscal_version
    @document.oscal_version.presence || DEFAULT_OSCAL_VERSION
  end

  private

  def eager_load_associations
    @components    = @document.ssp_components.to_a
    @users         = @document.ssp_users.to_a
    @info_types    = @document.ssp_information_types.to_a
    @leveraged     = @document.ssp_leveraged_authorizations.to_a
    @inventory     = @document.ssp_inventory_items.to_a
    @controls      = @document.ssp_controls
                              .roots
                              .includes(
                                :ssp_control_fields,
                                ssp_by_components: :ssp_component,
                                provider_statements: :ssp_control_fields
                              ).to_a
  end

  # ── Top-level SSP envelope ─────────────────────────────────────────

  def build_ssp
    {
      "system-security-plan" => {
        "uuid"                     => @document.uuid,
        "metadata"                 => build_metadata,
        "import-profile"           => build_import_profile,
        "system-characteristics"   => build_system_characteristics,
        "system-implementation"    => build_system_implementation,
        "control-implementation"   => build_control_implementation,
        "back-matter"              => build_back_matter
      }.compact
    }
  end

  # ── Metadata ───────────────────────────────────────────────────────

  def build_metadata
    @document.build_oscal_metadata(
      default_version: @document.ssp_version || "1.0.0",
      default_roles: [
        { "id" => "prepared-by",     "title" => "Prepared By" },
        { "id" => "system-owner",    "title" => "System Owner" },
        { "id" => "authorizing-official", "title" => "Authorizing Official" }
      ],
      default_parties: [
        { "uuid" => SecureRandom.uuid, "type" => "organization", "name" => "SPARC Export" }
      ]
    )
  end

  # ── Import Profile ─────────────────────────────────────────────────

  def build_import_profile
    { "href" => @document.import_profile_href.presence || "#" }
  end

  # ── System Characteristics ─────────────────────────────────────────

  def build_system_characteristics
    sc = {
      "system-ids"  => build_system_ids,
      "system-name" => @document.name
    }

    sc["system-name-short"] = @document.system_name_short if @document.system_name_short.present?
    sc["description"] = @document.description.presence ||
                        "System Security Plan exported from SPARC for #{@document.name}"
    sc["security-sensitivity-level"] = @document.security_sensitivity_level if @document.security_sensitivity_level.present?
    sc["system-information"] = build_system_information
    sc["security-impact-level"] = build_security_impact_level if has_security_impact?
    sc["status"] = build_system_status
    sc["date-authorized"] = @document.date_authorized.iso8601 if @document.date_authorized.present?
    sc["authorization-boundary"] = build_authorization_boundary
    sc["network-architecture"] = { "description" => @document.network_architecture_description } if @document.network_architecture_description.present?
    sc["data-flow"] = { "description" => @document.data_flow_description } if @document.data_flow_description.present?

    sc
  end

  def build_system_ids
    if @document.system_id.present?
      [ { "id" => @document.system_id } ]
    else
      [ { "id" => @document.id.to_s } ]
    end
  end

  def build_system_information
    if @info_types.any?
      {
        "information-types" => @info_types.map { |it| build_information_type(it) }
      }
    else
      {
        "information-types" => [
          {
            "uuid"        => SecureRandom.uuid,
            "title"       => "System Information",
            "description" => "Information processed, stored, or transmitted by #{@document.name}."
          }
        ]
      }
    end
  end

  def build_information_type(it)
    entry = {
      "uuid"        => it.uuid,
      "title"       => it.title,
      "description" => it.description
    }

    entry["categorizations"] = it.categorizations_data if it.categorizations_data.present?

    ci = build_impact(it.confidentiality_impact_base, it.confidentiality_impact_selected, it.confidentiality_impact_adjustment)
    entry["confidentiality-impact"] = ci if ci

    ii = build_impact(it.integrity_impact_base, it.integrity_impact_selected, it.integrity_impact_adjustment)
    entry["integrity-impact"] = ii if ii

    ai = build_impact(it.availability_impact_base, it.availability_impact_selected, it.availability_impact_adjustment)
    entry["availability-impact"] = ai if ai

    entry
  end

  def build_impact(base, selected, adjustment)
    return nil if base.blank? && selected.blank?
    impact = {}
    impact["base"] = base if base.present?
    impact["selected"] = selected if selected.present?
    impact["adjustment-justification"] = adjustment if adjustment.present?
    impact.presence
  end

  def has_security_impact?
    @document.security_objective_confidentiality.present? ||
      @document.security_objective_integrity.present? ||
      @document.security_objective_availability.present?
  end

  def build_security_impact_level
    {
      "security-objective-confidentiality" => @document.security_objective_confidentiality,
      "security-objective-integrity"       => @document.security_objective_integrity,
      "security-objective-availability"    => @document.security_objective_availability
    }.compact
  end

  def build_system_status
    { "state" => @document.system_status.presence || "operational" }
  end

  def build_authorization_boundary
    desc = @document.authorization_boundary_description.presence ||
           "Authorization boundary for #{@document.name}. Update this description to reflect the actual boundary."
    { "description" => desc }
  end

  # ── System Implementation ──────────────────────────────────────────

  def build_system_implementation
    impl = {}

    impl["users"] = build_users
    impl["components"] = build_components

    if @leveraged.any?
      impl["leveraged-authorizations"] = @leveraged.map { |la| build_leveraged_authorization(la) }
    end

    if @inventory.any?
      impl["inventory-items"] = @inventory.map { |ii| build_inventory_item(ii) }
    end

    impl
  end

  def build_users
    if @users.any?
      @users.map { |u| build_user(u) }
    else
      [
        {
          "uuid"     => SecureRandom.uuid,
          "title"    => "General User",
          "role-ids" => [ "system-owner" ]
        }
      ]
    end
  end

  def build_user(user)
    entry = { "uuid" => user.uuid }
    entry["title"]       = user.title if user.title.present?
    entry["description"] = user.description if user.description.present?
    entry["short-name"]  = user.short_name if user.short_name.present?
    entry["role-ids"]    = user.role_ids_data if user.role_ids_data.present?
    entry["authorized-privileges"] = user.authorized_privileges_data if user.authorized_privileges_data.present?
    entry["props"]       = user.props_data if user.props_data.present?
    entry["links"]       = user.links_data if user.links_data.present?
    entry["remarks"]     = user.remarks if user.remarks.present?
    entry
  end

  def build_components
    if @components.any?
      @components.map { |c| build_component(c) }
    else
      this_uuid = SecureRandom.uuid
      @default_component_uuid = this_uuid
      [
        {
          "uuid"        => this_uuid,
          "type"        => "this-system",
          "title"       => @document.name,
          "description" => "The system described by this SSP.",
          "status"      => { "state" => "operational" }
        }
      ]
    end
  end

  def build_component(comp)
    entry = {
      "uuid"        => comp.uuid,
      "type"        => comp.component_type,
      "title"       => comp.title,
      "description" => comp.description
    }
    entry["purpose"] = comp.purpose if comp.purpose.present?
    entry["status"]  = build_component_status(comp)
    entry["responsible-roles"] = comp.responsible_roles_data if comp.responsible_roles_data.present?
    entry["protocols"]         = comp.protocols_data if comp.protocols_data.present?
    entry["props"]             = comp.props_data if comp.props_data.present?
    entry["links"]             = comp.links_data if comp.links_data.present?
    entry["remarks"]           = comp.remarks if comp.remarks.present?
    entry
  end

  def build_component_status(comp)
    status = { "state" => comp.status_state.presence || "operational" }
    status["remarks"] = comp.status_remarks if comp.status_remarks.present?
    status
  end

  def build_leveraged_authorization(la)
    entry = {
      "uuid"            => la.uuid,
      "title"           => la.title,
      "party-uuid"      => la.party_uuid,
      "date-authorized" => la.date_authorized&.iso8601
    }
    entry["props"]   = la.props_data if la.props_data.present?
    entry["links"]   = la.links_data if la.links_data.present?
    entry["remarks"] = la.remarks if la.remarks.present?
    entry.compact
  end

  def build_inventory_item(item)
    entry = {
      "uuid"        => item.uuid,
      "description" => item.description
    }
    entry["implemented-components"] = item.implemented_components_data if item.implemented_components_data.present?
    entry["responsible-parties"]    = item.responsible_parties_data if item.responsible_parties_data.present?
    entry["props"]                  = item.props_data if item.props_data.present?
    entry["links"]                  = item.links_data if item.links_data.present?
    entry["remarks"]                = item.remarks if item.remarks.present?
    entry
  end

  # ── Control Implementation ─────────────────────────────────────────

  def build_control_implementation
    {
      "description"              => "Control implementation for #{@document.name}",
      "implemented-requirements" => @controls.map { |ctrl| build_implemented_requirement(ctrl) }
    }
  end

  def build_implemented_requirement(control)
    field_map = control.ssp_control_fields.index_by(&:field_name)
    by_comps  = control.ssp_by_components.to_a

    result = {
      "uuid"       => SecureRandom.uuid,
      "control-id" => normalize_control_id(control.control_id)
    }

    # Props carry status, control_application, coverage_level, control_type
    props = build_props(field_map)
    result["props"] = props if props.any?

    # By-components (enriched controls with component-level descriptions)
    if by_comps.any?
      result["by-components"] = by_comps.map { |bc| build_by_component(bc) }
    end

    # Statements capture implementation narrative fields (legacy + enriched)
    statements = build_statements(control, field_map)
    result["statements"] = statements if statements.any?

    # Remarks aggregate free-text fields
    remarks = build_remarks(control, field_map)
    result["remarks"] = remarks if remarks.present?

    # Back-matter resource links (href="#uuid" references)
    if control.respond_to?(:back_matter_resources) && control.back_matter_resources.any?
      result["links"] = control.back_matter_resources.map do |resource|
        { "href" => "##{resource.uuid}", "rel" => resource.rel.presence || "reference" }
      end
    end

    result
  end

  def build_by_component(bc)
    entry = {
      "component-uuid" => bc.ssp_component.uuid,
      "uuid"           => bc.uuid
    }
    entry["description"] = bc.description.presence || "Implementation of this control by #{bc.ssp_component.title}."

    if bc.implementation_status.present?
      entry["implementation-status"] = { "state" => bc.implementation_status }
      if bc.remarks.present?
        entry["implementation-status"]["remarks"] = bc.remarks
      end
    end

    entry["export"]    = bc.export_data if bc.export_data.present?
    entry["inherited"] = bc.inherited_data if bc.inherited_data.present?
    entry["satisfied"] = bc.satisfied_data if bc.satisfied_data.present?
    entry["responsible-roles"] = bc.responsible_roles_data if bc.responsible_roles_data.present?
    entry["set-parameters"]    = bc.set_parameters_data if bc.set_parameters_data.present?
    entry["props"]  = bc.props_data if bc.props_data.present?
    entry["links"]  = bc.links_data if bc.links_data.present?

    entry
  end

  # ── Back matter ────────────────────────────────────────────────────

  def build_back_matter
    @document.build_oscal_back_matter
  end

  # ── Helpers ────────────────────────────────────────────────────────

  def normalize_control_id(raw_id)
    return "unknown" if raw_id.blank?
    # OSCAL TokenDatatype: ^(\p{L}|_)(\p{L}|\p{N}|[.\-_])*$
    # Convert parenthesised enhancements to dot notation: "AC-2 (1)" -> "ac-2.1"
    raw_id.strip
          .downcase
          .gsub(/\s+/, "-")       # spaces -> hyphens
          .gsub("(", ".")         # open paren -> dot
          .gsub(")", "")          # strip close paren
          .gsub(/\.{2,}/, ".")    # collapse multiple dots
          .gsub(/-\./, ".")       # clean "ac-2.1" not "ac-2-.1"
  end

  def build_props(field_map)
    props = []

    status = field_map["status"]&.field_value
    props << { "name" => "implementation-status", "value" => status.downcase.gsub(/\s+/, "-") } if status.present?

    type_use = field_map["control_application"]&.field_value
    props << { "name" => "control-type", "ns" => "https://sparc.local/ns", "value" => type_use } if type_use.present?

    coverage_level = field_map["coverage_level"]&.field_value
    props << { "name" => "provided-as", "ns" => "https://sparc.local/ns", "value" => coverage_level } if coverage_level.present?

    origination = field_map["control_type"]&.field_value
    props << { "name" => "control-origination", "ns" => "https://sparc.local/ns", "value" => origination } if origination.present?

    responsible = field_map["responsible_entities"]&.field_value
    props << { "name" => "responsible-entities", "ns" => "https://sparc.local/ns", "value" => responsible } if responsible.present?

    props
  end

  def build_statements(control, field_map)
    statements = []
    control_id = normalize_control_id(control.control_id)

    # Private implementation as a statement
    priv = field_map["implementation_statement"]&.field_value
    if priv.present?
      statements << {
        "statement-id" => "#{control_id}_priv",
        "uuid"         => SecureRandom.uuid,
        "remarks"      => priv
      }
    end

    # Public implementation as a statement
    pub = field_map["implementation_summary"]&.field_value
    if pub.present?
      statements << {
        "statement-id" => "#{control_id}_pub",
        "uuid"         => SecureRandom.uuid,
        "remarks"      => pub
      }
    end

    # Provider / inherited statements (legacy Excel structure)
    control.provider_statements.each_with_index do |stmt, i|
      stmt_fields = stmt.ssp_control_fields.index_by(&:field_name)
      priv_impl = stmt_fields["implementation_statement"]&.field_value
      pub_impl  = stmt_fields["implementation_summary"]&.field_value
      narrative = [ priv_impl, pub_impl ].compact.join("\n\n")
      next if narrative.blank?

      statements << {
        "statement-id" => "#{control_id}_inherited_#{i + 1}",
        "uuid"         => SecureRandom.uuid,
        "remarks"      => narrative
      }
    end

    statements
  end

  def build_remarks(control, field_map)
    parts = []

    stated_req = field_map["stated_requirement"]&.field_value
    parts << "Stated Requirement: #{stated_req}" if stated_req.present?

    notes = field_map["notes"]&.field_value
    parts << "Notes: #{notes}" if notes.present?

    expected = field_map["expected_completion"]&.field_value
    parts << "Expected Completion: #{expected}" if expected.present?

    inherited_from = field_map["inherited_from"]&.field_value
    parts << "Inherited From: #{inherited_from}" if inherited_from.present?

    history = field_map["history"]&.field_value
    parts << "History: #{history}" if history.present?

    parts.join("\n\n").presence
  end
end
