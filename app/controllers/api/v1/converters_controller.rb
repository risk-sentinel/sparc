# frozen_string_literal: true

# #1011 — REST API for framework converters: the lookup tables that map source
# framework identifiers (CCI, CIS, OVAL, STIG, AWS Config, AWS Security Hub) to
# NIST SP 800-53 control ids.
#
#   GET    /api/v1/converters
#   POST   /api/v1/converters
#   GET    /api/v1/converters/:id
#   PATCH  /api/v1/converters/:id
#   DELETE /api/v1/converters/:id
#   POST   /api/v1/converters/:id/refresh
#   GET    /api/v1/converters/:id/export
#   GET    /api/v1/converters/:converter_id/entries
#   POST   /api/v1/converters/:converter_id/entries
#   DELETE /api/v1/converters/:converter_id/entries/:id
#
# Found by the missing-endpoint axis of #995. Converters ingest external
# mappings, and every refresh and import could be triggered only from a browser
# — the surface most obviously wanted by automation was the one with no API.
#
# **The three web refresh actions collapse into ONE endpoint here.**
# `refresh_cci`, `refresh_aws_config` and `refresh_aws_security_hub` differ only
# in which `converter_type` they will accept, and each rejects the other two.
# A caller already knows the converter's type — it is on the record — so three
# paths that each refuse two thirds of the collection is a UI affordance, not an
# API. `ConverterRefreshJob::SERVICE_BY_TYPE` decides what actually runs, and a
# type with no registered service is refused by name.
#
# Refresh is ASYNCHRONOUS. The endpoint returns 202 with the converter in
# `processing`; poll `show` for the outcome. Reporting 200 for work that has not
# happened is the shape #995 exists to stop.
#
# NIST 800-53 Controls:
#   AC-3 Access Enforcement (converters.write), AU-12 Audit Record Generation,
#   CM-6 Configuration Settings
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
class Api::V1::ConvertersController < Api::V1::BaseController
  before_action :set_converter, only: %i[show update destroy refresh export]
  before_action :authorize_read!
  before_action :authorize_write!, only: %i[create update destroy refresh]

  # GET /api/v1/converters
  def index
    scope = Converter.order(:name)
    scope = scope.where(converter_type: params[:converter_type]) if params[:converter_type].present?
    scope = scope.where(status: params[:status]) if params[:status].present?
    result = paginate(scope, items: 50)

    render json: {
      data: result[:data].map { |converter| serialize(converter) },
      meta: result[:meta]
    }
  end

  # GET /api/v1/converters/:id
  def show
    render json: { data: serialize(@converter, detailed: true) }
  end

  # POST /api/v1/converters
  def create
    converter = Converter.new(converter_params)
    converter.save!

    audit_log("converter_created", subject: converter, metadata: { name: converter.name })
    render json: { data: serialize(converter, detailed: true) }, status: :created
  end

  # PATCH /api/v1/converters/:id
  def update
    @converter.update!(converter_params)

    audit_log("converter_updated", subject: @converter, metadata: { name: @converter.name })
    render json: { data: serialize(@converter, detailed: true) }
  end

  # DELETE /api/v1/converters/:id
  def destroy
    name = @converter.name
    entries = @converter.converter_entries.count
    @converter.destroy!

    audit_log("converter_deleted", subject: @converter, metadata: { name: name })
    render json: {
      data: { id: @converter.id, name: name, deleted: true, entries_deleted: entries }
    }
  end

  # POST /api/v1/converters/:id/refresh
  def refresh
    service = ConverterRefreshJob::SERVICE_BY_TYPE[@converter.converter_type]
    unless service
      return render json: {
        error: "This converter type cannot be refreshed.",
        details: [ "converter_type '#{@converter.converter_type}' has no registered refresh service" ],
        expected: ConverterRefreshJob::SERVICE_BY_TYPE.keys
      }, status: :unprocessable_content
    end

    # Re-entrancy guard, matching the web path: a second refresh while one is
    # running would race the first for the same rows.
    if @converter.status == "processing"
      return render json: {
        error: "A refresh is already in progress for this converter.",
        details: [ "status is 'processing'" ]
      }, status: :conflict
    end

    @converter.update!(status: "processing", error_message: nil)
    ConverterRefreshJob.perform_later(@converter.id)

    audit_log("converter_refresh_started", subject: @converter,
              metadata: { name: @converter.name, converter_type: @converter.converter_type })

    render json: {
      data: serialize(@converter.reload, detailed: true).merge(
        refresh: { enqueued: true, service: service,
                   note: "Refresh runs in the background. Poll this converter for status." }
      )
    }, status: :accepted
  end

  # GET /api/v1/converters/:id/export
  def export
    audit_log("converter_exported", subject: @converter,
              metadata: { name: @converter.name, format: "json" })

    render json: {
      data: serialize(@converter, detailed: true).merge(
        entries: @converter.converter_entries.order(:source_id).map { |e| serialize_entry(e) }
      )
    }
  end

  private

  # Converters are slug-addressed in the web routes; an id works too so a
  # caller can use what a list response gave them.
  def set_converter
    param = params[:id].to_s
    @converter = Converter.find_by(slug: param) || Converter.find(param)
  end

  def converter_params
    permit_strictly(:converter,
      :name, :description, :converter_type, :version,
      :status, :source_framework, :target_framework
    )
  end

  def serialize(converter, detailed: false)
    data = {
      id: converter.id,
      uuid: converter.uuid,
      slug: converter.slug,
      name: converter.name,
      converter_type: converter.converter_type,
      status: converter.status,
      source_framework: converter.source_framework,
      target_framework: converter.target_framework,
      entry_count: converter.converter_entries.count,
      refreshable: ConverterRefreshJob::SERVICE_BY_TYPE.key?(converter.converter_type)
    }

    if detailed
      data[:description] = converter.description
      data[:version] = converter.version
      # Surfaced on the record rather than only in logs: a converter left in
      # `failed` says nothing about why unless the reason travels with it.
      data[:error_message] = converter.error_message
      data[:created_at] = converter.created_at.utc.iso8601
      data[:updated_at] = converter.updated_at.utc.iso8601
    end

    data
  end

  def serialize_entry(entry)
    {
      id: entry.id,
      source_id: entry.source_id,
      target_id: entry.target_id,
      relationship: entry.relationship,
      category: entry.category,
      remarks: entry.remarks
    }
  end

  # #919 removed `converters.read`: any authenticated user may read converters,
  # so the absence of a check here is the correct behaviour rather than an
  # oversight. Kept as a named no-op so the next reader does not "fix" it.
  def authorize_read! = nil

  def authorize_write!
    return if current_user.admin?
    return if current_user.has_permission?("converters.write")

    raise NotAuthorizedError, "Not authorized to modify converters"
  end
end
