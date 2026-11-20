# frozen_string_literal: true

# #1354 — the documents a connection pulls, each set explicitly (owner,
# 2026-11-20: crawl the root to find documents, pull only the explicit ones).
#
#   GET    /api/v1/exchange_connections/:exchange_connection_id/document_sources
#   POST   /api/v1/exchange_connections/:exchange_connection_id/document_sources
#   PATCH  /api/v1/exchange_connections/:exchange_connection_id/document_sources/:id
#   DELETE /api/v1/exchange_connections/:exchange_connection_id/document_sources/:id
#
# Body root `exchange_document_source`: url (https), format (fedramp | oscal |
# hdf | xccdf), document_type, pull_interval_hours (1–744), enabled.
#
# Same authority as the connection: `connections.manage` across the instance,
# or an instance administrator. A document's host becomes one of the
# connection's pinned hosts, so adding one widens what SPARC may reach.
#
# NIST SP 800-53: CA-3, SA-9, AC-3 / AC-6, IA-9 (each address's host is a
# pin), AU-12 (each change audited).
class Api::V1::ExchangeDocumentSourcesController < Api::V1::BaseController
  FIELDS = %i[url format document_type pull_interval_hours enabled].freeze

  before_action :authorize_manage!
  before_action :set_connection
  before_action :set_source, only: %i[update destroy]

  # Shared with the connection's detailed response.
  def self.serialize(source)
    {
      id: source.id,
      exchange_connection_id: source.exchange_connection_id,
      url: source.url,
      format: source.format,
      document_type: source.document_type,
      pull_interval_hours: source.pull_interval_hours,
      enabled: source.enabled,
      last_pulled_at: source.last_pulled_at&.utc&.iso8601,
      last_status: source.last_status,
      last_sha256: source.last_sha256,
      last_error: source.last_error,
      created_at: source.created_at.utc.iso8601,
      updated_at: source.updated_at.utc.iso8601
    }
  end

  # GET .../document_sources
  def index
    rows = @connection.document_sources.order(:id).map { |s| self.class.serialize(s) }
    render json: { data: rows, meta: whole_collection(rows) }
  end

  # POST .../document_sources
  def create
    source = @connection.document_sources.new(source_params)
    if source.save
      audit("exchange_document_source_created", source)
      render json: { data: self.class.serialize(source) }, status: :created
    else
      render_invalid(source)
    end
  end

  # PATCH .../document_sources/:id
  def update
    if @source.update(source_params)
      audit("exchange_document_source_updated", @source, changed: @source.saved_changes.keys - %w[updated_at])
      render json: { data: self.class.serialize(@source) }
    else
      render_invalid(@source)
    end
  end

  # DELETE .../document_sources/:id — versions already received stay on record.
  def destroy
    audit("exchange_document_source_deleted", @source)
    @source.destroy!
    render json: { data: { id: @source.id, deleted: true } }
  end

  private

  def set_connection
    @connection = ExchangeConnection.find(params[:exchange_connection_id])
  end

  def set_source
    @source = @connection.document_sources.find(params[:id])
  end

  def source_params
    permit_strictly(:exchange_document_source, *FIELDS)
  end

  def render_invalid(source)
    render json: { error: "Validation failed", details: source.errors.full_messages },
           status: :unprocessable_content
  end

  def audit(action, source, **extra)
    audit_log(action, subject: @connection,
              metadata: { document_source_id: source.id, url: source.url, format: source.format,
                          document_type: source.document_type, enabled: source.enabled, **extra }.compact)
  end

  def authorize_manage!
    return if current_user.instance_administrator?
    return if current_user.has_permission?("connections.manage")

    raise NotAuthorizedError, "Not authorized to manage exchange connections"
  end
end
