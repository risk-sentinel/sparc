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
  # Federation export/import are peer-to-peer (federate permission + a known
  # peer). The #646 create endpoint is a normal authenticated write — any API
  # user may add a source (org/boundary-scoped by default).
  before_action :authorize_federate!, only: %i[export import]
  before_action :set_peer, only: %i[export import]

  # POST /api/v1/authoritative_sources
  #
  # Add a library source (#646). Org/boundary-scoped by default; pass
  # instance_wide=true to request instance-wide availability (granted directly
  # if the caller has promotion authority, else queued for approval). The web
  # UI is a thin client over this endpoint.
  def create
    result = AuthoritativeSourceCreator.call(
      actor: current_user,
      attrs: create_params,
      instance_wide: params[:instance_wide]
    )

    if result.success?
      audit_log("authoritative_source_created", subject: result.resource,
                metadata: { title: result.resource.title, availability: result.message })
      render json: {
        data: serialize_back_matter_resource(result.resource),
        message: result.message
      }, status: :created
    else
      render json: { error: result.error }, status: :unprocessable_entity
    end
  end

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

  def create_params
    params.require(:back_matter_resource)
          .permit(:title, :description, :href, :rel, :media_type)
  end

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
