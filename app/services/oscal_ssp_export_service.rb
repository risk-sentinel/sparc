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
  include OscalExportReconciliation

  DEFAULT_OSCAL_VERSION = OscalSchema::DEFAULT_VERSION
  OSCAL_VERSION = DEFAULT_OSCAL_VERSION # backward compat

  # OSCAL prop/statement names reused across the export build.
  DATE_AUTHORIZED       = "date-authorized".freeze
  PARTY_UUID            = "party-uuid".freeze
  RESPONSIBLE_ROLES     = "responsible-roles".freeze
  IMPLEMENTATION_STATUS = "implementation-status".freeze
  STATEMENT_ID          = "statement-id".freeze
  BY_COMPONENTS         = "by-components".freeze
  # #1004 — how a component points at the CDEF it came from.
  COMPONENT_DEFINITION_REL = "component-definition".freeze

  # #958 — SPARC's own markers, parked in a statement's set_parameters_data by
  # SspJsonParserService so LeveragedAuthorization can query them. They are
  # bookkeeping, not OSCAL, and must never reach an export as-is.
  STATEMENT_MARKER_KEY  = "tag".freeze
  PROVIDED_MARKER       = "provided".freeze
  RESPONSIBILITY_MARKER = "responsibility".freeze
  SSP_STATEMENT         = "ssp-statement".freeze
  # Namespace for SPARC-specific OSCAL props (control-type, provided-as, etc.).
  SPARC_NS = "https://sparc.local/ns".freeze

  def initialize(ssp_document)
    @document = ssp_document
    eager_load_associations
  end

  # Build, validate, and return pretty-printed OSCAL SSP JSON.
  def export
    # #911 layer 2 — never publish a control-id that resolves to no loaded
    # catalog. The schema cannot catch this: `tbd` is a valid TokenDatatype.
    refuse_unresolvable_controls!(label: "SSP", name: @document.name,
                                  control_ids: @document.ssp_controls.pluck(:control_id))
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
    # Ordered so repeated exports of an unchanged document are identical.
    @components    = @document.ssp_components.order(:id).to_a
    @users         = @document.ssp_users.order(:id).to_a
    @info_types    = @document.ssp_information_types.order(:id).to_a
    @leveraged     = @document.ssp_leveraged_authorizations.to_a
    @inventory     = @document.ssp_inventory_items.to_a
    @controls      = @document.ssp_controls
                              .roots
                              .includes(
                                :ssp_control_fields,
                                ssp_control_statements: :inheritance_links,
                                ssp_by_components: :ssp_component,
                                provider_statements: :ssp_control_fields
                              ).to_a
    # #396: boundary-level leveraged authorizations, plus the components
    # each one exposes. Empty when no boundary or no LAs are configured.
    boundary = @document.authorization_boundary
    @boundary_leveraged_auths = boundary ? boundary.leveraging_relationships.includes(:leveraged_authorization_components).to_a : []
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
      default_parties: default_parties
    )
  end

  # The document's own org, plus a party for each leveraged system's owner —
  # a leveraged-authorization's `party-uuid` must resolve to a declared party,
  # not dangle.
  def default_parties
    parties = [ { "uuid" => OscalUuidService.org_party_uuid_for(@document),
                  "type" => "organization", "name" => "SPARC Export" } ]

    @boundary_leveraged_auths.each do |la|
      uuid = leveraged_party_uuid(la)
      next if uuid.blank? || parties.any? { |p| p["uuid"] == uuid }

      org = la.leveraged_boundary&.organization
      parties << { "uuid" => uuid, "type" => "organization",
                   "name" => org&.name.presence || "Leveraged System Provider" }
    end

    parties
  end

  def leveraged_party_uuid(la)
    org = la.leveraged_boundary&.organization
    return org.uuid if org&.uuid.present?

    # No organization on the leveraged boundary (or no boundary at all, which
    # is Scenario 2/3): derive a stable one rather than omit a required field.
    OscalUuidService.derived(la.uuid, "leveraged-authorization-party")
  end

  # ── Import Profile ─────────────────────────────────────────────────

  def build_import_profile
    # #395 P2: prefer `uuid:<profile.uuid>` from the linked ProfileDocument
    # FK. Fall back to the raw `import_profile_href` round-trip column,
    # then "#" as the schema-required last resort.
    href = OscalMetadata.import_href_for(@document.profile_document) ||
           @document.import_profile_href.presence ||
           "#"
    { "href" => href }
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
    sc[DATE_AUTHORIZED] = @document.date_authorized.iso8601 if @document.date_authorized.present?
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
            "uuid"        => OscalUuidService.derived(@document.uuid, "ssp-default-info-type"),
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

    leveraged_assemblies = build_leveraged_authorizations_list
    impl["leveraged-authorizations"] = leveraged_assemblies if leveraged_assemblies.any?

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
          "uuid"     => OscalUuidService.derived(@document.uuid, "ssp-default-user"),
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
      this_uuid = OscalUuidService.derived(@document.uuid, "ssp-this-system-component")
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
    entry[RESPONSIBLE_ROLES] = comp.responsible_roles_data if comp.responsible_roles_data.present?
    entry["protocols"]         = comp.protocols_data if comp.protocols_data.present?
    # #998 — the validation pair. Props and links are MERGED with whatever the
    # component already carries rather than replacing them: props_data and
    # links_data hold what was imported, and a validation claim is an addition
    # to that, not a substitute for it.
    props = Array(comp.props_data) + validation_props(comp)
    links = Array(comp.links_data) + validation_links(comp) + component_definition_links(comp)

    entry["props"]             = props if props.present?
    entry["links"]             = links if links.present?
    entry["remarks"]           = comp.remarks if comp.remarks.present?
    entry
  end

  # #1004 — the trail back to the component definition this component came from.
  #
  # `ssp_components.cdef_document_id` records it and the export dropped it, so a
  # reader of the OSCAL saw a uuid and a title and the trail stopped there: the
  # boundary's component definitions were invisible in the package. The link
  # resolves to a back-matter resource that `BackMatterBuilder` emits for the
  # same CDEF, so the reference is internal to the document and resolvable
  # without reaching back into SPARC.
  #
  # The href is the CDEF's OWN uuid. Per the per-subject UUID rule an export
  # must never mint or change one, and the subject here IS that component
  # definition — so the same CDEF yields the same resource uuid on every export,
  # which is what makes it a citation rather than a fresh identifier each time.
  def component_definition_links(comp)
    return [] if comp.cdef_document_id.blank?

    cdef = comp.cdef_document
    return [] if cdef.nil?

    [ { "href" => "##{cdef.uuid}", "rel" => COMPONENT_DEFINITION_REL, "text" => cdef.name } ]
  end

  # The certificate, on the validation component itself.
  def validation_props(comp)
    return [] unless comp.validation?

    props = []
    if comp.validation_type.present?
      props << { "name" => SspComponent::VALIDATION_TYPE_PROP, "value" => comp.validation_type }
    end
    if comp.validation_reference.present?
      props << { "name" => SspComponent::VALIDATION_REFERENCE_PROP, "value" => comp.validation_reference }
    end
    props
  end

  # Two directions, and both are needed for the pair to mean anything: the
  # validation component points OUT to the authoritative record, and the product
  # component points IN to its validation. A validation component pointing at
  # nothing is another partial, which is what #998 exists to stop.
  def validation_links(comp)
    links = []

    if comp.validation? && comp.validation_details_href.present?
      links << { "href" => comp.validation_details_href,
                 "rel"  => SspComponent::VALIDATION_DETAILS_REL }
    end

    comp.validations.each do |validation|
      links << { "href" => "##{validation.uuid}", "rel" => SspComponent::VALIDATION_REL }
    end

    links
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
      PARTY_UUID        => la.party_uuid,
      DATE_AUTHORIZED => la.date_authorized&.iso8601
    }
    entry["props"]   = la.props_data if la.props_data.present?
    entry["links"]   = la.links_data if la.links_data.present?
    entry["remarks"] = la.remarks if la.remarks.present?
    entry.compact
  end

  # #396: merge the new boundary-level LeveragedAuthorization assemblies
  # with any legacy SspLeveragedAuthorization rows, de-duplicating on UUID
  # so an SSP parsed from OSCAL (which writes both) doesn't emit twice.
  def build_leveraged_authorizations_list
    legacy = @leveraged.map { |la| build_leveraged_authorization(la) }
    modern = @boundary_leveraged_auths.map { |la| build_boundary_leveraged_authorization(la) }

    seen_uuids = Set.new
    (modern + legacy).each_with_object([]) do |entry, acc|
      uuid = entry["uuid"]
      next if uuid.blank?
      next if seen_uuids.include?(uuid)
      seen_uuids << uuid
      acc << entry
    end
  end

  # #958 — OSCAL REQUIRES `party-uuid` on a leveraged-authorization, and this
  # path never emitted one, so every boundary-level leveraged authorization
  # (#396) made its leveraging SSP fail schema validation on export. The
  # legacy SspLeveragedAuthorization path carries the column and always did.
  #
  # The party is the organization that owns the LEVERAGED system — the
  # provider being relied upon — and it is declared in metadata.parties by
  # build_metadata so the reference resolves instead of dangling.
  def build_boundary_leveraged_authorization(la)
    entry = {
      "uuid"       => la.uuid,
      "title"      => la.name,
      PARTY_UUID   => leveraged_party_uuid(la)
    }
    entry[DATE_AUTHORIZED] = la.date_authorized.iso8601 if la.date_authorized
    entry["remarks"] = la.description if la.description.present?

    leveraged_ssp = la.leveraged_boundary&.ssp_document
    links = []
    if leveraged_ssp
      href = OscalMetadata.import_href_for(leveraged_ssp)
      links << { "href" => href, "rel" => "leveraged-system" } if href
    end
    entry["links"] = links if links.any?
    entry.compact

    party_uuid = la.metadata && la.metadata["party_uuid"]
    entry[PARTY_UUID] = party_uuid if party_uuid.present?

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
      "uuid"       => OscalUuidService.derived(@document.uuid, "ssp-ir", control.uuid),
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
    remarks = build_remarks(field_map)
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
      entry[IMPLEMENTATION_STATUS] = { "state" => bc.implementation_status }
      if bc.remarks.present?
        entry[IMPLEMENTATION_STATUS]["remarks"] = bc.remarks
      end
    end

    entry["export"]    = bc.export_data if bc.export_data.present?
    entry["inherited"] = bc.inherited_data if bc.inherited_data.present?
    entry["satisfied"] = bc.satisfied_data if bc.satisfied_data.present?
    entry[RESPONSIBLE_ROLES] = bc.responsible_roles_data if bc.responsible_roles_data.present?
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

  # #852 — delegated to the one canonical implementation. This was one of
  # several byte-identical private copies; ControlId.canonical reproduces them
  # exactly (including the OSCAL TokenDatatype conversion of "AC-2 (1)" to
  # "ac-2.1") and additionally removes zero padding, so "AC-02" and "ac-2"
  # finally name the same control.
  def normalize_control_id(raw_id)
    ControlId.canonical(raw_id)
  end

  # `implementation-status` is an OSCAL-NAMESPACED prop, so its value has to come
  # from NIST's vocabulary — implemented / partial / planned / alternative /
  # not-applicable.
  #
  # This used to be `status.downcase.gsub(/\s+/, "-")`, which slugified SPARC's
  # own vocabulary straight into NIST's namespace. Three of the eight SPARC
  # statuses happen to collide with a NIST term and were right by accident; the
  # other five were not:
  #
  #   Deferred                   -> "deferred"                    not a NIST value
  #   Partially Implemented      -> "partially-implemented"       NIST says "partial"
  #   Alternative Implementation -> "alternative-implementation"  NIST says "alternative"
  #   Will Not Implement         -> "will-not-implement"          no NIST equivalent
  #   Not Implemented            -> "not-implemented"             no NIST equivalent
  #
  # NOTHING CAUGHT IT. Prop VALUES are Metaschema constraints, not JSON Schema
  # ones, and `OscalSchemaValidationService` validates JSON Schema — so the
  # export reported valid while telling a conforming reader something it cannot
  # interpret.
  #
  # Two rules here:
  #
  #   1. Map to NIST's term when one honestly applies. `Deferred` becomes
  #      `planned`: the control is intended and not yet in place, which is what
  #      `planned` means. It is NOT `not-applicable` — deferring something is not
  #      declaring it irrelevant.
  #   2. When NIST cannot express the status at all — `Will Not Implement`,
  #      `Not Implemented` — do NOT invent a term in NIST's namespace. Omit the
  #      OSCAL prop and say it in SPARC's own, where a reader knows to interpret
  #      it as ours.
  #
  # The verbatim SPARC status is ALWAYS emitted under SPARC_NS as well, so the
  # round trip loses nothing and the mapping stays inspectable.
  NIST_IMPLEMENTATION_STATUS = {
    "implemented"                => "implemented",
    "partially implemented"      => "partial",
    "planned"                    => "planned",
    "deferred"                   => "planned",
    "alternative implementation" => "alternative",
    "not applicable"             => "not-applicable"
  }.freeze

  def implementation_status_props(status)
    props = []
    nist  = NIST_IMPLEMENTATION_STATUS[status.to_s.strip.downcase]
    props << { "name" => IMPLEMENTATION_STATUS, "value" => nist } if nist
    props << { "name" => "sparc-status", "ns" => SPARC_NS, "value" => status }
    props
  end

  def build_props(field_map)
    props = []

    status = field_map["status"]&.field_value
    props.concat(implementation_status_props(status)) if status.present?

    type_use = field_map["control_application"]&.field_value
    props << { "name" => "control-type", "ns" => SPARC_NS, "value" => type_use } if type_use.present?

    coverage_level = field_map["coverage_level"]&.field_value
    props << { "name" => "provided-as", "ns" => SPARC_NS, "value" => coverage_level } if coverage_level.present?

    origination = field_map["control_type"]&.field_value
    props << { "name" => "control-origination", "ns" => SPARC_NS, "value" => origination } if origination.present?

    responsible = field_map["responsible_entities"]&.field_value
    props << { "name" => "responsible-entities", "ns" => SPARC_NS, "value" => responsible } if responsible.present?

    props
  end

  # #393: when ssp_control_statements records exist for this control
  # (backfilled or imported), they are the source of truth. Falls back to
  # the legacy field-synthesized statements (implementation_statement,
  # implementation_summary) for un-backfilled SSPs (no linked profile).
  # #946 — BOTH sources, not one or the other.
  #
  # This returned the table statements when any existed and the
  # field-synthesized ones otherwise, so a control that had both lost the
  # field. That is the normal state for a generated SSP: `SspFromProfileService`
  # creates statement rows from the catalog (#955), and the organisation's own
  # narrative lives in the `implementation_statement` FIELD. Exporting only the
  # first dropped the part a reader actually cares about — what the system does
  # about the control — while keeping the part the catalog already states.
  #
  # Statement ids are unique per control, and the field-synthesized ones are
  # suffixed `_priv`/`_pub`, so the two sets cannot collide.
  def build_statements(control, field_map)
    build_statements_from_table(control) + build_statements_from_fields(control, field_map)
  end

  def build_statements_from_table(control)
    control.ssp_control_statements.order(:row_order).map do |stmt|
      entry = {
        STATEMENT_ID => stmt.statement_id,
        "uuid"         => stmt.uuid,
        "remarks"      => stmt.implementation_prose.presence || stmt.remarks
      }
      entry[RESPONSIBLE_ROLES] = stmt.responsible_roles_data if stmt.responsible_roles_data.present?

      # #958 — `set-parameters` is NOT legal on a statement (OSCAL allows it
      # on an implemented-requirement and on a by-component), so emitting it
      # here made every SSP carrying one fail schema validation on export.
      by_components = build_statement_by_components(stmt)
      entry[BY_COMPONENTS] = by_components if by_components.any?

      # #396 + #398: emit inheritance links so the source of the prose
      # round-trips through OSCAL. `implements` for CDEF source,
      # `inherited` for a leveraged SSP source.
      inh_links = build_statement_inheritance_links(stmt)
      entry["links"] = inh_links if inh_links.any?
      entry.compact
    end
  end

  # #958 — what SPARC stores in a statement's `set_parameters_data` is mostly
  # not set-parameters at all. SspJsonParserService parks `{"tag" =>
  # "provided"}` / `{"tag" => "responsibility"}` markers there so
  # LeveragedAuthorization#inheritable_statements can match them with a jsonb
  # containment query. Those markers are READ on import from
  # `by-component.satisfied[]` and `.responsibilities[]` — exactly where OSCAL
  # models this — so they round-trip back there instead of leaking as an
  # illegal property or being silently dropped.
  #
  # Genuine set-parameters ride along on the same by-component, which is a
  # place OSCAL does allow them.
  def build_statement_by_components(stmt)
    markers, real_params = Array(stmt.set_parameters_data).partition do |param|
      param.is_a?(Hash) && param.key?(STATEMENT_MARKER_KEY)
    end
    return [] if markers.empty? && real_params.empty?

    component_uuid = statement_component_uuid
    return [] if component_uuid.blank?

    tags  = markers.filter_map { |m| m[STATEMENT_MARKER_KEY] }
    entry = {
      "component-uuid" => component_uuid,
      "uuid"           => OscalUuidService.derived(stmt.uuid, "ssp-statement-by-component"),
      "description"    => "Implementation of #{stmt.statement_id} by this system."
    }

    # Both live under `by-component.export`, not directly on the by-component:
    # OSCAL models this from the PROVIDER's point of view, which is exactly
    # what a leveraged SSP is. `satisfied` is the mirror image — the
    # leveraging system declaring it met a responsibility — and does not
    # belong here.
    exported = {}
    if tags.include?(PROVIDED_MARKER)
      exported["provided"] = [ {
        "uuid"        => OscalUuidService.derived(stmt.uuid, "ssp-statement-provided"),
        "description" => "This system provides #{stmt.statement_id} to leveraging systems."
      } ]
    end

    if tags.include?(RESPONSIBILITY_MARKER)
      exported["responsibilities"] = [ {
        "uuid"        => OscalUuidService.derived(stmt.uuid, "ssp-statement-responsibility"),
        "description" => "A leveraging system is responsible for #{stmt.statement_id}."
      } ]
    end

    entry["export"] = exported if exported.any?

    entry["set-parameters"] = real_params if real_params.any?
    [ entry ]
  end

  # The by-component has to name a component that exists in `components`, or
  # the reference dangles. Falls back to the synthesized this-system uuid,
  # which build_components derives the same way.
  def statement_component_uuid
    @statement_component_uuid ||=
      @components.find { |c| c.component_type == "this-system" }&.uuid ||
      @components.first&.uuid ||
      OscalUuidService.derived(@document.uuid, "ssp-this-system-component")
  end

  def build_statement_inheritance_links(stmt)
    stmt.inheritance_links.map do |link|
      rel = link.source_type == "CdefControlStatement" ? "implements" : "inherited"
      { "href" => "uuid:#{link.source_uuid}", "rel" => rel }
    end
  end

  # Legacy field-synthesized statements. UUIDs use the same formula the
  # backfill writes into ssp_control_statements -- so an SSP that gets
  # backfilled mid-lifecycle round-trips with byte-identical UUIDs.
  def build_statements_from_fields(control, field_map)
    statements = []
    control_id = normalize_control_id(control.control_id)

    priv = field_map["implementation_statement"]&.field_value
    if priv.present?
      stmt_id = "#{control_id}_priv"
      statements << {
        STATEMENT_ID => stmt_id,
        "uuid"         => OscalUuidService.derived(control.uuid, SSP_STATEMENT, stmt_id),
        "remarks"      => priv
      }
    end

    pub = field_map["implementation_summary"]&.field_value
    if pub.present?
      stmt_id = "#{control_id}_pub"
      statements << {
        STATEMENT_ID => stmt_id,
        "uuid"         => OscalUuidService.derived(control.uuid, SSP_STATEMENT, stmt_id),
        "remarks"      => pub
      }
    end

    control.provider_statements.each_with_index do |stmt, i|
      stmt_fields = stmt.ssp_control_fields.index_by(&:field_name)
      priv_impl = stmt_fields["implementation_statement"]&.field_value
      pub_impl  = stmt_fields["implementation_summary"]&.field_value
      narrative = [ priv_impl, pub_impl ].compact.join("\n\n")
      next if narrative.blank?

      stmt_id = "#{control_id}_inherited_#{i + 1}"
      statements << {
        STATEMENT_ID => stmt_id,
        "uuid"         => OscalUuidService.derived(control.uuid, SSP_STATEMENT, stmt_id),
        "remarks"      => narrative
      }
    end

    statements
  end

  def build_remarks(field_map)
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
