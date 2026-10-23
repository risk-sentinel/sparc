# Builds an OSCAL v1.1.2 Catalog JSON document from a ControlCatalog
# and its families/controls.  Validates the output against the official
# NIST JSON schema before returning.
#
# Usage:
#   service = OscalCatalogExportService.new(control_catalog)
#   json_string = service.export            # validates, raises on failure
#   json_string = service.export_unvalidated # skips validation
#   result      = service.validation_result  # inspect errors without raising
#
class OscalCatalogExportService
  DEFAULT_OSCAL_VERSION = OscalSchema::DEFAULT_VERSION
  OSCAL_VERSION = DEFAULT_OSCAL_VERSION # backward compat

  def initialize(control_catalog)
    @catalog = control_catalog
  end

  def export
    data = build_catalog
    OscalSchemaValidationService.validate!(:catalog, data, version: effective_oscal_version)
    JSON.pretty_generate(data)
  end

  def export_unvalidated
    JSON.pretty_generate(build_catalog)
  end

  def validation_result
    data = build_catalog
    OscalSchemaValidationService.validate(:catalog, data)
  end


  def effective_oscal_version
    @catalog.oscal_version.presence || DEFAULT_OSCAL_VERSION
  end

  private

  def build_catalog
    {
      "catalog" => {
        "uuid"     => @catalog.oscal_uuid.presence || OscalUuidService.derived(@catalog.id.to_s, "catalog-root"),
        "metadata" => build_metadata,
        "groups"   => build_groups
      }.compact
    }
  end

  def build_metadata
    @catalog.build_oscal_metadata(
      default_version: @catalog.oscal_document_version || "1.0.0",
      default_roles: [
        { "id" => "creator", "title" => "Document Creator" }
      ],
      default_parties: [
        { "uuid" => OscalUuidService.derived(@catalog.oscal_uuid.to_s, "catalog-default-party"),
          "type" => "organization", "name" => SparcConfig.oscal_org_name }
      ]
    )
  end

  def build_groups
    @catalog.control_families.includes(:catalog_controls).order(:sort_order).map do |family|
      # #1252 — a family imported from OSCAL records its group (id, class,
      # props, parts, links, params) and its nested groups; one created in
      # SPARC, or imported before that, records nothing and exports as a NIST
      # family. The title is the family's current name, which an editor may
      # have changed.
      data = family.group_data.to_h
      by_group = CatalogGroupTree.by_group(family.catalog_controls.reject(&:statement_item?), data)
      props = [ *data["props"], *(family.retired? ? [ WITHDRAWN_PROP ] : []) ].uniq
      {
        "id"       => data["id"].presence || family.code.downcase,
        "class"    => data.empty? ? "family" : data["class"],
        "title"    => family.name,
        "params"   => data["params"],
        "props"    => props.presence,
        "links"    => data["links"],
        "parts"    => data["parts"],
        "groups"   => build_nested_groups(data["groups"], by_group).presence,
        # The schema requires a present `controls` to hold at least one; a
        # family with none omits the key rather than exporting an invalid [].
        "controls" => build_controls(by_group[nil]).presence
      }.compact
    end
  end

  def build_nested_groups(definitions, by_group)
    Array(definitions).map do |definition|
      definition.except("groups", "key").merge(
        "groups"   => build_nested_groups(definition["groups"], by_group).presence,
        "controls" => build_controls(by_group[definition["key"] || definition["id"]]).presence
      ).compact
    end
  end

  # #1252 — the controls and their nesting come from the hierarchy imports
  # record (`statement_item`, `parent_control_id`), not from NIST's id shape:
  # the shape test exported no controls at all for a catalog with other ids
  # (FedRAMP 20x `ksi-auth-01`). OSCAL nests a child control (an enhancement)
  # inside its parent, at any depth; a control whose parent is not in this
  # group is exported at the group's top level rather than dropped.
  def build_controls(group_controls)
    controls = Array(group_controls).sort_by(&:control_id)
    ids = controls.to_set(&:control_id)
    children = controls.group_by { |c| ids.include?(c.parent_control_id) ? c.parent_control_id : nil }

    nest = lambda do |control|
      ctrl_hash = build_control(control)
      kids = children[control.control_id]
      ctrl_hash["controls"] = kids.map(&nest) if kids.present?
      ctrl_hash
    end
    Array(children[nil]).map(&nest)
  end

  def build_control(control)
    result = {
      "id"    => control.control_id,
      "class" => "SP800-53",
      "title" => control.title
    }

    # #1241 — through CatalogControl.oscal_param: a select the catalog answered
    # is emitted as its answer, since OSCAL allows `values` or `select`, not both.
    result["params"] = control.params_list.map { |param| CatalogControl.oscal_param(param) } if control.params_present?

    props = build_control_props(control)
    result["props"] = props if props.any?

    parts = build_control_parts(control)
    result["parts"] = parts if parts.any?

    links = retired_links(control)
    result["links"] = links if links.any?

    result
  end

  # #1115 — a retired entry (a FedRAMP KSI the source no longer publishes) is
  # exported the way NIST exports a withdrawn control: `status: withdrawn`. Its
  # successors are linked `related`, NOT `incorporated-into` — FedRAMP names a
  # closest successor, it does not say the old requirement was folded into it.
  WITHDRAWN_PROP = { "name" => "status", "value" => "withdrawn" }.freeze

  def retired_links(control)
    return [] unless control.retired?

    Array(control.superseded_by).map { |id| { "href" => "##{id.to_s.downcase}", "rel" => "related" } }
  end

  def build_control_props(control)
    props = []
    props << { "name" => "label", "value" => control.display_id }
    if control.sort_id.present?
      props << { "name" => "sort-id", "value" => control.sort_id }
    end
    # #1106 — `label` and `sort-id` above are CORRECT unnamespaced: NIST's own
    # 800-53 catalog emits 12,831 and 1,196 of them exactly that way. `priority`
    # and `impact-level` are not NIST catalog prop names, so they carry the
    # deployment namespace instead of claiming one.
    if control.priority.present?
      props << { "name" => "priority", "ns" => OscalNamespace.instance, "value" => control.priority }
    end

    if control.baseline_impact.present?
      control.baseline_impact.split(",").map(&:strip).each do |level|
        props << { "name" => "impact-level", "ns" => OscalNamespace.instance, "value" => level }
      end
    end

    props << WITHDRAWN_PROP if control.retired?
    props
  end

  def build_control_parts(control)
    parts = []
    guidance = control.guidance_data || {}

    if guidance["statement"].present?
      parts << {
        "id"    => "#{control.control_id}_smt",
        "name"  => "statement",
        "prose" => guidance["statement"]
      }
    end

    if guidance["supplemental_guidance"].present?
      guidance_part = {
        "id"    => "#{control.control_id}_gdn",
        "name"  => "guidance",
        "prose" => guidance["supplemental_guidance"]
      }

      if guidance["related_controls"].present?
        guidance_part["links"] = guidance["related_controls"].split(",").map(&:strip).map do |ref|
          { "href" => "##{ref.downcase}", "rel" => "related" }
        end
      end

      parts << guidance_part
    end

    parts
  end
end
