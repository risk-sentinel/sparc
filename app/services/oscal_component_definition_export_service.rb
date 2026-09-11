# Builds an OSCAL v1.1.2 Component Definition JSON document from a
# CdefDocument and its controls.  Validates the output against the
# official NIST JSON schema before returning.
#
# Usage:
#   service = OscalComponentDefinitionExportService.new(cdef_document)
#   json_string = service.export            # validates, raises on failure
#   json_string = service.export_unvalidated # skips validation (legacy)
#   result      = service.validation_result  # inspect errors without raising
#
class OscalComponentDefinitionExportService
  DEFAULT_OSCAL_VERSION = OscalSchema::DEFAULT_VERSION
  OSCAL_VERSION = DEFAULT_OSCAL_VERSION # backward compat

  def initialize(cdef_document)
    @document = cdef_document
  end

  # Build, validate, and return pretty-printed OSCAL JSON.
  # Raises OscalValidationError if the output fails schema validation.
  def export
    data = build_component_definition
    OscalSchemaValidationService.validate!(:component_definition, data, version: effective_oscal_version)
    JSON.pretty_generate(data)
  end

  # Build and return OSCAL JSON without schema validation.
  def export_unvalidated
    JSON.pretty_generate(build_component_definition)
  end

  # Build the document and return the validation result (does not raise).
  def validation_result
    data = build_component_definition
    OscalSchemaValidationService.validate(:component_definition, data)
  end


  def effective_oscal_version
    @document.oscal_version.presence || DEFAULT_OSCAL_VERSION
  end

  private

  def build_component_definition
    {
      "component-definition" => {
        "uuid"         => @document.uuid,
        "metadata"     => build_metadata,
        "components"   => build_components,
        "back-matter"  => build_back_matter
      }.compact
    }
  end

  def build_metadata
    @document.build_oscal_metadata(
      default_version: @document.cdef_version || "1.0.0",
      default_roles: [
        { "id" => "prepared-by", "title" => "Prepared By" }
      ],
      default_parties: [
        { "uuid" => OscalUuidService.org_party_uuid_for(@document),
          "type" => "organization", "name" => "SPARC Export" }
      ]
    )
  end

  # #1088 item 5 — a component definition may define MANY components, and the
  # AWS corpus does: one `service` carrying the regions and partitions, plus one
  # `software` component per AWS Config Rule (the checks). SPARC imported all of
  # them into `cdef_components` and then exported exactly ONE, rebuilt from the
  # `cdef_documents.component_*` columns — so a four-component document went out
  # as one, and every control it asserted was reattributed to that single
  # invented component. Round-trip loss, in the same shape as #1100 and #1114.
  #
  # Attribution decides which path applies. A document whose controls carry
  # `component_uuid` (imported through the OSCAL walk since #1088) exports the
  # components it actually has. Anything else — a hand-authored CDEF, an XCCDF
  # import, a row that predates the column — exports exactly as before, so #944's
  # authored `component_*` values still win on the documents they were written
  # for. That fallback is not legacy tolerance: those documents genuinely have
  # one component, and it is the one the author named.
  def build_components
    attributed = @document.cdef_controls.where.not(component_uuid: [ nil, "" ])
    return [ build_component ] if attributed.empty?

    indexed = @document.cdef_components.index_by(&:component_uuid)
    by_component = attributed.order(:row_order)
                             .includes(:cdef_control_fields)
                             .group_by(&:component_uuid)

    # Services first, mirroring the show page: they are what a reader is
    # choosing between; the Config Rule components are supporting detail.
    ordered_uuids = by_component.keys.sort_by do |uuid|
      comp = indexed[uuid]
      [ comp&.component_type == "service" ? 0 : 1, comp&.title.to_s ]
    end

    components = ordered_uuids.filter_map do |uuid|
      build_indexed_component(uuid, indexed[uuid], by_component[uuid])
    end

    # A control whose component was never indexed must not vanish from the
    # export. Nothing observed produces this — the indexer and the control walk
    # read the same array — but silently dropping asserted controls is the one
    # outcome worth guarding against by construction.
    orphans = @document.cdef_controls
                       .where(component_uuid: [ nil, "" ])
                       .or(@document.cdef_controls.where.not(component_uuid: indexed.keys))
                       .order(:row_order).includes(:cdef_control_fields).to_a
    components << build_component(orphans) if orphans.any?

    components.presence || [ build_component ]
  end

  # One OSCAL component from an indexed `cdef_components` row, carrying the
  # controls attributed to it.
  def build_indexed_component(uuid, indexed_component, controls)
    exportable = drop_unmapped(controls)

    component = {
      "uuid"        => oscal_component_uuid(uuid),
      "type"        => indexed_component&.component_type.presence || "software",
      "title"       => indexed_component&.title.presence || @document.name,
      "description" => indexed_component&.description.presence ||
                       "Component of #{@document.name}"
    }
    component["purpose"] = indexed_component.purpose if indexed_component&.purpose.presence

    # #1051 — emit `control-implementations` only when there is a requirement to
    # put in it; OSCAL requires at least one entry.
    impls = build_control_implementations(exportable)
    component["control-implementations"] = impls if impls.any?
    component
  end

  # OSCAL requires a v4-shaped uuid. A component uuid carried in from an
  # upstream document is preserved — that is the round-trip fidelity #1088 is
  # for, and the AWS corpus supplies real ones — but a source that supplies
  # something else must not make the export schema-invalid. Caught by
  # `cdef_json_parser_index_savepoint_968_spec`, whose fixture uuid ends
  # "00000000dupe": not hex, so not a uuid, and passing it through produced
  # `/component-definition/components/0/uuid: does not match pattern`.
  #
  # The fallback is DERIVED from the document uuid and the source's own string,
  # so it is stable across exports and distinct per component rather than a
  # random value that changes every time.
  OSCAL_UUID = /\A[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[45][0-9A-Fa-f]{3}-[89ABab][0-9A-Fa-f]{3}-[0-9A-Fa-f]{12}\z/

  def oscal_component_uuid(uuid)
    return uuid if OSCAL_UUID.match?(uuid.to_s)

    OscalUuidService.derived(@document.uuid, "cdef-component-#{uuid}")
  end

  # #1088 item 4 — ONE control-implementation PER SOURCE.
  #
  # `source` is required on a control-implementation and the OSCAL schema
  # documents it as "a reference to an OSCAL catalog or profile". The property is
  # an array precisely so a component can implement controls drawn from more than
  # one catalog and more than one profile — R4 and R5 together, say. SPARC
  # collapsed every control into a single implementation whose source it
  # re-derived from `profile_document_id`, so a document that arrived citing two
  # catalogs went out citing one, with the other's controls silently reattributed.
  def build_control_implementations(controls)
    return [] if controls.empty?

    controls.group_by { |c| c.implementation_source.presence }.map do |source, group|
      resolved = source || default_control_implementation_source
      {
        "uuid"        => OscalUuidService.derived(@document.uuid,
                                                  "cdef-control-implementation-#{resolved}"),
        "source"      => resolved,
        "description" => group.first.implementation_description.presence ||
                         @document.control_implementation_description.presence ||
                         "Controls from #{@document.cdef_type || 'imported'} component definition: #{@document.name}",
        "implemented-requirements" => group.map { |ctrl| build_implemented_requirement(ctrl) }
      }
    end
  end

  # The source for a control that carries none of its own — a hand-authored
  # CDEF, or one imported before #1088 stored the source per control.
  #
  # #944 — an authored source names the catalog or profile whose controls are
  # actually being implemented. `determine_source` otherwise synthesises a
  # `sparc.local` URL that resolves to nothing and carries the database primary
  # key into a delivered artifact.
  #
  # #982 — #944 gave authors a way to name it but never read the one SPARC
  # already knew. A CDEF built from a published profile records that profile in
  # `profile_document_id`, which #911 declared as exactly this hop
  # (`CdefDocument.lineage_via :profile_document`; `CatalogLineage` names the
  # chain `cdef -> @source`). Nothing consulted it, so every profile-sourced CDEF
  # exported the `sparc.local` placeholder while the real source sat one
  # association away — the document declined to name its own control basis.
  #
  # Resolved live from the association rather than copied to a column at build
  # time, so re-pointing a CDEF's profile cannot leave a stale source behind.
  #
  # The authored value still wins: #944 exists so a human can name a source SPARC
  # has no record of, and a form field that silently loses to a foreign key would
  # be its own defect. #1088 adds one hop ABOVE all of these — a source the
  # document itself carried on import — for the same reason: what the document
  # said beats what SPARC would infer.
  def default_control_implementation_source
    @document.control_implementation_source.presence ||
      OscalMetadata.import_href_for(@document.profile_document) ||
      determine_source
  end

  # #911 — a rule that resolved to no NIST control has nothing to put in
  # `control-id`, and exporting `unknown-<id>` is a false claim no validator
  # would catch. Shared by both component paths.
  def drop_unmapped(controls)
    unmapped = @document.cdef_controls.unmapped_stig_rules.ids.to_set
    controls.reject { |c| unmapped.include?(c.id) }
  end

  def build_component(preloaded_controls = nil)
    # #911 — a STIG rule that resolved to no NIST control has nothing to put in
    # `control-id`. It used to be exported as `unknown-<row id>`, which is a
    # false claim: the document asserted an implemented requirement against a
    # control that does not exist in any catalog, and no validator would flag it
    # because the string is a well-formed token. Omitting the rule is the
    # honest export; the CDEF screen and API report the gap and its remedy.
    controls = preloaded_controls ? drop_unmapped(preloaded_controls) :
               @document.cdef_controls
                        .where.not(id: @document.cdef_controls.unmapped_stig_rules.select(:id))
                        .order(:row_order)
                        .includes(:cdef_control_fields)

    if controls.empty? && @document.unmapped_stig_rules?
      raise OscalValidationError,
            "No rule in \"#{@document.name}\" maps to a NIST control, so there is no " \
            "implemented requirement to export. Refresh the stig_to_nist converter, or " \
            "supply the missing CCI references in the benchmark, then export again. " \
            "For SCAP or CIS content, convert it upstream first (`saf convert xccdf_results2hdf`, " \
            "or cis-bench for CIS Benchmarks) — those tools resolve NIST controls themselves (#1033)."
    end

    # #944 — authored values win; the fallbacks are exactly what was hardcoded
    # here before, so a document nobody has edited exports byte-identically.
    # "software" as a blanket default meant every exported CDEF claimed to be
    # software regardless of what it described.
    # #998 — props and links on the COMPONENT. They were already emitted on
    # implemented-requirements and statements; the component was the one place
    # they were missing, so an imported CDEF's component-level claims were
    # dropped on the way back out and a `validation` component had no way to
    # cite its certificate.
    #
    # A CDEF still exports exactly ONE component, built from the
    # cdef_documents.component_* columns, so it cannot carry the component PAIR
    # OSCAL uses to model validation (product + validation joined by
    # `rel="validation"`). `validation` is therefore documented as PARTIAL on
    # CDEF — see docs/api and the Component Definitions guide — and the full
    # model lives on the SSP, where ssp_components is a real table with many
    # rows per document.
    component = {
      "uuid"        => OscalUuidService.derived(@document.uuid, "cdef-component"),
      "type"        => @document.component_type.presence || "software",
      "title"       => @document.component_title.presence || @document.name,
      "description" => @document.component_description.presence ||
                       @document.description.presence ||
                       "Imported component definition"
    }

    props = Array(@document.component_props_data)
    links = Array(@document.component_links_data)
    component["props"] = props if props.present?
    component["links"] = links if links.present?

    # #1051 — built FROM the controls that exist, not unconditionally.
    #
    # OSCAL requires `implemented-requirements` to hold at least one entry, so a
    # document with no controls exported a `control-implementations` scaffold
    # wrapping an empty array and failed validation:
    #
    #   /component-definition/components/0/control-implementations/0/
    #     implemented-requirements: array size is less than: 1
    #
    # That was 163 of 232 documents — 70% of the library — all of them AWS Labs
    # service CDEFs (#466, #939) that carry no control mappings. Not caused by the
    # 1.2.2 default (#1020): identical at 1.1.2, so it was pre-existing and simply
    # never measured, because every per-type export spec builds a fixture WITH
    # controls.
    #
    # A component with no `control-implementations` is legal OSCAL, and it is the
    # honest export: the document genuinely maps no controls. Whether the ingest
    # should create such documents at all is a separate question (#1051 option 2)
    # and deliberately not decided here.
    #
    # Same idiom as `props`/`links` above: emit what exists.
    impls = build_control_implementations(controls.to_a)
    component["control-implementations"] = impls if impls.any?
    component
  end

  def build_implemented_requirement(control)
    field_map = control.cdef_control_fields.index_by(&:field_name)

    result = {
      "uuid"        => OscalUuidService.derived(control.uuid, "cdef-ir"),
      "control-id"  => normalize_control_id(control, field_map),
      "description" => build_description(control, field_map)
    }

    props = build_props(control)
    result["props"] = props if props.any?

    stmts = build_ir_statements(control, field_map, result["control-id"])
    result["statements"] = stmts if stmts

    # OSCAL-compliant enhanced fields
    append_ir_enhanced_props(result, field_map)
    append_ir_responsible_roles(result, field_map)
    append_ir_set_parameters(result, field_map)
    append_ir_links(result, control)

    result
  end

  # #393: table-driven statements when records exist (backfilled or imported);
  # falls back to a single field-synthesized statement for un-backfilled CDEFs
  # (no linked profile) so existing exports work. Returns the array or nil.
  def build_ir_statements(control, field_map, control_id)
    if control.cdef_control_statements.any?
      return control.cdef_control_statements.order(:row_order).map do |stmt|
        entry = {
          "statement-id" => stmt.statement_id,
          "uuid"         => stmt.uuid,
          "description"  => stmt.implementation_prose.presence || stmt.remarks
        }
        entry["set-parameters"] = stmt.set_parameters_data if stmt.set_parameters_data.present?
        entry.compact
      end
    end

    narrative = field_map["implementation_narrative"]&.field_value
    return nil if narrative.blank?

    [ {
      "statement-id" => "#{control_id}_stmt",
      "uuid"         => OscalUuidService.derived(control.uuid, "cdef-statement", "default"),
      "description"  => narrative
    } ]
  end

  # Append CDEF field-derived props in a stable order (implementation-status,
  # control-origin, baseline-priority).
  def append_ir_enhanced_props(result, field_map)
    {
      "implementation_status" => "implementation-status",
      "control_origin"        => "control-origin",
      "baseline_priority"     => "baseline-priority"
    }.each do |field_name, prop_name|
      value = field_map[field_name]&.field_value
      next if value.blank?
      result["props"] ||= []
      result["props"] << { "name" => prop_name, "value" => value }
    end
  end

  def append_ir_responsible_roles(result, field_map)
    roles = field_map["responsible_roles"]&.field_value
    return if roles.blank?
    result["responsible-roles"] = roles.split(",").map(&:strip).reject(&:blank?).map do |role|
      { "role-id" => role }
    end
  end

  def append_ir_set_parameters(result, field_map)
    params = field_map["set_parameters"]&.field_value
    return if params.blank?
    parsed = JSON.parse(params)
    result["set-parameters"] = parsed.map do |param|
      { "param-id" => param["id"] || param["param-id"], "values" => Array(param["value"] || param["values"]) }
    end
  rescue JSON::ParserError
    # Skip malformed set_parameters
  end

  def append_ir_links(result, control)
    return unless control.respond_to?(:back_matter_resources) && control.back_matter_resources.any?
    result["links"] = control.back_matter_resources.map do |resource|
      { "href" => "##{resource.uuid}", "rel" => resource.rel.presence || "reference" }
    end
  end

  def normalize_control_id(control, field_map)
    raw = if (nist = field_map["nist_controls"]&.field_value).present?
      nist.split(",").first.strip
    elsif control.control_id.present?
      control.control_id
    else
      "unknown-#{control.id}"
    end

    # #852 — resolution of WHICH id to use stays here (it is specific to CDEF
    # field mapping); the normalisation itself is shared, so a component
    # definition writes the same identifier for a control as the SSP, SAP, SAR
    # and POA&M exports do.
    #
    # #1030 — `control_key`, not `canonical`. This method prefers the
    # `nist_controls` field, which holds the statement-level reference the CCI
    # mapping supplies (`cm-6-b`), so the export published a statement into an
    # OSCAL `control-id`. An implemented-requirement's `control-id` must name a
    # control in the profile or catalog the control-implementation sources, and
    # those hold controls and enhancements — never statement parts. Reducing
    # here also makes the preference above moot: `nist_controls` and
    # `control_id` now reduce to the same key.
    #
    # Statement-level targeting is not lost to OSCAL; it belongs in `statements`
    # rather than in `control-id`. Emitting a properly-formed `cm-6_smt.b` there
    # is a fidelity improvement this does not attempt.
    ControlId.control_key(raw)
  end

  def build_description(control, field_map)
    parts = []
    parts << control.title if control.title.present?
    parts << field_map["description"]&.field_value if field_map["description"]&.field_value.present?
    parts << "Fix: #{field_map['fix_text']&.field_value}" if field_map["fix_text"]&.field_value.present?
    parts.join("\n\n").presence || "No description available"
  end

  def build_props(control)
    props = []
    props << { "name" => "severity", "value" => control.severity } if control.severity.present?
    props << { "name" => "rule-id",  "value" => control.rule_id }  if control.rule_id.present?
    props << { "name" => "group-id", "value" => control.group_id } if control.group_id.present?
    props << { "name" => "stig-id",  "value" => control.stig_id }  if control.stig_id.present?

    if control.cci_references.present?
      control.cci_references.split(",").each do |cci|
        props << { "name" => "cci", "ns" => "http://cyber.mil/cci", "value" => cci.strip }
      end
    end

    props
  end

  def determine_source
    case @document.cdef_type
    when "disa_stig" then "https://public.cyber.mil/stigs/"
    when "cis"       then "https://www.cisecurity.org/cis-benchmarks"
    when "scap"      then "https://csrc.nist.gov/projects/security-content-automation-protocol"
    else "https://sparc.local/component-definitions/#{@document.id}"
    end
  end

  def build_back_matter
    @document.build_oscal_back_matter
  end
end
