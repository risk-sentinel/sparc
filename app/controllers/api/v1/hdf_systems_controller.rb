# frozen_string_literal: true

# #1179 — the authorization boundary as an HDF `hdf-system` document:
#
#   GET /api/v1/authorization_boundaries/:authorization_boundary_id/hdf_system
#
# `:authorization_boundary_id` is the numeric id, the boundary uuid, or the
# slug. The uuid form is the one other HDF documents cite as `systemRef`,
# because it survives a rename and a slug does not.
#
# The response body IS the artefact — raw hdf-system JSON, not wrapped — so it
# can be saved and passed straight to `hdf validate --type system` or
# `hdf evidence build --system`.
#
# CACHING. The ETag is STRONG and is the SHA-256 of the exact response bytes.
# The export is deterministic (no timestamps, fixed ordering), so equal bytes
# mean an equal document and nothing else can. A timestamp-derived tag was the
# alternative and it is wrong here: the document reads the system-owner
# membership, the organization, the CDEFs' component index and the SSP's
# control fields, and editing most of those touches no `updated_at` the
# boundary can see — so it would answer 304 for a document that had changed.
# A matching If-None-Match gets 304 and an empty body. The CLI validation still
# runs on every request, because the tag is only known once the document has
# been built and validated.
#
# AUTHORIZATION. The document is the boundary's, and it also carries the SSP's
# implementation narrative (as control-designation descriptions), so it needs
# BOTH `authorization_boundaries.read` and `ssp.read` on this boundary. Either
# alone would let a reader of one see content gated by the other.
#
# NIST 800-53: IA-2 (token auth), AC-3/AC-6 (boundary-scoped RBAC, both
# permissions), CM-8 (component inventory), AU-12 (hdf_system_exported).
class Api::V1::HdfSystemsController < Api::V1::BaseController
  UUID_FORMAT = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

  before_action :set_boundary
  before_action :authorize_read!

  rescue_from HdfSystemExportService::Unexportable do |e|
    render json: { error: "Boundary cannot be exported as an hdf-system document", details: e.message },
           status: :unprocessable_content
  end

  rescue_from HdfSystemExportService::InvalidDocument do |e|
    render json: { error: "hdf-system document failed schema validation", details: e.errors },
           status: :unprocessable_content
  end

  rescue_from HdfRunner::Error do |e|
    render json: { error: "hdf-system validation failed", details: e.message },
           status: :unprocessable_content
  end

  # GET .../hdf_system
  def show
    service = HdfSystemExportService.new(@boundary)
    doc = service.export
    body = JSON.generate(doc)

    response.headers["ETag"] = %("#{Digest::SHA256.hexdigest(body)}")
    return head(:not_modified) if request.fresh?(response)

    audit_log("hdf_system_exported", subject: @boundary,
              metadata: { components: doc["components"].size,
                          excluded_components: service.excluded_components.size,
                          control_designations: Array(doc["controlDesignations"]).size })
    render json: body
  end

  private

  def set_boundary
    key = params[:authorization_boundary_id].to_s
    @boundary =
      if key.match?(/\A\d+\z/)
        AuthorizationBoundary.find(key)
      elsif key.match?(UUID_FORMAT)
        AuthorizationBoundary.find_by(uuid: key.downcase) || AuthorizationBoundary.find_by!(slug: key)
      else
        AuthorizationBoundary.find_by!(slug: key)
      end
  end

  def authorize_read!
    return if current_user.instance_administrator?

    missing = %w[authorization_boundaries.read ssp.read].reject do |key|
      current_user.has_permission?(key, authorization_boundary_id: @boundary.id)
    end
    return if missing.empty?

    raise NotAuthorizedError, "Not authorized to export this boundary's hdf-system document " \
                              "(missing: #{missing.join(', ')})"
  end
end
