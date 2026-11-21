# frozen_string_literal: true

# #1354 — the materials a connection's Class A certification rests on
# (FedRAMP FRC-CLA-EAM): a SOC 2 Type II report, a bridge letter, a Readiness
# Assessment Report, a Security Assessment Plan, and the like.
#
#   GET  /api/v1/exchange_connections/:exchange_connection_id/certification_materials
#   POST /api/v1/exchange_connections/:exchange_connection_id/certification_materials
#        multipart: `file`, `kind` (one of ExchangeConnection::CLASS_A_MATERIALS)
#
# Each is stored by SHA-256 as a received document of the connection's
# boundary, never schema-checked, and decided there like any other
# (POST /api/v1/authorization_boundaries/:id/received_documents/:id/accept,
# respond, reject; exchange.review on the boundary, and never by the person
# who added it).
#
# Adding one needs what managing the connection needs: `connections.manage`
# across the instance, or an instance administrator.
#
# NIST SP 800-53: CA-3, CA-6, SA-9, AC-3, AU-12.
class Api::V1::ExchangeCertificationMaterialsController < Api::V1::BaseController
  before_action :authorize_manage!
  before_action :set_connection

  def index
    scope = @connection.received_documents.certification_materials.recent
    result = paginate(scope)
    render json: { data: result[:data].map { |doc| serialize(doc) }, meta: result[:meta] }
  end

  def create
    file = params[:file]
    unless file.respond_to?(:read)
      return render(json: { error: "No file supplied", note: "Send a multipart `file` field and a `kind`" },
                    status: :unprocessable_content)
    end

    outcome = CertificationMaterialService.call(
      connection: @connection, kind: params[:kind], bytes: file.read, filename: file.original_filename,
      content_type: file.content_type, received_by: current_user
    )
    render json: { data: serialize(outcome.document), status: outcome.status.to_s },
           status: outcome.stored? ? :created : :ok
  rescue CertificationMaterialService::Error => e
    render json: { error: e.message, details: [ "Kinds: #{ExchangeConnection::CLASS_A_MATERIALS.keys.join(', ')}" ] },
           status: :unprocessable_content
  end

  private

  def set_connection
    @connection = ExchangeConnection.find(params[:exchange_connection_id])
  end

  def serialize(doc)
    path = "/api/v1/authorization_boundaries/#{doc.authorization_boundary_id}/received_documents/#{doc.id}"
    {
      id: doc.id,
      exchange_connection_id: doc.exchange_connection_id,
      kind: doc.document_type,
      kind_label: ExchangeConnection::CLASS_A_MATERIALS[doc.document_type],
      filename: doc.filename,
      content_type: doc.content_type,
      sha256: doc.sha256,
      byte_size: doc.byte_size,
      state: doc.state,
      received_at: doc.received_at&.utc&.iso8601,
      received_by_id: doc.received_by_id,
      reviewed_at: doc.reviewed_at&.utc&.iso8601,
      links: { received_document: path, file: "#{path}/file" }
    }
  end

  def authorize_manage!
    return if current_user.instance_administrator?
    return if current_user.has_permission?("connections.manage")

    raise NotAuthorizedError, "Not authorized to manage exchange connections"
  end
end
