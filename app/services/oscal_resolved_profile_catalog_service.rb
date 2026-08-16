# Builds an OSCAL v1.1.2 resolved-profile Catalog JSON document from a
# ProfileDocument and its linked ControlCatalog.  The output is a full
# Catalog containing only the controls selected in the profile, with
# catalog data (params, props, parts) merged with profile modifications
# (priority overrides, organization-defined parameter values).
#
# Usage:
#   service = OscalResolvedProfileCatalogService.new(profile_document)
#   json_string = service.export
#
class OscalResolvedProfileCatalogService
  DEFAULT_OSCAL_VERSION = OscalSchema::DEFAULT_VERSION
  OSCAL_VERSION = DEFAULT_OSCAL_VERSION # backward compat
  MEDIA_TYPE = "media-type".freeze

  def initialize(profile_document)
    @profile = profile_document
    @catalog = profile_document.control_catalog
    raise ArgumentError, "ProfileDocument must have a linked control_catalog" unless @catalog
  end

  def export
    JSON.pretty_generate(build_catalog)
  end

  def effective_oscal_version
    @profile.oscal_version.presence || DEFAULT_OSCAL_VERSION
  end

  private

  def build_catalog
    {
      "catalog" => {
        "uuid"         => SecureRandom.uuid,
        "metadata"     => build_metadata,
        "groups"       => build_groups,
        "back-matter"  => build_back_matter
      }.compact
    }
  end

  def build_metadata
    {
      "title"         => @profile.name,
      "version"       => @profile.profile_version || "1.0.0",
      "oscal-version" => @profile.oscal_version || effective_oscal_version,
      "last-modified" => Time.current.iso8601,
      "published"     => @profile.published,
      "props"         => [ { "name" => "resolution-tool", "value" => "SPARC" } ],
      "links"         => [ { "href" => "##{@profile.uuid}", "rel" => "source-profile" } ],
      "roles"         => [ { "id" => "creator", "title" => "Document Creator" } ],
      "parties"       => [ {
        "uuid" => SecureRandom.uuid,
        "type" => "organization",
        "name" => "SPARC Export"
      } ]
    }.compact
  end

  def build_groups
    profile_controls = @profile.profile_controls
                               .order(:row_order)
                               .includes(:profile_control_fields)

    # Build a lookup of profile control data keyed by control_id
    profile_lookup = profile_controls.index_by(&:control_id)
    selected_ids = profile_lookup.keys.to_set

    # Group catalog controls by family, filtered to selected controls
    families = @catalog.control_families
                       .includes(:catalog_controls)
                       .order(:sort_order)

    groups = families.filter_map do |family|
      selected_controls = family.catalog_controls
                                .select { |cc| selected_ids.include?(cc.control_id) }
                                .sort_by(&:control_id)

      next if selected_controls.empty?

      {
        "id"       => family.code.downcase,
        "class"    => "family",
        "title"    => family.name,
        "controls" => selected_controls.map { |cc| build_control(cc, profile_lookup[cc.control_id]) }
      }
    end

    groups.presence
  end

  def build_control(catalog_control, profile_control)
    result = {
      "id"    => catalog_control.control_id,
      "class" => "SP800-53",
      "title" => catalog_control.title
    }

    # Merge params from catalog with profile parameter values
    params = build_resolved_params(catalog_control, profile_control)
    result["params"] = params if params.present?

    props = build_control_props(catalog_control, profile_control)
    result["props"] = props if props.any?

    parts = build_control_parts(catalog_control, profile_control)
    result["parts"] = parts if parts.any?

    result
  end

  # Merges catalog param definitions with profile-set parameter values.
  # If the profile has a value for a parameter, it replaces the label.
  def build_resolved_params(catalog_control, profile_control)
    return [] unless catalog_control.params_present?

    param_values = set_parameter_values(profile_control)
    # #942 — the stored value for a `select` is WHICH branches were chosen, and
    # each branch can itself reference another parameter. Copying it into the
    # label verbatim put `{{ insert: param, ac-20_odp.02 }}` back into the
    # resolved output through the params, after the statement had been resolved.
    resolver = parameter_resolver(catalog_control, profile_control)

    catalog_control.params_list.map do |param|
      resolved = param.dup
      if param_values[param["id"]].present?
        resolved["label"] = resolver.resolve_param(param["id"]).presence ||
                            param_values[param["id"]]
      end

      # The options a selection offers are prose a person reads too, and
      # "establish {{ insert: param, ac-20_odp.02 }}" is the exact string a
      # resolved profile must not contain. Resolved in place; the choice keeps
      # its own wording ("establish", "identify") and only the reference is
      # substituted.
      if resolved["select"].is_a?(Hash) && resolved["select"]["choice"].present?
        select = resolved["select"].dup
        select["choice"] = Array(select["choice"]).map { |c| resolver.resolve_text(c).strip }
        resolved["select"] = select
      end

      resolved
    end
  end

  # param_id => the operator's set value. `parameter:` only: `parameter_label:`
  # is the catalog's own wording and `parameter_choices:` (#942) is the list of
  # options, neither of which is an answer.
  def set_parameter_values(profile_control)
    values = {}
    return values unless profile_control

    profile_control.profile_control_fields.each do |field|
      next unless field.field_name.start_with?("parameter:")
      next if field.field_name.start_with?("parameter_label:")

      param_id = field.field_name.delete_prefix("parameter:")
      values[param_id] = field.field_value if field.field_value.present?
    end
    values
  end

  # Resolves against the control's own params PLUS its parent's, because a
  # sub-control's statement references parameters declared on the parent
  # ("ac-1a" referencing "ac-1_prm_1"); resolving only the local set would leave
  # exactly those references standing.
  def parameter_resolver(catalog_control, profile_control)
    OscalParameterResolver.new(
      catalog_control.effective_params_list.presence || catalog_control.params_list,
      set_parameter_values(profile_control)
    )
  end

  def build_control_props(catalog_control, profile_control)
    props = []
    props << { "name" => "label", "value" => catalog_control.display_id }
    if catalog_control.sort_id.present?
      props << { "name" => "sort-id", "value" => catalog_control.sort_id }
    end

    # Use profile priority if set, otherwise fall back to catalog priority
    priority = profile_control&.priority.presence || catalog_control.priority.presence
    props << { "name" => "priority", "value" => priority } if priority.present?

    if catalog_control.baseline_impact.present?
      catalog_control.baseline_impact.split(",").map(&:strip).each do |level|
        props << { "name" => "impact-level", "value" => level }
      end
    end

    props
  end

  def build_control_parts(catalog_control, profile_control = nil)
    parts = []
    guidance = catalog_control.guidance_data || {}
    # #942 — this is a RESOLVED catalog. Copying the statement verbatim left
    # `{{ insert: param, ac-20_odp.01 }}` in the output, which is the one thing
    # a resolved profile must not contain: the reader is handed markup where the
    # organization-defined text belongs. Resolution is recursive because a
    # substituted parameter can itself reference others.
    resolver = parameter_resolver(catalog_control, profile_control)

    if guidance["statement"].present?
      parts << {
        "id"    => "#{catalog_control.control_id}_smt",
        "name"  => "statement",
        "prose" => resolver.resolve_text(guidance["statement"])
      }
    end

    if guidance["supplemental_guidance"].present?
      guidance_part = {
        "id"    => "#{catalog_control.control_id}_gdn",
        "name"  => "guidance",
        "prose" => resolver.resolve_text(guidance["supplemental_guidance"])
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

  def build_back_matter
    resources = []

    # Source profile resource
    resources << {
      "uuid"        => @profile.uuid,
      "title"       => @profile.name,
      "description" => "Source profile used to generate this resolved catalog",
      "rlinks"      => [ { "href" => "#{@profile.name.parameterize}.json", MEDIA_TYPE => "application/json" } ]
    }

    # Source catalog resource
    resources << {
      "uuid"        => @catalog.oscal_uuid,
      "title"       => @catalog.name,
      "description" => "Source catalog referenced by the profile",
      "rlinks"      => [ { "href" => "#{@catalog.name.parameterize}.json", MEDIA_TYPE => "application/json" } ]
    }

    # SPARC identifying resource
    resources << {
      "uuid"        => SecureRandom.uuid,
      "title"       => "SPARC Document Source",
      "description" => "Managed by SPARC",
      "rlinks"      => [ { "href" => SparcConfig.app_url, MEDIA_TYPE => "text/html" } ]
    }

    { "resources" => resources }
  end
end
