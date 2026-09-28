# API for the FedRAMP 20x KSI catalog.
#
# All endpoints require Bearer token authentication.
#
# GET  /api/v1/ksi_catalog/themes         — list KSI themes
# GET  /api/v1/ksi_catalog/indicators     — list KSIs (filterable by theme, impact_level)
# GET  /api/v1/ksi_catalog/indicators/:id — show KSI with mapped NIST controls
# GET  /api/v1/ksi_catalog/mappings       — KSI-to-NIST mapping entries
# POST /api/v1/ksi_catalog/import         — import the vendored FedRAMP/rules snapshot (#1172)
#
# #1115 — themes and indicators FedRAMP no longer publishes are RETIRED, not
# deleted, so the assessments recorded against them survive. The list endpoints
# return the current catalog; `?include_retired=true` adds the retired entries,
# each carrying `retired_at` and `superseded_by`. A retired indicator is still
# found by its id, so an old reference resolves to what it was.
#
# NIST 800-53 Controls:
#   AC-3 Access Enforcement (Bearer token auth; import needs catalogs.write)
#   AU-12 Audit Record Generation (the import is audited by the service)
#   CM-3 Configuration Change Control (import is validated, all-or-nothing)
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
#
class Api::V1::KsiCatalogController < Api::V1::BaseController
  before_action :set_ksi_catalog, except: :import
  before_action :authorize_catalogs_write!, only: :import

  # GET /api/v1/ksi_catalog/themes
  def themes
    families = @ksi_catalog.control_families.current_first
    families = families.not_retired unless include_retired?

    rows = families.map { |f| serialize_theme(f) }
    render json: { data: rows, meta: whole_collection(rows) }
  end

  # GET /api/v1/ksi_catalog/indicators
  def indicators
    scope = CatalogControl.joins(:control_family)
                          .where(control_families: { control_catalog_id: @ksi_catalog.id })
                          .reorder(Arel.sql("control_families.retired_at IS NOT NULL"), "control_families.sort_order",
                                   Arel.sql("catalog_controls.retired_at IS NOT NULL"), "catalog_controls.sort_id")
    scope = scope.not_retired unless include_retired?

    scope = scope.where(control_families: { code: params[:theme] }) if params[:theme].present?
    if params[:impact_level].present?
      scope = scope.where("baseline_impact ILIKE ?", "%#{params[:impact_level]}%")
    end

    result = paginate(scope)
    render json: {
      data: result[:data].map { |c| serialize_indicator(c) },
      meta: result[:meta]
    }
  end

  # GET /api/v1/ksi_catalog/indicators/:id
  def show_indicator
    indicator = CatalogControl.joins(:control_family)
                              .where(control_families: { control_catalog_id: @ksi_catalog.id })
                              .where(control_id: ControlId.forms(params[:id]))
                              .first!

    mapped_controls = load_mapped_controls(indicator.control_id)

    render json: {
      data: serialize_indicator(indicator, detailed: true).merge(
        mapped_nist_controls: mapped_controls
      )
    }
  end

  # POST /api/v1/ksi_catalog/import
  #
  # Synchronous: the snapshot is 46 indicators and one transaction. Reads only
  # the vendored copy in lib/data/fedramp — this endpoint never fetches from the
  # network. `dry_run=true` runs the whole import and rolls it back.
  #
  #   200 imported | unchanged | planned (dry run)
  #   422 refused — schema-invalid data or an inapplicable map; nothing written
  def import
    refuse_unrecognized_import_fields!
    dry_run = ActiveModel::Type::Boolean.new.cast(params[:dry_run]) || false
    result = FedrampKsiImportService.new(dry_run: dry_run).call

    body = { status: result.status.to_s, upstream_version: result.version,
             dry_run: dry_run, changes: result.changes, errors: result.errors }
    render json: { data: body }, status: result.refused? ? :unprocessable_content : :ok
  end

  # GET /api/v1/ksi_catalog/mappings
  def mappings
    mapping = ControlMapping.find_by(source_catalog: @ksi_catalog)

    unless mapping
      # #1019 — the empty case used to answer with a meta shaped nothing like
      # the populated one, so a client reading meta.count worked against a
      # seeded instance and broke against a fresh one.
      render json: { data: [], meta: whole_collection([], message: "No KSI-to-NIST mapping found") }
      return
    end

    entries = mapping.control_mapping_entries.order(:row_order)
    result = paginate(entries, items: 50)

    render json: {
      data: result[:data].map { |e| serialize_mapping_entry(e) },
      meta: result[:meta].merge(
        mapping_name: mapping.name,
        mapping_status: mapping.status
      )
    }
  end

  private

  def set_ksi_catalog
    @ksi_catalog = ControlCatalog.find_by!(source: FedrampKsiImportService::SOURCE)
  end

  def include_retired? = ActiveModel::Type::Boolean.new.cast(params[:include_retired]) || false

  IMPORT_FIELDS = %w[dry_run].freeze

  # The import takes one option and no record. A body carrying anything else
  # is refused rather than ignored: answering 200 to a request the endpoint
  # could not have understood is the #994 shape. There is no root key, so
  # `permit_strictly` does not apply; Rails' JSON params wrapper copies the
  # body under the controller's name, which is not a field the caller sent.
  def refuse_unrecognized_import_fields!
    wrapper = respond_to?(:_wrapper_key, true) ? _wrapper_key.to_s : nil
    submitted = request.request_parameters.keys.map(&:to_s) - [ wrapper ]
    unknown = submitted - IMPORT_FIELDS - ALWAYS_ALLOWED_FIELDS
    raise UnrecognizedFields.new(unknown, IMPORT_FIELDS) if unknown.any?
  end

  # Same rule as the catalogs API: admins always pass; everyone else needs
  # `catalogs.write`.
  def authorize_catalogs_write!
    return if current_user&.instance_administrator?
    return if current_user&.has_permission?("catalogs.write")

    render json: { error: "Forbidden" }, status: :forbidden
  end

  def serialize_theme(family)
    {
      code: family.code,
      name: family.name,
      sort_order: family.sort_order,
      indicators_count: family.catalog_controls.not_retired.count,
      retired_at: family.retired_at&.iso8601
    }
  end

  def serialize_indicator(control, detailed: false)
    data = {
      control_id: control.control_id,
      label: control.label,
      title: control.title,
      theme_code: control.control_family.code,
      theme_name: control.control_family.name,
      baseline_impact: control.baseline_impact,
      baseline_levels: control.baseline_levels,
      retired_at: control.retired_at&.iso8601,
      superseded_by: control.superseded_by
    }

    if detailed
      data[:description] = control.description
      guidance = control.guidance_data.is_a?(Hash) ? control.guidance_data : {}
      data[:validation_frequency] = guidance["validation_frequency"]
      data[:evidence_type] = guidance["evidence_type"]
      data[:automation_required] = guidance["automation_required"]
    end

    data
  end

  def serialize_mapping_entry(entry)
    {
      source_control_id: entry.source_control_id,
      target_control_id: entry.target_control_id,
      relationship: entry.relationship,
      source_type: entry.source_type,
      target_type: entry.target_type
    }
  end

  def load_mapped_controls(ksi_control_id)
    mapping = ControlMapping.find_by(source_catalog: @ksi_catalog)
    return [] unless mapping

    mapping.control_mapping_entries
           .where(source_control_id: ksi_control_id)
           .map { |e| { target: e.target_control_id, relationship: e.relationship } }
  end
end
