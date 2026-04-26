# Federation peer CRUD + sync (#372).
#
# All endpoints require `back_matter.federate` permission (or admin).
# Service tokens and signing secrets are write-only — they are never
# echoed back in responses.
#
# Endpoints:
#   GET    /api/v1/federation_peers
#   GET    /api/v1/federation_peers/:id
#   POST   /api/v1/federation_peers
#   PATCH  /api/v1/federation_peers/:id
#   DELETE /api/v1/federation_peers/:id
#   POST   /api/v1/federation_peers/:id/sync
class Api::V1::FederationPeersController < Api::V1::BaseController
  before_action :authorize_federate!
  before_action :set_peer, only: %i[show update destroy sync]

  def index
    peers = FederationPeer.order(:name)
    render json: { data: peers.map { |p| serialize_peer(p) }, meta: { count: peers.size } }
  end

  def show
    render json: { data: serialize_peer(@peer, detailed: true) }
  end

  def create
    @peer = FederationPeer.new(peer_params_for_create)
    apply_secrets(@peer)

    if @peer.save
      audit_log("federation_peer_created", subject: @peer,
                metadata: { name: @peer.name, base_url: @peer.base_url })
      render json: { data: serialize_peer(@peer, detailed: true) }, status: :created
    else
      render json: { error: "Validation failed", details: @peer.errors.full_messages },
             status: :unprocessable_entity
    end
  end

  def update
    @peer.assign_attributes(peer_params_for_update)
    apply_secrets(@peer)

    if @peer.save
      audit_log("federation_peer_updated", subject: @peer, metadata: { name: @peer.name })
      render json: { data: serialize_peer(@peer, detailed: true) }
    else
      render json: { error: "Validation failed", details: @peer.errors.full_messages },
             status: :unprocessable_entity
    end
  end

  def destroy
    audit_log("federation_peer_deleted", subject: @peer, metadata: { name: @peer.name })
    @peer.destroy
    render json: { data: { id: @peer.id, deleted: true } }
  end

  # POST /api/v1/federation_peers/:id/sync — pull authoritative resources
  def sync
    result = AuthoritativeSourceFederationService.pull(peer: @peer, actor: current_user)

    if result.success?
      audit_log("federation_peer_synced", subject: @peer,
                metadata: { imported: result.imported.size,
                            skipped:  result.skipped.size,
                            errors:   result.errors.size,
                            bundle_uuid: result.bundle_uuid })
      render json: {
        data: {
          peer:        serialize_peer(@peer.reload),
          imported:    result.imported.size,
          skipped:     result.skipped.size,
          errors:      result.errors,
          bundle_uuid: result.bundle_uuid
        }
      }
    else
      render json: { error: result.error }, status: result.status_code
    end
  end

  private

  def set_peer
    @peer = FederationPeer.find(params[:id])
  end

  def peer_params_for_create
    params.require(:federation_peer).permit(:name, :base_url, :enabled, public_metadata: {})
  end

  def peer_params_for_update
    params.require(:federation_peer).permit(:base_url, :enabled, public_metadata: {})
  end

  # service_token and signing_secret are write-only and live outside the
  # mass-assignment surface so they are explicit at every call site.
  def apply_secrets(peer)
    nested = params.fetch(:federation_peer, {})
    peer.service_token  = nested[:service_token]  if nested.key?(:service_token)
    peer.signing_secret = nested[:signing_secret] if nested.key?(:signing_secret)
  end

  def serialize_peer(peer, detailed: false)
    data = {
      id:                  peer.id,
      name:                peer.name,
      base_url:            peer.base_url,
      enabled:             peer.enabled,
      last_synced_at:      peer.last_synced_at&.iso8601,
      last_sync_status:    peer.last_sync_status,
      service_token_set:   peer.encrypted_service_token.present?,
      signing_secret_set:  peer.encrypted_signing_secret.present?,
      created_at:          peer.created_at.iso8601,
      updated_at:          peer.updated_at.iso8601
    }
    data[:public_metadata] = peer.public_metadata if detailed
    data
  end

  def authorize_federate!
    return if current_user.admin?
    return if current_user.has_permission?("back_matter.federate")

    raise NotAuthorizedError, "Not authorized to manage federation peers"
  end
end
