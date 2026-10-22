# Builds an OSCAL v1.1.2 Profile JSON document from a ProfileDocument
# and its controls.  Validates the output against the official NIST
# JSON schema before returning.
#
# Usage:
#   service = OscalProfileExportService.new(profile_document)
#   json_string = service.export            # validates, raises on failure
#   json_string = service.export_unvalidated # skips validation
#   result      = service.validation_result  # inspect errors without raising
#
class OscalProfileExportService
  include OscalExportReconciliation

  DEFAULT_OSCAL_VERSION = OscalSchema::DEFAULT_VERSION
  OSCAL_VERSION = DEFAULT_OSCAL_VERSION # backward compat

  def initialize(profile_document)
    @document = profile_document
  end

  def export
    # #911 layer 2 — never publish a control-id that resolves to no loaded
    # catalog. TokenDatatype constrains the character set, not existence.
    refuse_unresolvable_controls!(label: "Profile", name: @document.name,
                                  control_ids: @document.profile_controls.pluck(:control_id))
    data = build_profile
    OscalSchemaValidationService.validate!(:profile, data, version: effective_oscal_version)
    JSON.pretty_generate(data)
  end

  def export_unvalidated
    JSON.pretty_generate(build_profile)
  end

  def validation_result
    data = build_profile
    OscalSchemaValidationService.validate(:profile, data)
  end


  def effective_oscal_version
    @document.oscal_version.presence || DEFAULT_OSCAL_VERSION
  end

  private

  def build_profile
    {
      "profile" => {
        "uuid"         => @document.uuid,
        "metadata"     => build_metadata,
        "imports"      => build_imports,
        "merge"        => build_merge,
        "modify"       => build_modify,
        "back-matter"  => build_back_matter
      }.compact
    }
  end

  def build_metadata
    @document.build_oscal_metadata(
      default_version: @document.profile_version || "1.0.0",
      default_roles: [
        { "id" => "creator", "title" => "Document Creator" }
      ],
      default_parties: [
        { "uuid" => OscalUuidService.org_party_uuid_for(@document),
          "type" => "organization", "name" => SparcConfig.oscal_org_name }
      ]
    )
  end

  # #1234 — one import per source catalog, each selecting its own controls.
  # A profile that imports NIST plus an organization's own catalog exported a
  # single NIST import listing the custom controls too, which said NIST
  # published them. A control with no recorded source belongs to the primary
  # catalog, as every profile imported before #1234 does.
  def build_imports
    controls = @document.profile_controls.order(:row_order).to_a
    primary  = @document.control_catalog
    groups   = controls.group_by { |c| c.source_catalog_id || primary&.id }

    groups.map do |catalog_id, members|
      catalog = source_catalogs[catalog_id]
      {
        "href" => import_href(catalog, members),
        "include-controls" => [ {
          # #852 — with-ids is TokenDatatype; a profile control stored as
          # "AC-2 (1)" would otherwise fail the profile schema at export.
          "with-ids" => members.map { |c| ControlId.canonical(c.control_id) }
        } ]
      }
    end.presence || [ { "href" => import_href(primary, []), "include-controls" => [ { "with-ids" => [] } ] } ]
  end

  # #395 P2: prefer `uuid:<catalog.oscal_uuid>` so the catalog reference is
  # round-trip-stable. Without a catalog, the import's own href as the file
  # gave it (#1234: per import, so an unlinked one keeps its own), then the
  # first import's, then "#" as the schema-required last resort.
  def import_href(catalog, members)
    return "uuid:#{catalog.oscal_uuid}" if catalog&.oscal_uuid.present?

    ids = members.map(&:control_id)
    recorded = Array(@document.import_metadata&.dig("imports"))
                 .find { |imp| (Array(imp["control_ids"]) & ids).any? }
    recorded&.dig("href").presence ||
      @document.import_metadata&.dig("catalog_href") ||
      (catalog ? "##{catalog.oscal_uuid}" : "#")
  end

  # Every catalog the profile's controls come from, by id: the primary
  # catalog and each recorded source.
  def source_catalogs
    @source_catalogs ||= begin
      ids = @document.profile_controls.distinct.pluck(:source_catalog_id).compact
      ids << @document.control_catalog_id if @document.control_catalog_id
      ControlCatalog.where(id: ids.uniq).index_by(&:id)
    end
  end

  def build_merge
    @document.import_metadata&.dig("merge") || { "as-is" => true }
  end

  def build_modify
    controls = @document.profile_controls
                        .order(:row_order)
                        .includes(:profile_control_fields)

    alters         = controls.filter_map { |ctrl| build_alter(ctrl) }
    set_parameters = build_set_parameters(controls)

    result = {}
    result["set-parameters"] = set_parameters if set_parameters.any?
    result["alters"]         = alters         if alters.any?
    result.presence
  end

  def build_alter(control)
    props = []
    if control.priority.present?
      props << { "name" => "priority", "ns" => OscalNamespace.instance, "value" => control.priority }
    end

    # #1106 slice 5 — author-defined props.
    #
    # Whatever an author types after `prop:` became a prop name in NIST's
    # namespace: unbounded, and the only finding in the audit that was open-ended
    # rather than a fixed list. The fix is NOT an allow-list — extending OSCAL is
    # the point, and NIST provides for it. It is a namespace: these are the
    # deployment's own terms, so they are emitted under the deployment's
    # namespace, where they are legal by construction and never a violation.
    control.profile_control_fields.each do |field|
      next unless field.field_name.start_with?("prop:")
      prop_name = field.field_name.delete_prefix("prop:")
      props << { "name" => prop_name, "ns" => OscalNamespace.instance, "value" => field.field_value }
    end

    return nil if props.empty?

    {
      # #852 — TokenDatatype, same as with-ids above.
      "control-id" => ControlId.canonical(control.control_id),
      "adds" => [ { "position" => "starting", "props" => props } ]
    }
  end

  def build_set_parameters(controls)
    params = []
    controls.each do |ctrl|
      ctrl.profile_control_fields.each do |field|
        next unless field.field_name.start_with?("parameter:")
        param_id = field.field_name.delete_prefix("parameter:")
        # A set-parameter states "this ODP is tailored to these values". OSCAL
        # requires at least one value, and ProfileControlSelectionService creates
        # a parameter field for EVERY ODP the control exposes — blank whenever
        # the catalog param carries no label. Emitting "values": [] therefore
        # asserted a tailoring the author never made AND made the whole profile
        # fail schema validation, so any profile containing such a control could
        # not be exported at all.
        #
        # Omitting an untailored parameter invents nothing; it drops an assertion
        # that was never made. (Contrast poam risk/statement, which is REQUIRED
        # substantive content and must never be synthesised — see that exporter.)
        # #942 — ParameterValueList, not a bare comma split. OSCAL insert markup
        # always contains a comma, so splitting on ", " turned a single chosen
        # branch ("establish {{ insert: param, ac-20_odp.02 }}") into two
        # `set-parameters` values nobody selected, and both were exported.
        values = ParameterValueList.split(field.field_value)
        next if values.empty?

        params << { "param-id" => param_id, "values" => values }
      end
    end
    params
  end

  def build_back_matter
    base = @document.build_oscal_back_matter
    resources = base["resources"] || []

    # Add a resource entry per source catalog so each import href resolves
    # (#1234: every imported catalog, primary first, not only the primary).
    primary_id = @document.control_catalog_id
    source_catalogs.values.sort_by { |c| [ c.id == primary_id ? 0 : 1, c.id ] }.reverse_each do |catalog|
      resources.unshift({
        "uuid"        => catalog.oscal_uuid,
        "title"       => catalog.name,
        "description" => "Source catalog for this profile",
        "rlinks"      => [ { "href" => "#{catalog.name.parameterize}.json", "media-type" => "application/json" } ]
      })
    end

    # Add source profile resource entry if this is a tailored profile
    source = @document.source_profile
    if source
      resources.unshift({
        "uuid"        => source.uuid,
        "title"       => source.name,
        "description" => "Source profile this was tailored from",
        "rlinks"      => [ { "href" => "#{source.name.parameterize}.json", "media-type" => "application/json" } ]
      })
    end

    { "resources" => resources }
  end
end
