# frozen_string_literal: true

# #1354 — connections to other systems SPARC pulls FedRAMP, OSCAL, HDF and
# XCCDF documents from: the API the Settings screen is a client of.
#
#   GET    /api/v1/exchange_connections
#   POST   /api/v1/exchange_connections
#   GET    /api/v1/exchange_connections/:id
#   PATCH  /api/v1/exchange_connections/:id
#   DELETE /api/v1/exchange_connections/:id
#   POST   /api/v1/exchange_connections/:id/pull             pull every enabled document now
#   POST   /api/v1/exchange_connections/:id/discover         list the root's document links; stores nothing
#   POST   /api/v1/exchange_connections/:id/test_connection  fetch and validate each document; stores nothing
#
# Instance-level authority: `connections.manage` held across the instance, or
# an instance administrator. A grant on one boundary is not enough: a
# connection decides which outside hosts SPARC reaches and where their
# documents land.
#
# The credential SPARC sends to the other system is WRITE-ONLY: accepted as
# `credential`, stored encrypted, and never returned. Responses say only
# whether one is set (`credential_set`).
#
# NIST SP 800-53: CA-3 (information exchange agreements are registered here),
# SA-9 (external system services), AC-3 / AC-6 (instance-level permission),
# IA-5 (the credential is write-only and encrypted at rest), IA-9 (host and
# TLS key pins), AU-12 (create, update, delete, pull, discover and test are
# audited).
class Api::V1::ExchangeConnectionsController < Api::V1::BaseController
  CONNECTION_FIELDS = %i[name authorization_boundary_id fedramp_id certification_class certification_type
                         root_url auth_scheme auth_header_name enabled].freeze
  LIST_FIELDS = %i[spki_sha256 allowed_cidrs].freeze

  before_action :authorize_manage!
  before_action :set_connection, except: %i[index create]

  # GET /api/v1/exchange_connections
  def index
    scope = ExchangeConnection.includes(:authorization_boundary, :document_sources).order(:name)
    scope = scope.where(authorization_boundary_id: boundary_id_param(params[:authorization_boundary_id])) if params[:authorization_boundary_id].present?
    result = paginate(scope)
    render json: { data: result[:data].map { |c| serialize(c) }, meta: result[:meta] }
  end

  # GET /api/v1/exchange_connections/:id
  def show
    render json: { data: serialize(@connection, detailed: true) }
  end

  # POST /api/v1/exchange_connections
  def create
    @connection = ExchangeConnection.new(connection_params)
    @connection.created_by = current_user
    apply_credential(@connection)

    if @connection.save
      audit_log("exchange_connection_created", subject: @connection, metadata: audit_metadata(@connection))
      render json: { data: serialize(@connection, detailed: true) }, status: :created
    else
      render_invalid(@connection)
    end
  end

  # PATCH /api/v1/exchange_connections/:id
  def update
    @connection.assign_attributes(connection_params)
    credential_changed = apply_credential(@connection)

    if @connection.save
      audit_log("exchange_connection_updated", subject: @connection,
                metadata: audit_metadata(@connection).merge(changed: @connection.saved_changes.keys - %w[updated_at encrypted_credential],
                                                            credential_changed: credential_changed))
      render json: { data: serialize(@connection, detailed: true) }
    else
      render_invalid(@connection)
    end
  end

  # DELETE /api/v1/exchange_connections/:id
  #
  # Received versions stay on record (their connection is cleared); only the
  # connection and its document addresses go.
  def destroy
    audit_log("exchange_connection_deleted", subject: @connection, metadata: audit_metadata(@connection))
    @connection.destroy!
    render json: { data: { id: @connection.id, deleted: true } }
  end

  # POST /api/v1/exchange_connections/:id/pull
  #
  # Pulls every enabled document of the connection now, whether or not its
  # interval has passed. Each result is recorded on its document and in the
  # audit log by ExchangePullService.
  def pull
    return render(json: { error: "The connection is disabled" }, status: :unprocessable_content) unless @connection.enabled?

    sources = @connection.document_sources.enabled.order(:id).to_a
    if sources.empty?
      return render(json: { error: "The connection has no enabled document to pull" }, status: :unprocessable_content)
    end

    results = sources.map { |source| pull_result(source, ExchangePullService.call(source, user: current_user)) }
    render json: { data: { connection: serialize(@connection.reload), results: results } }
  end

  # POST /api/v1/exchange_connections/:id/discover
  def discover
    found = ExchangeConnectionProbe.discover(@connection)
    audit_log("exchange_connection_discovered", subject: @connection,
              metadata: { root_url: found[:root_url], candidates: found[:candidates].size })
    render json: { data: found }
  rescue ExchangeConnectionProbe::Error => e
    probe_failed("exchange_connection_discovered", e)
  end

  # POST /api/v1/exchange_connections/:id/test_connection
  def test_connection
    report = ExchangeConnectionProbe.test(@connection)
    reached = report[:sources].count { |s| s[:reachable] }
    audit_log("exchange_connection_tested", subject: @connection,
              metadata: { sources: report[:sources].size, reachable: reached,
                          valid: report[:sources].count { |s| s.dig(:validation, :valid) } })
    render json: { data: report }
  rescue ExchangeConnectionProbe::Error => e
    probe_failed("exchange_connection_tested", e)
  end

  private

  def set_connection
    @connection = ExchangeConnection.find(params[:id])
  end

  # A configuration SPARC cannot fetch with is the caller's to fix (422); the
  # other system refusing or failing is a bad gateway (502).
  def probe_failed(action, error)
    audit_log(action, subject: @connection, metadata: { failed: true, reason: error.reason.to_s, error: error.message.slice(0, 300) })
    status = error.reason.in?(%i[configuration no_root_url]) ? :unprocessable_content : :bad_gateway
    render json: { error: error.message, reason: error.reason.to_s }, status: status
  end

  def pull_result(source, result)
    doc = result.document
    { document_source_id: source.id, url: source.url, status: result.status.to_s, error: result.error,
      received_document: doc && { id: doc.id, state: doc.state, sha256: doc.sha256, valid: doc.valid_document,
                                  url: "/api/v1/authorization_boundaries/#{doc.authorization_boundary_id}/received_documents/#{doc.id}" } }
  end

  def connection_params
    permitted = permit_strictly(:exchange_connection, *CONNECTION_FIELDS, *LIST_FIELDS,
                                spki_sha256: [], allowed_cidrs: [], also_accepts: %i[credential])
    if permitted.key?(:authorization_boundary_id)
      permitted[:authorization_boundary_id] = boundary_id_param(permitted[:authorization_boundary_id])
    end
    permitted
  end

  # A boundary may be named by id or slug, as on the boundary endpoints.
  def boundary_id_param(value)
    key = value.to_s
    return key if key.match?(/\A\d+\z/)

    AuthorizationBoundary.find_by(slug: key)&.id
  end

  # IA-5: write-only. Present (even blank) means "set it" (blank clears);
  # absent leaves it as it is. Returns whether it was touched.
  def apply_credential(connection)
    nested = params.fetch(:exchange_connection, {})
    return false unless nested.respond_to?(:key?) && nested.key?(:credential)

    connection.credential = nested[:credential]
    true
  end

  def render_invalid(connection)
    render json: { error: "Validation failed", details: connection.errors.full_messages },
           status: :unprocessable_content
  end

  def audit_metadata(connection)
    { name: connection.name, authorization_boundary_id: connection.authorization_boundary_id,
      root_url: connection.root_url, fedramp_id: connection.fedramp_id, enabled: connection.enabled }.compact
  end

  def serialize(connection, detailed: false)
    data = {
      id: connection.id,
      name: connection.name,
      authorization_boundary_id: connection.authorization_boundary_id,
      authorization_boundary_name: connection.authorization_boundary&.name,
      fedramp_id: connection.fedramp_id,
      certification_class: connection.certification_class,
      certification_type: connection.certification_type,
      root_url: connection.root_url,
      auth_scheme: connection.auth_scheme,
      auth_header_name: connection.auth_header_name,
      # IA-5: whether a credential is set, never the credential.
      credential_set: connection.credential?,
      pinned_hosts: connection.pinned_hosts,
      spki_sha256: connection.spki_sha256,
      allowed_cidrs: connection.allowed_cidrs,
      enabled: connection.enabled,
      last_pulled_at: connection.last_pulled_at&.utc&.iso8601,
      last_pull_status: connection.last_pull_status,
      last_error: connection.last_error,
      document_source_count: connection.document_sources.size,
      created_at: connection.created_at.utc.iso8601,
      updated_at: connection.updated_at.utc.iso8601
    }
    if detailed
      data[:document_sources] = connection.document_sources.sort_by(&:id).map do |source|
        Api::V1::ExchangeDocumentSourcesController.serialize(source)
      end
    end
    data
  end

  def authorize_manage!
    return if current_user.instance_administrator?
    return if current_user.has_permission?("connections.manage")

    raise NotAuthorizedError, "Not authorized to manage exchange connections"
  end
end
