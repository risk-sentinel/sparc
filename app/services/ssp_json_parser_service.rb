# Parses an OSCAL SSP JSON file into the relational SSP model.
#
# Usage:
#   SspJsonParserService.new(ssp_document, file_path).parse
#   # or from an already-parsed hash (used by XML parser delegation):
#   SspJsonParserService.new(ssp_document, nil).parse_from_hash(data)
#
class SspJsonParserService
  def initialize(document, file_path)
    @document  = document
    @file_path = file_path
  end

  def parse
    content = File.read(@file_path).force_encoding("UTF-8")
    data    = JSON.parse(content)
    parse_from_hash(data)
  end

  def parse_from_hash(data)
    ssp = data["system-security-plan"] || raise("Invalid OSCAL SSP: missing 'system-security-plan' root key")

    ActiveRecord::Base.transaction do
      update_document_metadata(ssp)
      parse_system_characteristics(ssp["system-characteristics"])
      @component_map = parse_system_implementation(ssp["system-implementation"])
      parse_control_implementation(ssp["control-implementation"], @component_map)
    end
  end

  private

  # ── Document-level metadata ──────────────────────────────────────

  def update_document_metadata(ssp)
    metadata = ssp["metadata"] || {}
    @document.update!(
      creation_method:    "oscal_import",
      oscal_version:      metadata["oscal-version"],
      ssp_version:        metadata["version"],
      import_profile_href: ssp.dig("import-profile", "href"),
      metadata_extra:     metadata.except("title", "version", "oscal-version", "last-modified"),
      import_metadata:    {
        "uuid"        => ssp["uuid"],
        "back_matter" => ssp.dig("back-matter", "resources")
      }.compact
    )
    @document.update!(name: metadata["title"]) if metadata["title"].present?
  end

  # ── System characteristics ───────────────────────────────────────

  def parse_system_characteristics(sc)
    return unless sc

    @document.update!(
      system_id:                          sc.dig("system-ids", 0, "id"),
      description:                        extract_text(sc["description"]),
      system_name_short:                  sc["system-name-short"],
      security_sensitivity_level:         sc["security-sensitivity-level"],
      system_status:                      sc.dig("status", "state") || "operational",
      date_authorized:                    sc["date-authorized"],
      authorization_boundary_description: extract_text(sc.dig("authorization-boundary", "description")),
      network_architecture_description:   extract_text(sc.dig("network-architecture", "description")),
      data_flow_description:              extract_text(sc.dig("data-flow", "description")),
      security_objective_confidentiality: sc.dig("security-impact-level", "security-objective-confidentiality"),
      security_objective_integrity:       sc.dig("security-impact-level", "security-objective-integrity"),
      security_objective_availability:    sc.dig("security-impact-level", "security-objective-availability")
    )

    # Update name from system-name if present
    @document.update!(name: sc["system-name"]) if sc["system-name"].present? && @document.name.blank?

    parse_information_types(sc.dig("system-information", "information-types") || [])
  end

  def parse_information_types(types)
    types.each do |it|
      @document.ssp_information_types.create!(
        uuid:                              it["uuid"] || SecureRandom.uuid,
        title:                             it["title"] || "Information Type",
        description:                       extract_text(it["description"]) || "No description provided.",
        confidentiality_impact_base:       it.dig("confidentiality-impact", "base"),
        confidentiality_impact_selected:   it.dig("confidentiality-impact", "selected"),
        confidentiality_impact_adjustment: it.dig("confidentiality-impact", "adjustment-justification"),
        integrity_impact_base:             it.dig("integrity-impact", "base"),
        integrity_impact_selected:         it.dig("integrity-impact", "selected"),
        integrity_impact_adjustment:       it.dig("integrity-impact", "adjustment-justification"),
        availability_impact_base:          it.dig("availability-impact", "base"),
        availability_impact_selected:      it.dig("availability-impact", "selected"),
        availability_impact_adjustment:    it.dig("availability-impact", "adjustment-justification"),
        categorizations_data:              it["categorizations"] || [],
        props_data:                        it["props"] || [],
        links_data:                        it["links"] || []
      )
    end
  end

  # ── System implementation ────────────────────────────────────────

  def parse_system_implementation(si)
    return {} unless si

    component_map = {}
    parse_components(si["components"] || [], component_map)
    parse_users(si["users"] || [])
    parse_leveraged_authorizations(si["leveraged-authorizations"] || [])
    parse_inventory_items(si["inventory-items"] || [])
    component_map
  end

  def parse_components(components, component_map)
    components.each do |comp|
      status = comp["status"] || {}
      record = @document.ssp_components.create!(
        uuid:                   comp["uuid"],
        component_type:         comp["type"],
        title:                  comp["title"] || "Untitled Component",
        description:            extract_text(comp["description"]) || "No description provided.",
        purpose:                comp["purpose"],
        status_state:           status["state"] || "operational",
        status_remarks:         status["remarks"],
        responsible_roles_data: comp["responsible-roles"] || [],
        protocols_data:         comp["protocols"] || [],
        props_data:             comp["props"] || [],
        links_data:             comp["links"] || [],
        remarks:                comp["remarks"]
      )
      component_map[comp["uuid"]] = record
    end
  end

  def parse_users(users)
    users.each do |user|
      @document.ssp_users.create!(
        uuid:                       user["uuid"] || SecureRandom.uuid,
        title:                      user["title"],
        description:                user["description"],
        short_name:                 user["short-name"],
        role_ids_data:              user["role-ids"] || [],
        authorized_privileges_data: user["authorized-privileges"] || [],
        props_data:                 user["props"] || [],
        links_data:                 user["links"] || [],
        remarks:                    user["remarks"]
      )
    end
  end

  def parse_leveraged_authorizations(auths)
    auths.each do |auth|
      @document.ssp_leveraged_authorizations.create!(
        uuid:            auth["uuid"] || SecureRandom.uuid,
        title:           auth["title"],
        party_uuid:      auth["party-uuid"],
        date_authorized: auth["date-authorized"],
        props_data:      auth["props"] || [],
        links_data:      auth["links"] || [],
        remarks:         auth["remarks"]
      )
    end
  end

  def parse_inventory_items(items)
    items.each do |item|
      @document.ssp_inventory_items.create!(
        uuid:                       item["uuid"] || SecureRandom.uuid,
        description:                extract_text(item["description"]) || "No description provided.",
        implemented_components_data: item["implemented-components"] || [],
        responsible_parties_data:    item["responsible-parties"] || [],
        props_data:                  item["props"] || [],
        links_data:                  item["links"] || [],
        remarks:                     item["remarks"]
      )
    end
  end

  # ── Control implementation ───────────────────────────────────────

  def parse_control_implementation(ci, component_map)
    return unless ci

    (ci["implemented-requirements"] || []).each_with_index do |ir, idx|
      ctrl = @document.ssp_controls.create!(
        control_id: ir["control-id"],
        row_order:  idx
      )

      parse_implemented_requirement_props(ctrl, ir)
      parse_by_components(ctrl, ir["by-components"] || [], component_map)
      parse_statements_as_fields(ctrl, ir)
      parse_remarks_as_field(ctrl, ir)
    end
  end

  def parse_implemented_requirement_props(ctrl, ir)
    (ir["props"] || []).each do |prop|
      field_name = prop_name_to_field(prop["name"])
      next unless field_name

      ctrl.ssp_control_fields.create!(
        field_name:  field_name,
        field_value: prop["value"]
      )
    end
  end

  def parse_by_components(ctrl, by_components, component_map)
    by_components.each do |bc|
      component = component_map[bc["component-uuid"]]
      next unless component

      ctrl.ssp_by_components.create!(
        ssp_component:         component,
        uuid:                  bc["uuid"] || SecureRandom.uuid,
        description:           extract_text(bc["description"]),
        implementation_status: bc.dig("implementation-status", "state") || bc["implementation-status"],
        export_data:           bc["export"] || {},
        inherited_data:        bc["inherited"] || [],
        satisfied_data:        bc["satisfied"] || [],
        responsible_roles_data: bc["responsible-roles"] || [],
        set_parameters_data:   bc["set-parameters"] || [],
        props_data:            bc["props"] || [],
        links_data:            bc["links"] || [],
        remarks:               bc["remarks"]
      )
    end
  end

  def parse_statements_as_fields(ctrl, ir)
    (ir["statements"] || []).each do |stmt|
      narrative = stmt["remarks"] || stmt.dig("by-components", 0, "description") || ""
      next if narrative.blank?

      ctrl.ssp_control_fields.create!(
        field_name:  "statement_#{stmt['statement-id']}",
        field_value: narrative
      )
    end
  end

  def parse_remarks_as_field(ctrl, ir)
    return unless ir["remarks"].present?

    ctrl.ssp_control_fields.create!(
      field_name:  "notes",
      field_value: ir["remarks"]
    )
  end

  # ── Helpers ──────────────────────────────────────────────────────

  def prop_name_to_field(oscal_name)
    {
      "implementation-status"  => "status",
      "control-type"           => "type_use_as",
      "provided-as"            => "provided_as",
      "control-origination"    => "control_origination",
      "responsible-entities"   => "responsible_entities"
    }[oscal_name]
  end

  def extract_text(value)
    case value
    when String then value.presence
    when Hash   then value["value"].presence || value.to_s
    else value.to_s.presence
    end
  end
end
