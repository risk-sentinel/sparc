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
  before_action :set_source, only: %i[show update destroy restore]
  before_action :authorize_write!, only: %i[update destroy restore]

  # GET /api/v1/authoritative_sources
  #
  # #1039 — this path had NO index and NO show, because it was declared as a
  # SINGULAR `resource` and Rails does not generate them for one. Scoped the
  # same way the web screen scopes: globally-available plus the caller's own
  # organizations, everything for an instance admin.
  # Paginated, and publishing the #1019 envelope. It first returned the whole
  # collection with no `meta`, which failed the contract sweep and — on an
  # instance holding 978 sources — sent all of them on every call. Nothing
  # consumes this endpoint yet (it shipped unreleased), so the shape is free to
  # be the standard one rather than a second thing clients must special-case.
  def index
    scope = visible_sources
    scope = scope.where(archived_at: nil) unless ActiveModel::Type::Boolean.new.cast(params[:include_archived])

    result = paginate(scope.order(:title))
    render json: {
      data: result[:data].map { |r| serialize_back_matter_resource(r, detailed: true) },
      meta: result[:meta]
    }
  end

  # GET /api/v1/authoritative_sources/:id
  def show
    render json: { data: serialize_back_matter_resource(@source, detailed: true) }
  end

  # PATCH /api/v1/authoritative_sources/:id
  def update
    if @source.update(update_params)
      audit_log("authoritative_source_updated", subject: @source,
                metadata: { title: @source.title })
      render json: { data: serialize_back_matter_resource(@source, detailed: true) }
    else
      render json: { error: "Update failed", details: @source.errors.full_messages },
             status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/authoritative_sources/:id
  #
  # ARCHIVES. These resources participate in federation and promotion, so a
  # hard delete strands a federated copy on a peer. Returns the archived record
  # rather than a bare 204 so a client can tell what actually happened — a
  # DELETE that does not delete is the kind of contract surprise #995 exists to
  # catch, and it is written on the endpoint page.
  def destroy
    @source.update!(archived_at: Time.current)
    audit_log("authoritative_source_archived", subject: @source,
              metadata: { title: @source.title })
    render json: { data: serialize_back_matter_resource(@source, detailed: true), archived: true }
  end

  # POST /api/v1/authoritative_sources/:id/restore
  def restore
    @source.update!(archived_at: nil)
    audit_log("authoritative_source_restored", subject: @source,
              metadata: { title: @source.title })
    render json: { data: serialize_back_matter_resource(@source, detailed: true), archived: false }
  end

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
          imported:    result.imported.map { |r| serialize_back_matter_resource(r, detailed: true) },
          skipped:     result.skipped,
          errors:      result.errors
        }
      }
    else
      render json: { error: result.error }, status: result.status_code
    end
  end

  private

  def set_source
    @source = BackMatterResource.find(params[:id])
    return if current_user.admin?
    return if @source.globally_available? ||
              current_user.organizations.ids.include?(@source.organization_id)

    raise NotAuthorizedError, "Not authorized for that authoritative source"
  end

  def visible_sources
    return BackMatterResource.all if current_user.admin?

    org_ids = current_user.organizations.ids
    if org_ids.any?
      BackMatterResource.where("globally_available = ? OR organization_id IN (?)", true, org_ids)
    else
      BackMatterResource.where(globally_available: true)
    end
  end

  def authorize_write!
    return if current_user.admin?
    return if current_user.has_permission?("back_matter.write")

    raise NotAuthorizedError, "Not authorized to change authoritative sources"
  end

  def update_params
    permit_strictly(:back_matter_resource,
      :title, :description, :href, :rel, :media_type,
      :organization_id, :provided_by_team, :provided_by_contact)
  end

  def create_params
    # #1021 — was `params.require(...)` and `.permit(...)` on separate lines, so
    # the #995 conversion's single-line pattern did not match it and this
    # endpoint kept dropping unrecognized fields in silence.
    # The provenance pair (#1039) has to be accepted on create as well as
    # update: the web form submits both on the very first save, and a strict
    # allowlist that knows them only on `update` rejects the create outright.
    permit_strictly(:back_matter_resource,
      :title, :description, :href, :rel, :media_type,
      :provided_by_team, :provided_by_contact)
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
