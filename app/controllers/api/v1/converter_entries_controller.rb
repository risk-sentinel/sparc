# frozen_string_literal: true

# #1011 — REST API for the individual source→target rows inside a converter.
#
#   GET    /api/v1/converters/:converter_id/entries
#   POST   /api/v1/converters/:converter_id/entries
#   DELETE /api/v1/converters/:converter_id/entries/:id
#
# The entries ARE the mapping — a converter without them translates nothing —
# and they could be added or removed only from a browser.
#
# `index` is filterable by `source_id` and `target_id` because the question a
# caller actually has is "what does X map to", and paging through thousands of
# rows to answer it is not an answer.
#
# NIST 800-53 Controls:
#   AC-3 Access Enforcement (converters.write), AU-12 Audit Record Generation
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
class Api::V1::ConverterEntriesController < Api::V1::BaseController
  before_action :set_converter
  before_action :authorize_write!, only: %i[create destroy]

  # GET /api/v1/converters/:converter_id/entries
  def index
    scope = @converter.converter_entries.order(:source_id)
    scope = scope.where(source_id: params[:source_id]) if params[:source_id].present?
    scope = scope.where(target_id: params[:target_id]) if params[:target_id].present?
    result = paginate(scope, items: 100)

    render json: {
      data: result[:data].map { |entry| serialize(entry) },
      meta: result[:meta]
    }
  end

  # POST /api/v1/converters/:converter_id/entries
  def create
    entry = @converter.converter_entries.new(entry_params)
    entry.save!

    audit_log("converter_entry_created", subject: @converter,
              metadata: { converter: @converter.name,
                          source_id: entry.source_id, target_id: entry.target_id })

    render json: { data: serialize(entry) }, status: :created
  end

  # DELETE /api/v1/converters/:converter_id/entries/:id
  def destroy
    entry = @converter.converter_entries.find(params[:id])

    audit_log("converter_entry_deleted", subject: @converter,
              metadata: { converter: @converter.name,
                          source_id: entry.source_id, target_id: entry.target_id })
    entry.destroy!

    render json: { data: { id: entry.id, converter_id: @converter.id, deleted: true } }
  end

  private

  def set_converter
    param = params[:converter_id].to_s
    @converter = Converter.find_by(slug: param) || Converter.find(param)
  end

  def entry_params
    permit_strictly(:converter_entry,
      :source_id, :target_id, :relationship, :category, :remarks
    )
  end

  def serialize(entry)
    {
      id: entry.id,
      converter_id: entry.converter_id,
      source_id: entry.source_id,
      target_id: entry.target_id,
      relationship: entry.relationship,
      category: entry.category,
      remarks: entry.remarks
    }
  end

  def authorize_write!
    return if current_user.admin?
    return if current_user.has_permission?("converters.write")

    raise NotAuthorizedError, "Not authorized to modify converter entries"
  end
end
