# REST API for the entries inside a Control Mapping (#945).
#
# The mapping SHELL had a full API; its entries had none at all. The only way
# to add or remove a control-to-control relationship was the web form, which
# breaks the rule that the UI is never the only way to perform a mutation — and
# the web form had no `update` either, so an entry could be created and deleted
# but never corrected.
#
# GET    /api/v1/control_mappings/:control_mapping_id/entries      — list
# POST   /api/v1/control_mappings/:control_mapping_id/entries      — create
# PATCH  /api/v1/control_mappings/:control_mapping_id/entries/:id  — update
# DELETE /api/v1/control_mappings/:control_mapping_id/entries/:id  — delete
#
# The identifiers are validated on the MODEL against the mapping's own source
# and target catalogs, so this endpoint is guarded by the same rule as the form
# rather than by a copy of it.
#
# NIST 800-53 Controls:
#   AC-3 Access Enforcement (Bearer token auth, write gate)
#   AC-6 Least Privilege (mappings.write or admin for mutations)
#   AU-12 Audit Record Generation (mutations logged via audit_log)
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
class Api::V1::ControlMappingEntriesController < Api::V1::BaseController
  # Authorize BEFORE finding, so an unpermissioned caller gets 403 rather than
  # a 404 that leaks whether the mapping exists (#575 Path D).
  before_action :authorize_mappings_write!, only: [ :create, :update, :destroy ]
  before_action :set_mapping
  before_action :set_entry, only: [ :update, :destroy ]

  def index
    scope = @mapping.control_mapping_entries
    result = paginate(scope)
    render json: {
      data: result[:data].map { |entry| serialize_entry(entry) },
      meta: result[:meta].merge(unresolved: scope.reject(&:resolved?).length)
    }
  end

  def create
    entry = @mapping.control_mapping_entries.new(entry_params)

    if entry.save
      audit_log("api_mapping_entry_created", subject: entry, metadata: audit_metadata(entry))
      render json: { data: serialize_entry(entry) }, status: :created
    else
      render json: { errors: entry.errors.to_hash(true) }, status: :unprocessable_content
    end
  end

  def update
    if @entry.update(entry_params)
      audit_log("api_mapping_entry_updated", subject: @entry, metadata: audit_metadata(@entry))
      render json: { data: serialize_entry(@entry) }
    else
      render json: { errors: @entry.errors.to_hash(true) }, status: :unprocessable_content
    end
  end

  def destroy
    audit_log("api_mapping_entry_deleted", subject: @entry, metadata: audit_metadata(@entry))
    @entry.destroy
    head :no_content
  end

  private

  def authorize_mappings_write!
    return if current_user&.admin?
    return if current_user&.has_permission?("mappings.write")

    render json: { error: "Forbidden" }, status: :forbidden
  end

  # Accept either numeric id or slug, matching the mappings controller.
  def set_mapping
    id_or_slug = params[:control_mapping_id].to_s
    @mapping = if id_or_slug.match?(/\A\d+\z/)
      ControlMapping.find_by!(id: id_or_slug)
    else
      ControlMapping.find_by!(slug: id_or_slug)
    end
  end

  def set_entry
    @entry = @mapping.control_mapping_entries.find(params[:id])
  end

  def entry_params
    permit_strictly(:control_mapping_entry,
      :source_control_id, :source_type,
      :target_control_id, :target_type,
      :relationship, :matching_rationale, :remarks, :row_order
    )
  end

  def audit_metadata(entry)
    {
      mapping_id: @mapping.id,
      source_control_id: entry.source_control_id,
      target_control_id: entry.target_control_id,
      relationship: entry.relationship
    }
  end

  def serialize_entry(entry)
    {
      id: entry.id,
      uuid: entry.uuid,
      source_control_id: entry.source_control_id,
      source_type: entry.source_type,
      target_control_id: entry.target_control_id,
      target_type: entry.target_type,
      relationship: entry.relationship,
      matching_rationale: entry.matching_rationale,
      remarks: entry.remarks,
      row_order: entry.row_order,
      # Reported so an integrator can find entries stored before the identifiers
      # were validated, without SPARC rewriting what someone recorded.
      resolved: entry.resolved?,
      unresolved_sides: entry.unresolved_sides,
      created_at: entry.created_at.iso8601,
      updated_at: entry.updated_at.iso8601
    }
  end
end
