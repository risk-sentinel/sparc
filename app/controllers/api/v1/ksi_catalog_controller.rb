# Read-only API for browsing the FedRAMP 20x KSI catalog.
#
# All endpoints require Bearer token authentication.
# No write operations — the KSI catalog is seeded from FedRAMP specifications.
#
# GET /api/v1/ksi_catalog/themes         — list KSI themes
# GET /api/v1/ksi_catalog/indicators     — list KSIs (filterable by theme, impact_level)
# GET /api/v1/ksi_catalog/indicators/:id — show KSI with mapped NIST controls
# GET /api/v1/ksi_catalog/mappings       — KSI-to-NIST mapping entries
#
# NIST 800-53 Controls:
#   AC-3 Access Enforcement (Bearer token auth)
#   AU-12 Audit Record Generation (read-only, no mutations)
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
#
class Api::V1::KsiCatalogController < Api::V1::BaseController
  before_action :set_ksi_catalog

  # GET /api/v1/ksi_catalog/themes
  def themes
    families = @ksi_catalog.control_families.order(:sort_order)

    render json: {
      data: families.map { |f| serialize_theme(f) }
    }
  end

  # GET /api/v1/ksi_catalog/indicators
  def indicators
    scope = CatalogControl.joins(:control_family)
                          .where(control_families: { control_catalog_id: @ksi_catalog.id })
                          .order("control_families.sort_order", "catalog_controls.sort_id")

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
                              .find_by!(control_id: params[:id])

    mapped_controls = load_mapped_controls(indicator.control_id)

    render json: {
      data: serialize_indicator(indicator, detailed: true).merge(
        mapped_nist_controls: mapped_controls
      )
    }
  end

  # GET /api/v1/ksi_catalog/mappings
  def mappings
    mapping = ControlMapping.find_by(source_catalog: @ksi_catalog)

    unless mapping
      render json: { data: [], meta: { message: "No KSI-to-NIST mapping found" } }
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
    @ksi_catalog = ControlCatalog.find_by!(source: "FedRAMP 20x")
  end

  def serialize_theme(family)
    {
      code: family.code,
      name: family.name,
      sort_order: family.sort_order,
      indicators_count: family.catalog_controls.count
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
      baseline_levels: control.baseline_levels
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
