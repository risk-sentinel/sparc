# Federation export / import endpoints for authoritative back-matter
# resources (#372). Used by peer SPARC instances to pre-populate
# leveraged-authorization references (#396).
#
# Endpoints:
#   GET  /api/v1/authoritative_sources/export
#        Returns a signed envelope of this instance's authoritative
#        resources for the calling peer. The peer is identified by name
#        via the `peer` query param; the caller must hold an API token
#        with the `back_matter.federate` permission.
#
#   POST /api/v1/authoritative_sources/import
#        Accepts a signed envelope from a configured peer and imports
#        each contained resource. The peer is identified by name via
#        the `peer` field in the request body.
#
# NIST 800-53:
#   AC-3 / AC-4 / AC-20 / AU-2 / SC-8 / SC-12 / SC-13
class Api::V1::AuthoritativeSourcesController < Api::V1::BaseController
  before_action :authorize_federate!
  before_action :set_peer

  # GET /api/v1/authoritative_sources/export
  def export
    since = parse_since(params[:since])
    bundle = AuthoritativeSourceFederationService.build_export_bundle(
      peer:  @peer,
      since: since,
      scope: :authoritative
    )

    audit_log("authoritative_sources_export",
              metadata: { peer: @peer.name, bundle_uuid: bundle.dig("payload") })
    render json: bundle
  end

  # POST /api/v1/authoritative_sources/import
  def import
    envelope = params[:envelope]&.to_unsafe_h || params.except(:peer, :controller, :action).to_unsafe_h
    result = AuthoritativeSourceFederationService.import_bundle(
      envelope, peer: @peer, actor: current_user
    )

    if result.success?
      audit_log("authoritative_sources_import",
                metadata: { peer: @peer.name, imported: result.imported.size,
                            skipped: result.skipped.size, errors: result.errors.size,
                            bundle_uuid: result.bundle_uuid })
      render json: {
        data: {
          bundle_uuid: result.bundle_uuid,
          imported:    result.imported.map { |r| serialize_back_matter_resource(r) },
          skipped:     result.skipped,
          errors:      result.errors
        }
      }
    else
      render json: { error: result.error }, status: result.status_code
    end
  end

  private

  def authorize_federate!
    return if current_user.admin?
    return if current_user.has_permission?("back_matter.federate")

    raise NotAuthorizedError, "Not authorized to federate authoritative sources"
  end

  def set_peer
    name = params[:peer].presence || params.dig(:envelope, :key_id)
    @peer = FederationPeer.find_by(name: name)
    return if @peer

    render json: { error: "Unknown peer #{name.inspect}" }, status: :unprocessable_entity
  end

  def parse_since(value)
    return nil if value.blank?

    Time.iso8601(value)
  rescue ArgumentError
    nil
  end
end
